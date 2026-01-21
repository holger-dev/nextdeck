import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class WidgetService {
  static const MethodChannel _channel = MethodChannel('nextdeck/widget');

  Future<void> updateWidgetData(Map<String, dynamic> payload) async {
    if (!Platform.isIOS) return;
    final json = jsonEncode(payload);
    await _channel.invokeMethod('updateWidgetData', {'payload': json});
  }
}
