import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../theme/design_tokens.dart';

/// Beschreibt einen einzelnen Tab in der [GlassTabBar].
class GlassTabBarItem {
  final IconData icon;
  final String label;
  const GlassTabBarItem({required this.icon, required this.label});
}

/// Modernes "Floating-Glass"-Tab-Bar im iOS-17/18-Look.
///
/// Optisch:
/// - schwebt mit Margin links/rechts/unten
/// - rounded corners (Pill-Shape)
/// - Translucent + BackdropFilter-Blur
/// - dezenter Soft-Shadow für Tiefenwirkung
/// - Selected-Item bekommt einen runden Akzent-Hintergrund (iOS-typisch)
///
/// Funktional:
/// - identisches Verhalten wie eine `CupertinoTabBar` (re-tap auf aktiven Tab,
///   einzelne Items, Index-Callback). Wir geben das Re-Tap-Verhalten an den
///   Caller zurück, weil das pop-to-root-Verhalten dort sitzt.
class GlassTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassTabBarItem> items;

  const GlassTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final theme = CupertinoTheme.of(context);
    final activeColor = theme.primaryColor;
    final inactiveColor = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF6E6E73);

    final radius = BorderRadius.circular(DT.radiusXl);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: DT.glassBlur,
          sigmaY: DT.glassBlur,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: DT.glassBackground(context),
            borderRadius: radius,
            boxShadow: DT.shadowM(isDark),
            border: Border.all(
              color: DT.separatorColor(context),
              width: DT.dividerThin,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DT.spaceXs,
            vertical: DT.spaceXs,
          ),
          // Keine zusätzliche SafeArea hier — den Bottom-Inset setzt der
          // Aufrufer (main.dart) bereits über `Positioned(bottom: …)`.
          // Sonst hätten wir doppelten Inset und unter den Icons sehr viel
          // toten Platz.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final isActive = i == currentIndex;
              return Expanded(
                child: _GlassTabItem(
                  item: items[i],
                  isActive: isActive,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                  onTap: () {
                    if (!isActive) HapticFeedback.selectionClick();
                    onTap(i);
                  },
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _GlassTabItem extends StatelessWidget {
  final GlassTabBarItem item;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _GlassTabItem({
    required this.item,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? activeColor : inactiveColor;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: DT.durationFast,
        curve: DT.curveStandard,
        margin: const EdgeInsets.symmetric(
          horizontal: 2,
          vertical: 2,
        ),
        padding: const EdgeInsets.symmetric(
          vertical: DT.spaceS,
          horizontal: DT.spaceXs,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withOpacity(0.12)
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(DT.radiusM),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
