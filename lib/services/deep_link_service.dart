import 'dart:async';

import 'package:flutter/services.dart';

class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();
  static const MethodChannel _channel = MethodChannel('nextdeck/deeplink');

  final StreamController<Uri> _links = StreamController<Uri>.broadcast();
  bool _initialized = false;

  Stream<Uri> get links => _links.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final raw = call.arguments as String?;
        if (raw != null && raw.isNotEmpty) {
          _links.add(Uri.parse(raw));
        }
      }
    });
    final initial = await _channel.invokeMethod<String>('getInitialLink');
    if (initial != null && initial.isNotEmpty) {
      _links.add(Uri.parse(initial));
    }
  }
}
