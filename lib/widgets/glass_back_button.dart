import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// NC 2.0: Zurück-Button im Glass-Look für gepushte Seiten — ersetzt den
/// iOS-Standard-Back (blaues Chevron + „Zurück"-Text), damit die Navigation
/// überall den 38-px-GlassIconButton-Stil der App nutzt. Die Edge-Swipe-
/// Geste zum Zurückgehen bleibt davon unberührt.
class GlassBackButton extends StatelessWidget {
  final Color? color;
  const GlassBackButton({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      size: 38,
      icon: Icon(CupertinoIcons.chevron_left,
          size: 19, color: color ?? CupertinoColors.label.resolveFrom(context)),
      onPressed: () => Navigator.of(context).maybePop(),
    );
  }
}
