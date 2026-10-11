import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/serial_queue.dart';

void main() {
  test('the first action starts synchronously', () {
    final queue = SerialQueue();
    var started = false;

    queue.run(() async => started = true);

    expect(started, isTrue);
  });

  test('actions run one at a time, in the order they were queued', () async {
    final queue = SerialQueue();
    final events = <String>[];
    final gate = Completer<void>();

    final first = queue.run(() async {
      events.add('first start');
      await gate.future;
      events.add('first end');
    });
    final second = queue.run(() async {
      events.add('second start');
    });
    final third = queue.run(() async {
      events.add('third start');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['first start']);

    gate.complete();
    await Future.wait([first, second, third]);

    expect(events, [
      'first start',
      'first end',
      'second start',
      'third start',
    ]);
  });

  test('results are returned to each caller', () async {
    final queue = SerialQueue();

    final results = await Future.wait([
      queue.run(() async => 1),
      queue.run(() async => 'two'),
    ]);

    expect(results, [1, 'two']);
  });

  test('a failing action reaches its caller and does not block the next',
      () async {
    final queue = SerialQueue();
    final failing = queue.run<void>(() async => throw StateError('boom'));
    final next = queue.run(() async => 'ran');

    await expectLater(failing, throwsStateError);
    expect(await next, 'ran');
    expect(await queue.run(() async => 'later'), 'later');
  });

  test('forKey shares one queue per key and separates different keys',
      () async {
    final a1 = SerialQueue.forKey('serial-queue-test-a');
    final a2 = SerialQueue.forKey('serial-queue-test-a');
    final b = SerialQueue.forKey('serial-queue-test-b');
    expect(identical(a1, a2), isTrue);
    expect(identical(a1, b), isFalse);

    final events = <String>[];
    final gate = Completer<void>();
    final slow = a1.run(() async {
      await gate.future;
      events.add('a1');
    });
    final queuedBehind = a2.run(() async => events.add('a2'));
    await b.run(() async => events.add('b'));

    expect(events, ['b']);
    gate.complete();
    await Future.wait([slow, queuedBehind]);
    expect(events, ['b', 'a1', 'a2']);
  });
}
