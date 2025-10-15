import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/board.dart';
import '../services/log_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'debug_log_page.dart';
import 'board_sharing_page.dart';
import '../version.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  bool _testing = false;
  String? _testMsg;
  bool _testOk = false;
  bool _updatingUrl = false;
  bool _hostValid = true;
  String _stripScheme(String v) {
    var x = v.trim();
    if (x.isEmpty) return x;
    x = x.replaceFirst(RegExp(r'^\s*(https?:\/\/|\/\/)'), '');
    x = x.replaceFirst(RegExp(r'^\/+'), '');
    if (x.endsWith('/')) x = x.substring(0, x.length - 1);
    return x;
  }

  bool _isValidHost(String input) {
    final s = input.trim();
    if (s.isEmpty) return false;
    if (s.contains(' ')) return false;
    // Allow localhost
    if (s.toLowerCase() == 'localhost') return true;
    // Allow host:port
    final hostPort = RegExp(r'^(\[?[A-Za-z0-9\-.:]+\]?):?(\d{1,5})?$');
    if (!hostPort.hasMatch(s)) return false;
    final parts = s.split(':');
    final host = parts.first;
    // IPv4
    final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    final m = ipv4.firstMatch(host);
    if (m != null) {
      for (int i = 1; i <= 4; i++) {
        final v = int.tryParse(m.group(i)!);
        if (v == null || v < 0 || v > 255) return false;
      }
      return true;
    }
    // Hostname labels
    if (host.length > 253) return false;
    final labels = host.split('.');
    if (labels.any((l) => l.isEmpty || l.length > 63)) return false;
    final labelRx = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$');
    if (!labels.every((l) => labelRx.hasMatch(l))) return false;
    // Accept single-label (intranets), but prefer at least one dot; not enforced
    return true;
  }

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final initialUrl = app.baseUrl == null ? '' : _stripScheme(app.baseUrl!);
    _url = TextEditingController(text: initialUrl);
    _hostValid = initialUrl.isEmpty ? true : _isValidHost(initialUrl);
    _user = TextEditingController(text: app.username ?? '');
    _pass = TextEditingController(text: '');
    // live cleanup: strip any entered scheme so the field stays domain-only
    _url.addListener(() {
      if (_updatingUrl) return;
      final t = _url.text;
      final n = _stripScheme(t);
      if (t != n) {
        _updatingUrl = true;
        _url.value = TextEditingValue(text: n, selection: TextSelection.collapsed(offset: n.length));
        _updatingUrl = false;
      }
      final valid = n.isEmpty ? true : _isValidHost(n);
      if (valid != _hostValid) {
        setState(() => _hostValid = valid);
      }
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final app = context.read<AppState>();
    final l10n = L10n.of(context);
    final hostOnly = _stripScheme(_url.text);
    if (!_isValidHost(hostOnly)) {
      setState(() { _testMsg = l10n.invalidServerAddress; });
      return;
    }
    final fullUrl = 'https://$hostOnly';
    app.setCredentials(baseUrl: fullUrl, username: _user.text, password: _pass.text);
    setState(() { _testing = true; _testMsg = null; _testOk = false; });
    try {
      final ok = await app.testLogin();
      if (!ok) {
        setState(() { _testing = false; _testMsg = l10n.errorMsg('Login'); _testOk = false; });
        return;
      }
      // Prüfen, ob Deck aktiviert ist
      final hasDeck = await app.api.hasDeckEnabled(app.baseUrl!, app.username!, _pass.text);
      if (!hasDeck) {
        setState(() { _testing = false; _testMsg = l10n.errorMsg('Deck-App nicht verfügbar'); _testOk = false; });
        return;
      }
      await app.refreshBoards();
      final count = app.boards.length;
      setState(() { _testing = false; _testMsg = count > 0 ? l10n.loginSuccessBoards(count) : l10n.loginOkNoBoards; _testOk = true; });
    } catch (e) {
      setState(() { _testing = false; _testMsg = l10n.errorMsg(e.toString()); _testOk = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isDark = app.isDarkMode;
    final l10n = L10n.of(context);
    return CupertinoPageScaffold(
      backgroundColor: AppTheme.appBackground(app),
      navigationBar: CupertinoNavigationBar(middle: Text(l10n.settingsTitle)) ,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Konto
            const _Divider(),
            const SizedBox(height: 20),
            // Lokaler Modus Hinweis
            if (app.localMode) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemYellow.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CupertinoColors.systemYellow),
                ),
                child: Text(l10n.localModeBanner, style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 16),
            ],
            Text(l10n.localBoardSection, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(l10n.localModeToggleLabel)),
                CupertinoSwitch(
                  value: app.localMode,
                  onChanged: (v) async {
                    if (v) {
                      await showCupertinoDialog(
                        context: context,
                        builder: (ctx) => CupertinoAlertDialog(
                          title: Text(l10n.localModeEnableTitle),
                          content: Text(l10n.localModeEnableContent),
                          actions: [
                            CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
                            CupertinoDialogAction(
                              isDefaultAction: true,
                              onPressed: () async {
                                Navigator.of(ctx).pop();
                                await context.read<AppState>().setLocalMode(true);
                              },
                              child: Text(l10n.enable),
                            ),
                          ],
                        ),
                      );
                    } else {
                      await context.read<AppState>().setLocalMode(false);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            const _Divider(),
            const SizedBox(height: 20),
            // Startup tab selection
            Text(L10n.of(context).startupPage, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Builder(builder: (ctx) {
              final options = <int, Widget>{
                0: Text(L10n.of(ctx).navUpcoming),
                1: Text(L10n.of(ctx).navBoard),
                2: Text(L10n.of(ctx).overview),
              };
              return CupertinoSlidingSegmentedControl<int>(
                groupValue: app.startupTabIndex,
                children: options,
                onValueChanged: (v) {
                  if (v != null) context.read<AppState>().setStartupTabIndex(v);
                },
              );
            }),
            const SizedBox(height: 12),
            const _Divider(),
            const SizedBox(height: 20),
            // Performance
            Text(L10n.of(context).performance, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [ Expanded(child: Text(L10n.of(context).bgPreloadShort)), CupertinoSwitch(value: app.backgroundPreload, onChanged: (v) => app.setBackgroundPreload(v)) ]),
            const SizedBox(height: 6),
            Text(L10n.of(context).bgPreloadHelpShort, style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 12)),
            const SizedBox(height: 8),
            Text(L10n.of(context).upcomingProgressHelp, style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 12)),
            const SizedBox(height: 12),
            Row(children: [ Expanded(child: Text(L10n.of(context).cacheBoardsLocalShort)), CupertinoSwitch(value: app.cacheBoardsLocal, onChanged: (v) => app.setCacheBoardsLocal(v)) ]),
            const SizedBox(height: 6),
            Text(L10n.of(context).cacheBoardsLocalHelpShort, style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 12)),
            const SizedBox(height: 12),
            const _Divider(),
            const SizedBox(height: 20),
            // Language selector
            Text(l10n.language, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    app.localeCode == null
                        ? l10n.systemLanguage
                        : (app.localeCode == 'de' ? l10n.german : app.localeCode == 'es' ? l10n.spanish : l10n.english),
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    await showCupertinoModalPopup(
                      context: context,
                      builder: (ctx) => CupertinoActionSheet(
                        title: Text(l10n.language),
                        actions: [
                          CupertinoActionSheetAction(onPressed: () { Navigator.of(ctx).pop(); app.setLocale(null); }, child: Text(l10n.systemLanguage)),
                          CupertinoActionSheetAction(onPressed: () { Navigator.of(ctx).pop(); app.setLocale('de'); }, child: Text(l10n.german)),
                          CupertinoActionSheetAction(onPressed: () { Navigator.of(ctx).pop(); app.setLocale('en'); }, child: Text(l10n.english)),
                          CupertinoActionSheetAction(onPressed: () { Navigator.of(ctx).pop(); app.setLocale('es'); }, child: Text(l10n.spanish)),
                        ],
                        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.of(ctx).pop(), isDefaultAction: true, child: Text(l10n.cancel)),
                      ),
                    );
                  },
                  child: const Icon(CupertinoIcons.globe),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const _Divider(),
            const SizedBox(height: 20),
            Text(l10n.nextcloudAccess, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _url,
              placeholder: l10n.urlPlaceholder,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              prefix: Padding(
                padding: const EdgeInsets.only(left: 6, right: 4),
                child: Text('https://', style: TextStyle(color: CupertinoColors.secondaryLabel.resolveFrom(context))),
              ),
              suffix: _hostValid ? null : const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(CupertinoIcons.exclamationmark_circle, color: CupertinoColors.systemRed, size: 18),
              ),
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _hostValid ? CupertinoColors.separator.resolveFrom(context) : CupertinoColors.systemRed, width: _hostValid ? 0.5 : 1.0),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.httpsEnforcedInfo,
              style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _user,
              placeholder: l10n.username,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _pass,
              placeholder: l10n.password,
              obscureText: true,
            ),
            const SizedBox(height: 12),
            CupertinoButton.filled(
              onPressed: _testing ? null : _saveAndTest,
              child: _testing ? const CupertinoActivityIndicator() : Text(l10n.loginAndLoadBoards),
            ),
            if (_testMsg != null) ...[
              const SizedBox(height: 8),
              Text(_testMsg!, style: TextStyle(color: _testOk ? CupertinoColors.activeGreen : CupertinoColors.destructiveRed)),
            ],
            const SizedBox(height: 12),
            const _Divider(),
            const SizedBox(height: 20),
            Text(l10n.activeBoardSection, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (app.boards.isEmpty)
              Text(l10n.noBoardsPleaseTest)
            else
              _BoardPicker(
                boards: app.boards.where((b) => !b.archived).toList(),
                selected: app.activeBoard,
                onChanged: (b) => app.setActiveBoard(b),
              ),
            // Board teilen Link entfernt
            const SizedBox(height: 12),
            const _Divider(),
            const SizedBox(height: 20),
            Text(l10n.appearance, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(l10n.darkMode)),
                CupertinoSwitch(value: isDark, onChanged: (v) => app.setDarkMode(v)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(l10n.smartColors)),
                CupertinoSwitch(value: app.smartColors, onChanged: (v) => app.setSmartColors(v)),
              ],
            ),
            const SizedBox(height: 6),
            Text(l10n.smartColorsHelp, style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(l10n.showDescriptionAlways)),
                CupertinoSwitch(value: app.showDescriptionText, onChanged: (v) => app.setShowDescriptionText(v)),
              ],
            ),
            const SizedBox(height: 6),
            Text(l10n.showDescriptionHelp, style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 12)),
            const SizedBox(height: 12),
            const _Divider(),
            const SizedBox(height: 20),
            Text(l10n.developer, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(l10n.enableNetworkLogs)),
                CupertinoSwitch(
                  value: LogService().enabled,
                  onChanged: (v) {
                    LogService().enabled = v;
                    setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            CupertinoButton(
              onPressed: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const DebugLogPage())),
              child: Text(l10n.viewLogs),
            ),
            const SizedBox(height: 20),
            const _Divider(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                () {
                  final idx = kAppVersion.indexOf('+');
                  final pretty = idx > 0 ? '${kAppVersion.substring(0, idx)} (${kAppVersion.substring(idx + 1)})' : kAppVersion;
                  return '${l10n.appVersionLabel}: $pretty';
                }(),
                style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _ThemeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final dots = List.generate(5, (i) => i);
    return Row(
      children: dots
          .map((i) => Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: Container(
                    height: 32,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: i == selected ? CupertinoColors.activeBlue : CupertinoColors.separator),
                      gradient: LinearGradient(colors: [
                        Color(AppTheme.palettesLight[i][0]),
                        Color(AppTheme.palettesLight[i][3]),
                      ]),
                    ),
                    alignment: Alignment.center,
                    child: Text('Theme ${i + 1}', style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _BoardPicker extends StatelessWidget {
  final List<Board> boards;
  final Board? selected;
  final ValueChanged<Board> onChanged;
  const _BoardPicker({required this.boards, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final controller = FixedExtentScrollController(
      initialItem: selected == null ? 0 : boards.indexWhere((b) => b.id == selected!.id).clamp(0, boards.length - 1),
    );
    return SizedBox(
      height: 180,
      child: CupertinoPicker(
        scrollController: controller,
        itemExtent: 36,
        onSelectedItemChanged: (i) => onChanged(boards[i]),
        children: boards.map((b) => Center(child: Text(b.title))).toList(),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: CupertinoColors.separator);
  }
}
