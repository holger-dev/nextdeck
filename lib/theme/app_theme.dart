import 'package:flutter/cupertino.dart';
import 'dart:math' as math;

import '../state/app_state.dart';
import '../models/label.dart';

class AppTheme {
  static const palettesLight = [
    // Frisch
    [0xFFE3F2FD, 0xFFE8F5E9, 0xFFFFF3E0, 0xFFF3E5F5, 0xFFE1F5FE, 0xFFFFEBEE],
    // Ozean
    [0xFFE0F7FA, 0xFFE1F5FE, 0xFFE3F2FD, 0xFFF1F8E9, 0xFFFFFDE7, 0xFFF3E5F5],
    // Sonne
    [0xFFFFF8E1, 0xFFFFF3E0, 0xFFFFEBEE, 0xFFE8F5E9, 0xFFE0F2F1, 0xFFEDE7F6],
    // Beeren
    [0xFFFCE4EC, 0xFFF3E5F5, 0xFFEDE7F6, 0xFFE1F5FE, 0xFFE8F5E9, 0xFFFFF3E0],
    // Wald
    [0xFFE8F5E9, 0xFFE0F2F1, 0xFFE3F2FD, 0xFFEDE7F6, 0xFFFFF8E1, 0xFFFFEBEE],
  ];

  static const palettesDark = [
    [0xFF1E2933, 0xFF1E2E24, 0xFF2E2920, 0xFF2B2331, 0xFF1F2830, 0xFF2E2324],
    [0xFF142A2E, 0xFF132430, 0xFF111E29, 0xFF1B2A18, 0xFF2B2A12, 0xFF221C2A],
    [0xFF2A2616, 0xFF2A2318, 0xFF291A1C, 0xFF1F291D, 0xFF1B2826, 0xFF241F2E],
    [0xFF2B1E25, 0xFF241E2B, 0xFF1F1E2B, 0xFF18232B, 0xFF1B2A18, 0xFF291E1F],
    [0xFF1E2B21, 0xFF1C2827, 0xFF1C262E, 0xFF231E2B, 0xFF2B2618, 0xFF2A1E1F],
  ];

  static Color columnColor(AppState app, int columnIndex) {
    final idx = app.themeIndex % palettesLight.length;
    final list = app.isDarkMode ? palettesDark[idx] : palettesLight[idx];
    final c = list[columnIndex % list.length];
    return Color(c);
  }

  // Column color based on common status keywords; falls back to themed palette
  static Color preferredColumnColor(AppState app, String title, int columnIndex) {
    final m = _matchColumnColor(title);
    if (m != null) return m;
    return columnColor(app, columnIndex);
  }

  static Color? _matchColumnColor(String title) {
    final t = title.toLowerCase().trim();
    Color hex(int v) => Color(v);
    // Greens for done
    const green = 0xFF2ECC71; // emerald
    const orange = 0xFFF39C12; // orange
    const grey = 0xFF95A5A6; // concrete
    const purple = 0xFF9B59B6; // amethyst
    const red = 0xFFE74C3C; // alizarin
    const blue = 0xFF3498DB; // peter river
    const blueAlt = 0xFF2980B9; // belize hole (for ToDo)
    const teal = 0xFF1ABC9C; // turquoise

    bool any(Iterable<String> keys) => keys.any((k) => t.contains(k));
    if (any(['done', 'erledigt', 'fertig', 'complete', 'abgeschlossen', 'done ✅'])) return hex(green);
    if (any(['in progress', 'in arbeit', 'doing', 'progress', 'wip'])) return hex(orange);
    if (any(['blocked', 'blockiert', 'waiting', 'warten', 'on hold', 'bug', 'fehler', 'issue', 'defect'])) return hex(red);
    if (any(['review', 'prüfen', 'qa', 'test', 'feature', 'features', 'feat'])) return hex(purple);
    if (any(['ready', 'bereit'])) return hex(teal);
    if (any(['planned', 'planung', 'upcoming'])) return hex(blue);
    if (any(['todo', 'to do'])) return hex(blueAlt);
    if (any(['backlog', 'speicher', 'offen', 'ideas', 'ideen'])) return hex(grey);
    return null;
  }

  static Color neutralCardBase(AppState app) {
    return app.isDarkMode ? const Color(0xFF1F1F1F) : const Color(0xFFF5F5F5);
  }

  static Color cardBgFromBase(AppState app, List<Label> labels, Color base, int cardIndex) {
    if (labels.isNotEmpty && app.cardColorsFromLabels) {
      final labelBase = _parseDeckColor(labels.first.color) ?? base;
      return app.isDarkMode ? _blend(labelBase, const Color(0xFF101010), 0.6) : _blend(labelBase, const Color(0xFFFFFFFF), 0.8);
    }
    final tweak = (cardIndex % 2 == 0) ? 0.1 : -0.05;
    return _tint(base, app.isDarkMode ? -0.05 + tweak : 0.3 + tweak);
  }

  static Color cardBg(AppState app, List<Label> labels, int columnIndex, int cardIndex) {
    if (labels.isNotEmpty && app.cardColorsFromLabels) {
      final base = _parseDeckColor(labels.first.color) ?? neutralCardBase(app);
      return app.isDarkMode ? _blend(base, const Color(0xFF101010), 0.55) : _blend(base, const Color(0xFFFFFFFF), 0.7);
    }
    if (!app.cardColorsFromLabels) {
      final base = neutralCardBase(app);
      final tweak = (cardIndex % 2 == 0) ? 0.15 : -0.05;
      return _tint(base, app.isDarkMode ? -0.1 + tweak : 0.25 + tweak);
    }
    final col = columnColor(app, columnIndex);
    final tweak = (cardIndex % 2 == 0) ? 0.15 : -0.05;
    return _tint(col, app.isDarkMode ? -0.1 + tweak : 0.25 + tweak);
  }

  static Color textOn(Color bg) {
    final r = bg.red / 255.0, g = bg.green / 255.0, b = bg.blue / 255.0;
    double lum(double c) => c <= 0.03928 ? c / 12.92 : math.pow(((c + 0.055) / 1.055), 2.4).toDouble();
    final L = 0.2126 * lum(r) + 0.7152 * lum(g) + 0.0722 * lum(b);
    return L > 0.55 ? CupertinoColors.black : CupertinoColors.white;
  }

  static Color appBackground(AppState app) {
    final idx = app.themeIndex % palettesLight.length;
    final base = app.isDarkMode ? Color(palettesDark[idx][0]) : Color(palettesLight[idx][0]);
    // Subtle blend towards neutral to avoid overwhelming
    return app.isDarkMode ? blend(base, const Color(0xFF000000), 0.7) : blend(base, const Color(0xFFFFFFFF), 0.8);
  }

  static Color boardBandBackground(AppState app, Color base) {
    return app.isDarkMode
        ? blend(base, const Color(0xFF000000), 0.75)
        : blend(base, const Color(0xFFFFFFFF), 0.85);
  }

  static Color boardColor(AppState app, int boardIndex) {
    final idx = app.themeIndex % palettesLight.length;
    final list = app.isDarkMode ? palettesDark[idx] : palettesLight[idx];
    // Pick a stable color from palette by board index
    final c = list[boardIndex % list.length];
    return Color(c);
  }

  // Strong, saturated colors for Overview boards
  static const _strongBoardColors = <int>[
    0xFFEF6C00, // deep orange 800
    0xFF8E24AA, // purple 600
    0xFF1E88E5, // blue 600
    0xFF43A047, // green 600
    0xFFD81B60, // pink 600
    0xFFF4511E, // orange 600
    0xFF3949AB, // indigo 600
    0xFF00ACC1, // cyan 600
    0xFF5E35B1, // deep purple 600
    0xFF00897B, // teal 600
  ];

  static Color boardStrongColor(int index) {
    return Color(_strongBoardColors[index % _strongBoardColors.length]);
  }

  // Parse Nextcloud-style hex color (with/without '#')
  static Color? boardColorFrom(String? raw) => _parseDeckColor(raw ?? '');

  static Color? _parseDeckColor(String raw) {
    if (raw.isEmpty) return null;
    var s = raw.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    final val = int.tryParse(s, radix: 16);
    if (val == null) return null;
    return Color(val);
  }

  static Color _tint(Color c, double amount) {
    // amount: -1.0 (darken) .. +1.0 (lighten)
    return amount >= 0 ? _blend(c, const Color(0xFFFFFFFF), amount) : _blend(c, const Color(0xFF000000), -amount);
  }

  static Color _blend(Color a, Color b, double t) {
    return Color.fromARGB(
      (a.alpha + (b.alpha - a.alpha) * t).round(),
      (a.red + (b.red - a.red) * t).round(),
      (a.green + (b.green - a.green) * t).round(),
      (a.blue + (b.blue - a.blue) * t).round(),
    );
  }

  // Public blend for external usage
  static Color blend(Color a, Color b, double t) => _blend(a, b, t);
}
