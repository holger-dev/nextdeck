import 'package:flutter/cupertino.dart';

import '../theme/design_tokens.dart';

/// Generisches Skeleton-Loading-Element mit dezentem Shimmer-Effekt.
///
/// Wird als Platzhalter angezeigt, während echter Content lädt — wirkt
/// moderner als ein CupertinoActivityIndicator und lässt den Nutzer
/// vorab sehen, wo gleich Content erscheint.
///
/// Nutzung:
/// ```dart
/// const Skeleton(height: 14, width: 120);
/// const Skeleton.line();        // 14px hohe Standard-Zeile
/// const Skeleton.card();        // ganze Karten-Platzhalter
/// ```
class Skeleton extends StatefulWidget {
  final double width;
  final double? height;
  final double radius;

  const Skeleton({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = 6,
  });

  /// 14 px hohe Text-Zeile.
  const Skeleton.line({super.key, this.width = double.infinity})
      : height = 14,
        radius = 6;

  /// Block-Platzhalter (z. B. für eine ganze Card).
  const Skeleton.block({
    super.key,
    this.width = double.infinity,
    this.height = 80,
  }) : radius = DT.radiusL;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final base = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    final highlight =
        isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            // Bewegter Gradient-Akzent von links nach rechts.
            final t = _ctrl.value;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1 + 2 * t - 0.5, 0),
                  end: Alignment(-1 + 2 * t + 0.5, 0),
                  colors: [base, highlight, base],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Vorgefertigter Card-Skeleton im Stil der echten Stack-Karten.
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final base = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: DT.spaceL, vertical: DT.spaceXs),
      child: Container(
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(DT.radiusL),
          boxShadow: DT.shadowS(isDark),
        ),
        padding: const EdgeInsets.all(DT.spaceM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Skeleton.line(width: 180),
            SizedBox(height: 8),
            Skeleton.line(width: double.infinity),
            SizedBox(height: 6),
            Skeleton(width: 100, height: 18, radius: 9),
          ],
        ),
      ),
    );
  }
}

/// Liste mehrerer CardSkeletons für ein "Loading-Stack"-Look.
class CardListSkeleton extends StatelessWidget {
  final int count;
  const CardListSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (_) => const CardSkeleton()),
    );
  }
}
