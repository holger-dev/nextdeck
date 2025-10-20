import 'dart:async';
import 'dart:collection';
import '../config/sync_config.dart';

class SyncQueue {
  static final Queue<Future<void> Function()> _q = Queue();
  static int _inFlight = 0;

  static Future<void> run(Future<void> Function() task) {
    final c = Completer<void>();
    _q.add(() async { await task(); c.complete(); });
    _drain();
    return c.future;
  }

  static void enqueue(Future<void> Function() task) {
    _q.add(task);
    _drain();
  }

  static void _drain() {
    while (_inFlight < kSyncMaxConcurrency && _q.isNotEmpty) {
      final t = _q.removeFirst();
      _inFlight++;
      t().whenComplete(() { _inFlight--; _drain(); });
    }
  }
}

