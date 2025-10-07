import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../services/log_service.dart';
import '../l10n/app_localizations.dart';

class DebugLogPage extends StatelessWidget {
  const DebugLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: LogService(),
      child: Builder(
        builder: (context) {
          final log = context.watch<LogService>();
          final items = log.entries;
          return CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(
              middle: Text(L10n.of(context).networkLogs),
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => LogService().clear(),
                child: const Icon(CupertinoIcons.trash),
              ),
            ),
            child: SafeArea(
              child: items.isEmpty
                  ? Center(child: Text(L10n.of(context).noEntries))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final e = items[index];
                        final status = e.status?.toString() ?? '-';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: CupertinoColors.separator)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _statusColor(e.status),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${e.method} $status ${e.durationMs}ms',
                                      style: const TextStyle(color: CupertinoColors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      e.url,
                                      style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (e.requestBody != null && e.requestBody!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('Req: ${e.requestBody}', style: const TextStyle(fontSize: 12)),
                              ],
                              if (e.error != null) ...[
                                const SizedBox(height: 6),
                                Text('Error: ${e.error}', style: const TextStyle(fontSize: 12, color: CupertinoColors.destructiveRed)),
                              ] else if (e.responseSnippet != null && e.responseSnippet!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('Res: ${e.responseSnippet}', style: const TextStyle(fontSize: 12)),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(int? code) {
    if (code == null) return CupertinoColors.systemGrey;
    if (code >= 200 && code < 300) return CupertinoColors.activeGreen;
    if (code >= 400 && code < 500) return CupertinoColors.activeOrange;
    return CupertinoColors.destructiveRed;
  }
}
