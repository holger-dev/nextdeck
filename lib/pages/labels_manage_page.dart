import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/label.dart';
import '../l10n/app_localizations.dart';

class LabelsManagePage extends StatefulWidget {
  const LabelsManagePage({super.key});

  @override
  State<LabelsManagePage> createState() => _LabelsManagePageState();
}

class _LabelsManagePageState extends State<LabelsManagePage> {
  bool _loading = true;
  List<Label> _labels = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final baseUrl = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    final board = app.activeBoard;
    if (baseUrl == null || user == null || pass == null || board == null) {
      setState(() { _loading = false; });
      return;
    }
    try {
      final raw = await app.api.fetchBoardLabels(baseUrl, user, pass, board.id);
      setState(() {
        _labels = raw.map((e) => Label.fromJson(e)).toList();
      });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(l10n.manageLabels)),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: _labels.length,
                      separatorBuilder: (_, __) => Container(height: 1, color: CupertinoColors.separator),
                      itemBuilder: (context, i) {
                        final l = _labels[i];
                        return Dismissible(
                          key: ValueKey('label_${l.id}'),
                          direction: DismissDirection.endToStart,
                          background: Container(color: CupertinoColors.destructiveRed),
                          confirmDismiss: (_) async {
                            return await _confirmDelete(context, l);
                          },
                          onDismissed: (_) => _delete(l),
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            onPressed: () => _edit(l),
                            child: Row(
                              children: [
                                _ColorDot(color: _parseColor(l.color)),
                                const SizedBox(width: 10),
                                Expanded(child: Text(l.title.isEmpty ? 'Label ${l.id}' : l.title)),
                                const Icon(CupertinoIcons.forward)
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Container(height: 1, color: CupertinoColors.separator),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: CupertinoButton.filled(
                      onPressed: _create,
                      child: Text(l10n.addEllipsis),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, Label l) async {
    bool? ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.deleteLabelQuestion),
        content: Text('"${l.title.isEmpty ? l10n.wordLabel : l.title}" wirklich löschen?'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.delete)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _create() async {
    await _showEditSheet();
  }

  Future<void> _edit(Label l) async {
    await _showEditSheet(existing: l);
  }

  Future<void> _delete(Label l) async {
    final app = context.read<AppState>();
    final baseUrl = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    final board = app.activeBoard;
    if (baseUrl == null || user == null || pass == null || board == null) return;
    await app.api.deleteBoardLabel(baseUrl, user, pass, board.id, l.id);
    await _load();
  }

  Future<void> _showEditSheet({Label? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final colorCtrl = TextEditingController(text: _normColor(existing?.color ?? '3794ac'));
    Color preview = _parseColor(colorCtrl.text);
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        void updatePreview(String v) { setS(() { preview = _parseColor(v); }); }
        return CupertinoActionSheet(
          title: Text(existing == null ? l10n.newLabel : l10n.editLabel),
          message: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.title),
              const SizedBox(height: 4),
              CupertinoTextField(controller: titleCtrl, placeholder: l10n.title),
              const SizedBox(height: 8),
              Text(l10n.colorHexNoHash),
              const SizedBox(height: 4),
              Row(children: [
                _ColorDot(color: preview),
                const SizedBox(width: 8),
                Expanded(child: CupertinoTextField(controller: colorCtrl, onChanged: updatePreview, placeholder: l10n.exampleHex)),
              ]),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _presetColors.map((c) => GestureDetector(
                  onTap: () { colorCtrl.text = c; updatePreview(c); },
                  child: _ColorDot(color: _parseColor(c), size: 22),
                )).toList(),
              ),
            ],
          ),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _saveLabel(titleCtrl.text.trim(), colorCtrl.text.trim(), existing: existing);
              },
              child: Text(existing == null ? l10n.create : l10n.save),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.of(ctx).pop(), isDefaultAction: true, child: Text(l10n.cancel)),
        );
      }),
    );
  }

  Future<void> _saveLabel(String title, String color, {Label? existing}) async {
    if (title.isEmpty) return;
    final app = context.read<AppState>();
    final baseUrl = app.baseUrl; final user = app.username; final pass = await app.storage.read(key: 'password');
    final board = app.activeBoard;
    if (baseUrl == null || user == null || pass == null || board == null) return;
    if (existing == null) {
      await app.api.createBoardLabel(baseUrl, user, pass, board.id, title: title, color: color);
    } else {
      await app.api.updateBoardLabel(baseUrl, user, pass, board.id, existing.id, title: title, color: color);
    }
    await _load();
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final double size;
  const _ColorDot({required this.color, this.size = 18});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: CupertinoColors.separator)),
    );
  }
}

final _presetColors = <String>[
  '3794ac','a6d5a2','f4c430','f28b82','8ab4f8','a285d2','fbbc04','34a853','ea4335','4285f4','bdbdbd','80868b'
];

String _normColor(String c) {
  var s = c.trim();
  if (s.startsWith('#')) s = s.substring(1);
  return s;
}

Color _parseColor(String c) {
  var s = _normColor(c);
  if (s.length == 3) s = s.split('').map((ch) => '$ch$ch').join();
  if (s.length == 6) s = 'FF$s';
  final v = int.tryParse(s, radix: 16);
  return v == null ? CupertinoColors.systemGrey4 : Color(v);
}
