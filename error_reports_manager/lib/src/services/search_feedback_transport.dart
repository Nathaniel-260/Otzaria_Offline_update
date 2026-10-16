import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:path/path.dart' as p;

import '../search_feedback/search_feedback_backoff.dart';
import '../search_feedback/search_feedback_events.dart';
import '../search_feedback/search_feedback_identity.dart';
import '../search_feedback/search_feedback_queue.dart';
import '../search_feedback/search_feedback_queue_lock.dart';
import '../search_feedback/search_feedback_sender.dart';

typedef SearchFeedbackUploadResult = ({int sent, int rejected, int remaining});

/// נושא מקטעים קיימים של אוצריא; אינו רושם פעילות חיפוש בעצמו.
class SearchFeedbackTransport {
  SearchFeedbackTransport(this.directory, {http.Client? client, Uri? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? Uri.parse('https://otzaria.org');

  final String directory;
  final http.Client _client;
  final Uri _baseUrl;
  bool _stopped = false;
  Completer<void> _abort = Completer<void>();
  int _backoffStep = 0;

  static String dirIn(String dataDir) => p.join(dataDir, 'search-feedback');

  static const Duration carriedWindow = Duration(days: 89);
  static const Duration plainWindow = Duration(days: 29);

  SearchFeedbackQueue _queue(String path) => SearchFeedbackQueue(
        () async => Directory(path),
        clock: DateTime.now,
      );

  Future<int> pending(String sourceDirectory) async {
    if (!await Directory(sourceDirectory).exists()) return 0;
    final queue = _queue(sourceDirectory);
    await queue.load();
    return queue.eventCount;
  }

  /// ההצעה כוללת רק אירועים קריאים עם מפתח שמאפשר איסוף.
  Future<int> pendingForCollection(String sourceDirectory) async {
    final identity = await SearchFeedbackIdentityStore(
      () async => Directory(sourceDirectory),
    ).load();
    if (identity == null || identity.blocked) return 0;
    final carried = await SearchFeedbackIdentityStore(
      () async => Directory(p.join(directory, identity.keyId)),
    ).load();
    if (carried?.blocked == true) return 0;
    return _pendingSendable(sourceDirectory);
  }

  Future<int> _pendingSendable(String sourceDirectory) async {
    if (!await Directory(sourceDirectory).exists()) return 0;
    final queue = _queue(sourceDirectory);
    var count = 0;
    await for (final file in Directory(sourceDirectory).list()) {
      if (file is! File) continue;
      final batch = await queue.read(p.basename(file.path));
      if (batch != null && !_isLocalOnly(batch)) {
        count += batch.eventLines.length;
      }
    }
    return count;
  }

  /// חסימת שרת אינה נעקפת בהסכמה חדשה של המשתמש.
  Future<bool> resumeAfterConsent(String sourceDirectory) async {
    if (!await Directory(sourceDirectory).parent.exists()) return false;
    final identity = await SearchFeedbackIdentityStore(
      () async => Directory(sourceDirectory),
    ).load();
    if (identity?.blocked == true) return false;
    if (identity != null) {
      final carriedIdentity = await SearchFeedbackIdentityStore(
        () async => Directory(p.join(directory, identity.keyId)),
      ).load();
      if (carriedIdentity?.blocked == true) return false;
    }
    await _queue(sourceDirectory).resume();
    return true;
  }

  Future<int> count() async {
    var count = 0;
    if (!await Directory(directory).exists()) return count;
    await for (final entity in Directory(directory).list()) {
      if (entity is! Directory) continue;
      count += await _pendingSendable(entity.path);
    }
    return count;
  }

  /// ההסכמה והיעדר תהליך פעיל נבדקים שוב לפני כל העברה.
  Future<int> collect(String sourceDirectory,
      {required Future<bool> Function() mayCollect}) async {
    if (!await mayCollect()) return 0;
    final identity = await SearchFeedbackIdentityStore(
      () async => Directory(sourceDirectory),
    ).load();
    if (identity == null || identity.blocked) return 0;
    await Directory(directory).create(recursive: true);
    final transportLock = await SearchFeedbackQueueLock.acquire(
      p.join(directory, 'transport.lock'),
    );
    try {
      final source = _queue(sourceDirectory);
      final destination = p.join(directory, identity.keyId);
      await Directory(destination).create(recursive: true);
      final destinationIdentity = SearchFeedbackIdentityStore(
        () async => Directory(destination),
      );
      final carriedIdentity = await destinationIdentity.load();
      if (carriedIdentity?.blocked == true) return 0;
      var keyCarried = carriedIdentity != null;
      var collected = 0;
      for (final name in await source.sealAndList()) {
        if (!await mayCollect()) break;
        final candidate = await source.read(name);
        if (candidate == null || _isLocalOnly(candidate)) continue;
        final claimed = await source.claim(name);
        if (claimed == null) continue;
        final batch = await source.read(claimed);
        if (batch == null) continue;
        if (!keyCarried) {
          await destinationIdentity.save(identity);
          keyCarried = true;
        }
        final lock = await SearchFeedbackQueueLock.acquire('$destination.lock');
        try {
          // נשמר לפני המחיקה במקור, ושם המקטע מאפשר חזרה אחרי קריסה.
          await File(p.join(destination, '.dirty'))
              .writeAsString('', flush: true);
          final target = File(p.join(destination, claimed));
          await writeStringAtomically(
            target.path,
            '${batch.contextJson}\n${batch.eventLines.join('\n')}\n',
          );
        } finally {
          await lock.release();
        }
        await source.remove(claimed);
        collected += batch.eventLines.length;
      }
      return collected;
    } finally {
      await transportLock.release();
    }
  }

  static bool _isLocalOnly(SearchFeedbackStoredBatch batch) =>
      (jsonDecode(batch.contextJson) as Map)['localOnly'] == true;

  void stop() {
    _stopped = true;
    if (!_abort.isCompleted) _abort.complete();
  }

  void close() {
    stop();
    _client.close();
  }

  Future<SearchFeedbackUploadResult> upload() async {
    _stopped = false;
    _abort = Completer<void>();
    var sent = 0, rejected = 0;
    await Directory(directory).create(recursive: true);
    final lock = await SearchFeedbackQueueLock.acquire(
      p.join(directory, 'transport.lock'),
    );
    try {
      final retryFile = File(p.join(directory, 'retry-at.txt'));
      final filteredFile = File(p.join(directory, 'network-block.json'));
      if (await retryFile.exists()) {
        final retryAt = DateTime.tryParse(await retryFile.readAsString());
        if (retryAt != null && retryAt.isAfter(DateTime.now())) {
          return (sent: 0, rejected: 0, remaining: await count());
        }
      }
      Future<void> defer(SearchFeedbackOutcome outcome) async {
        if (_stopped) return;
        _stopped = true;
        _backoffStep++;
        final filtered = outcome.strike == SearchFeedbackStrike.filtered;
        final delay = searchFeedbackRetryDelay(
          strike: outcome.strike,
          retryAfter: outcome.retryAfter,
          backoffStep: _backoffStep,
          previousFilteredSeconds:
              filtered ? await _filteredDelaySeconds(filteredFile) : 0,
        );
        if (filtered) {
          await _replace(
            filteredFile,
            jsonEncode({'delaySeconds': delay.inSeconds}),
          );
        }
        await _replace(
          retryFile,
          DateTime.now().add(delay).toUtc().toIso8601String(),
        );
      }

      await for (final entity in Directory(directory).list()) {
        if (entity is! Directory || _stopped) continue;
        final store = SearchFeedbackIdentityStore(() async => entity);
        final identity = await store.load();
        if (identity == null || identity.blocked) continue;
        final queue = _queue(entity.path);
        final sender = SearchFeedbackSender(
          client: () => _client,
          baseUrl: _baseUrl,
          clock: DateTime.now,
        );
        for (final name in await queue.sealAndList()) {
          if (_stopped) break;
          final claimed = await queue.claim(name);
          if (claimed == null) continue;
          var carried = true;
          var droppedByFallback = 0;
          var batch = await queue.read(claimed,
              notBefore: DateTime.now().subtract(carriedWindow));
          if (batch == null) continue;
          final context = jsonDecode(batch.contextJson) as Map;
          if (batch.eventLines.isEmpty || context['localOnly'] == true) {
            await queue.remove(claimed);
            continue;
          }
          final version = context['appVersion'] as String? ?? '';
          Future<bool> register() async {
            final outcome = await sender.register(
              identity: identity,
              body: searchFeedbackJsonEncode({
                'schema': 1,
                'publicKey': identity.publicKeyBase64,
                'app': 'otzaria',
                'appVersion': truncateForSearchFeedback(version, 64),
                'platform': context['platform'],
                'createdAt': searchFeedbackIsoTime(DateTime.now()),
              }),
              appVersion: version,
              canSend: () => !_stopped,
              abortTrigger: _abort.future,
            );
            if (outcome.kind == SearchFeedbackOutcomeKind.keyBlocked) {
              identity.blocked = true;
              await store.save(identity);
              await queue.purge();
            }
            if (outcome.kind != SearchFeedbackOutcomeKind.accepted ||
                (outcome.keyId != null && outcome.keyId != identity.keyId)) {
              await defer(outcome);
              return false;
            }
            identity.registeredKeyId = identity.keyId;
            await store.save(identity);
            return true;
          }

          if (!identity.isRegistered && !await register()) break;
          Future<SearchFeedbackOutcome> post() {
            final events = batch!;
            return sender.sendEvents(
              identity: identity,
              body: '{"schema":1,"batchId":"${newSearchFeedbackId()}",'
                  '"sentAt":"${searchFeedbackIsoTime(DateTime.now())}",'
                  '${carried ? '"carriedOffline":true,' : ''}'
                  '"context":${events.contextJson},'
                  '"events":[${events.eventLines.join(',')}]}',
              appVersion: version,
              canSend: () => !_stopped,
              abortTrigger: _abort.future,
            );
          }

          var outcome = await post();
          if (outcome.kind == SearchFeedbackOutcomeKind.unknownKey) {
            identity.registeredKeyId = null;
            await store.save(identity);
            if (!await register()) break;
            outcome = await post();
          }
          if (outcome.kind == SearchFeedbackOutcomeKind.drop && !_stopped) {
            carried = false;
            final carriedCount = batch.eventLines.length;
            batch = await queue.read(claimed,
                notBefore: DateTime.now().subtract(plainWindow));
            if (batch == null) continue;
            droppedByFallback = carriedCount - batch.eventLines.length;
            if (batch.eventLines.isEmpty) {
              rejected += droppedByFallback;
              await queue.remove(claimed);
              continue;
            }
            outcome = await post();
          }
          switch (outcome.kind) {
            case SearchFeedbackOutcomeKind.accepted:
              sent += batch.eventLines.length - outcome.rejected;
              rejected += outcome.rejected + droppedByFallback;
              await queue.remove(claimed);
              _backoffStep = 0;
              if (await retryFile.exists()) await retryFile.delete();
              if (await filteredFile.exists()) await filteredFile.delete();
            case SearchFeedbackOutcomeKind.drop:
              rejected += batch.eventLines.length + droppedByFallback;
              await queue.remove(claimed);
            case SearchFeedbackOutcomeKind.tooLarge:
              await queue.split(claimed);
            case SearchFeedbackOutcomeKind.keyBlocked:
              identity.blocked = true;
              await store.save(identity);
              await queue.purge();
              _stopped = true;
            case SearchFeedbackOutcomeKind.unknownKey:
            case SearchFeedbackOutcomeKind.retryLater:
              if (outcome.strike == SearchFeedbackStrike.serverError) {
                final record = await queue.addStrike(
                  claimed,
                  outcome.strike.name,
                  DateTime.now(),
                );
                if (searchFeedbackStrikesExhausted(record, DateTime.now())) {
                  rejected += batch.eventLines.length;
                  await queue.remove(claimed);
                }
              }
              await defer(outcome);
          }
          if (_stopped) break;
        }
        if (!identity.blocked && await pending(entity.path) == 0) {
          await store.delete();
        }
      }
      return (sent: sent, rejected: rejected, remaining: await count());
    } finally {
      await lock.release();
    }
  }

  static Future<int> _filteredDelaySeconds(File file) async {
    try {
      return searchFeedbackFilteredDelaySeconds(await file.readAsString());
    } on FileSystemException {
      return 0;
    }
  }

  static Future<void> _replace(File file, String contents) async {
    await writeStringAtomically(file.path, contents);
  }
}
