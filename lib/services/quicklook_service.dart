import 'dart:io';

import 'package:flutter/services.dart';

/// Issue #86.3: nativer QuickLook-Markup-Editor (iOS).
///
/// Öffnet eine lokale Datei im systemeigenen QuickLook-Viewer mit
/// aktiviertem Bearbeiten-Modus (Markup: Zeichnen, Text, Signatur —
/// bei PDFs auch Seiten). Änderungen schreibt iOS direkt in die Datei.
///
/// Returnt:
/// * `true`  → Datei wurde bearbeitet (Inhalt hat sich geändert)
/// * `false` → nur angesehen, keine Änderung
/// * `null`  → Editor nicht verfügbar / Fehler (Caller sollte auf den
///             bisherigen Share-Sheet-Flow zurückfallen)
class QuickLookService {
  static const MethodChannel _channel = MethodChannel('nextdeck/quicklook');

  static Future<bool?> editFile(String path) async {
    if (!Platform.isIOS) return null;
    try {
      final res = await _channel.invokeMethod<bool>('editFile', {
        'path': path,
      });
      return res;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
