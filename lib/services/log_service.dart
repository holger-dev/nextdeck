import 'package:flutter/foundation.dart';

class LogEntry {
  final DateTime at;
  final String method;
  final String url;
  final int? status;
  final int durationMs;
  final String? requestBody;
  final String? responseSnippet;
  final String? error;

  LogEntry({
    required this.at,
    required this.method,
    required this.url,
    required this.durationMs,
    this.status,
    this.requestBody,
    this.responseSnippet,
    this.error,
  });
}

class LogService extends ChangeNotifier {
  static final LogService _i = LogService._();
  LogService._();
  factory LogService() => _i;

  bool enabled = true; // default on for development
  final List<LogEntry> _entries = [];
  List<LogEntry> get entries => List.unmodifiable(_entries.reversed);

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void add(LogEntry e) {
    // Always print to console for dev visibility
    debugPrint('[NET] ${e.method} ${e.url} -> ${e.status ?? '-'} in ${e.durationMs}ms');
    if (e.error != null) {
      debugPrint('[NET][ERR] ${e.error}');
    } else if (e.responseSnippet != null && e.responseSnippet!.isNotEmpty) {
      debugPrint('[NET][RES] ${e.responseSnippet}');
    }
    if (enabled) {
      _entries.add(e);
      if (_entries.length > 200) {
        _entries.removeRange(0, _entries.length - 200);
      }
      notifyListeners();
    }
  }
}
