import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final msg = app.bootMessage ?? 'Lade…';
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(radius: 16),
            const SizedBox(height: 12),
            Text(msg, style: const TextStyle(color: CupertinoColors.inactiveGray)),
          ],
        ),
      ),
    );
  }
}
