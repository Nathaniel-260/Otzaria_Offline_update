import 'dart:async';

class SerialQueue {
  SerialQueue();

  static final Map<String, SerialQueue> _byKey = {};

  factory SerialQueue.forKey(String key) =>
      _byKey.putIfAbsent(key, SerialQueue.new);

  Future<void>? _tail;

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final result = previous == null ? action() : previous.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}
