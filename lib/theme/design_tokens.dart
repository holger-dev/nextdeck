import 'package:flutter/cupertino.dart';

/// Zentrale Design-Tokens für die App.
///
/// Diese Konstanten ersetzen verstreute Magic Numbers (Radien, Abstände,
/// Schatten, Animations-Dauern) und sorgen für ein konsistentes, modernes
/// Look-and-Feel im Cupertino-Stil (iOS 17+).
///
/// Verwendung statt:
///   `BorderRadius.circular(7)`              -> `BorderRadius.circular(DT.radiusM)`
///   `EdgeInsets.symmetric(horizontal: 12)`  -> `EdgeInsets.symmetric(horizontal: DT.spaceM)`
///   `[BoxShadow(blurRadius: 4, ...)]`       -> `DT.shadowS(isDark)`
class DT {
  DT._();

  // ---- Spacing ----
  /// 4 px – Mikro-Abstand (Icon-Text)
  static const double spaceXs = 4;
  /// 8 px – Eng (zwischen Chip-Items)
  static const double spaceS = 8;
  /// 12 px – Standard-Innenabstand für Cards
  static const double spaceM = 12;
  /// 16 px – Standard-Außenabstand
  static const double spaceL = 16;
  /// 24 px – Sektion-Trenner
  static const double spaceXl = 24;
  /// 32 px – Großer Abstand zwischen Block-Sektionen
  static const double spaceXxl = 32;

  // ---- Border Radius ----
  /// 6 px – Kleine Pills (Tags)
  static const double radiusS = 6;
  /// 10 px – Standard-Cards
  static const double radiusM = 10;
  /// 14 px – Hervorgehobene Cards (Board-Summary)
  static const double radiusL = 14;
  /// 20 px – Sheet-Top-Corners
  static const double radiusXl = 20;
  /// Voll abgerundet (Buttons, kompakte Pills)
  static const double radiusFull = 999;

  // ---- Shadows ----
  /// Sehr subtile Elevation – Card-Liste, Stack-Items
  static List<BoxShadow> shadowS(bool isDark) {
    if (isDark) {
      return const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 6,
          offset: Offset(0, 1),
        ),
      ];
    }
    return const [
      BoxShadow(
        color: Color(0x14000000),
        blurRadius: 6,
        offset: Offset(0, 1),
      ),
    ];
  }

  /// Mittel – Hervorgehobene Cards (Board-Summary, Stack-Header)
  static List<BoxShadow> shadowM(bool isDark) {
    if (isDark) {
      return const [
        BoxShadow(
          color: Color(0x80000000),
          blurRadius: 12,
          offset: Offset(0, 3),
        ),
      ];
    }
    return const [
      BoxShadow(
        color: Color(0x1F000000),
        blurRadius: 12,
        offset: Offset(0, 3),
      ),
    ];
  }

  /// Stärker – Schwebende Modals, Floating Action Areas
  static List<BoxShadow> shadowL(bool isDark) {
    if (isDark) {
      return const [
        BoxShadow(
          color: Color(0x99000000),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ];
    }
    return const [
      BoxShadow(
        color: Color(0x29000000),
        blurRadius: 24,
        offset: Offset(0, 8),
      ),
    ];
  }

  // ---- Animation ----
  /// Sehr kurze Reaktionen (Button-Tap, Highlight)
  static const Duration durationFast = Duration(milliseconds: 150);
  /// Standard – Page-Transitions, Sheet-Movement
  static const Duration durationMedium = Duration(milliseconds: 260);
  /// Lange Transitions – Stack-Wechsel, Hero-Animation
  static const Duration durationSlow = Duration(milliseconds: 480);

  /// Standard-Curve für Page-Wechsel und sanfte Interaktionen.
  static const Curve curveStandard = Curves.easeInOutCubic;
  /// Curve für Schließen/Auf-Wegbewegungen.
  static const Curve curveExit = Curves.easeOutCubic;
  /// Curve für Eintreten/Erscheinen.
  static const Curve curveEnter = Curves.easeOutQuart;

  // ---- Divider / Border ----
  /// Sehr feine Trennlinie statt der harten 1-px-Separator
  static const double dividerThin = 0.5;
  /// Standard-Border-Stärke
  static const double borderThin = 0.8;

  /// Subtle separator-color für ein leiseres Liniengefühl
  /// (transparenter als CupertinoColors.separator).
  static Color separatorColor(BuildContext context) {
    final brightness = CupertinoTheme.brightnessOf(context);
    return brightness == Brightness.dark
        ? const Color(0x33FFFFFF)
        : const Color(0x14000000);
  }

  // ---- Tab-Bar / Glass ----
  /// Hintergrund für Glass-/Translucent-Effekte (iOS 17+ Look).
  ///
  /// Wir verwenden bewusst NICHT reines Weiß (0xFFFFFF), weil das auf weißem
  /// Page-Hintergrund optisch identisch zu einer opaken Tab-Bar wäre. Mit
  /// dem leichten iOS-System-Grau-Tint wird die Tab-Bar als eigenständige
  /// Schicht erkennbar, und CupertinoTabBar aktiviert intern automatisch
  /// den BackdropFilter, weil die Farbe einen Alpha-Anteil hat.
  static Color glassBackground(BuildContext context) {
    final brightness = CupertinoTheme.brightnessOf(context);
    return brightness == Brightness.dark
        // iOS Dark, ~50 % Deckung — Content scheint deutlich durch
        ? const Color(0x801C1C1E)
        // iOS Light, ~50 % Deckung auf systemGray5 — heller Glas-Effekt
        : const Color(0x80E5E5EA);
  }

  /// Blur-Stärke für `BackdropFilter` bei Glass-Effekten.
  static const double glassBlur = 18;
}
