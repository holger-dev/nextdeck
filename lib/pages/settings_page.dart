import 'package:flutter/cupertino.dart';
import 'dart:io';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/board.dart';
import '../services/log_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import 'debug_log_page.dart';
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
  bool _slashMode = false;
  bool _sectionAccountOpen = true;
  bool _sectionHelpOpen = false;
  bool _sectionStartupOpen = false;
  bool _sectionNotificationsOpen = false;
  bool _sectionAppearanceOpen = false;
  bool _sectionLanguageOpen = false;
  bool _sectionPerformanceOpen = false;
  bool _sectionSyncOpen = false;
  bool _sectionSyncOtherBoardsOpen = false;
  bool _sectionLocalOpen = false;
  bool _sectionDeveloperOpen = false;
  bool _sectionSupportOpen = false;
  String _stripScheme(String v) {
    var x = v.trim();
    if (x.isEmpty) return x;
    // Preserve server-relative input exactly as typed
    if (x.startsWith('/')) {
      return x;
    }
    // Remove explicit scheme or protocol-relative
    x = x.replaceFirst(RegExp(r'^\s*(https?:\/\/|\/\/)'), '');
    // Remove accidental leading slashes (host should be domain[:port][path])
    x = x.replaceFirst(RegExp(r'^\/+'), '');
    // Do not strip trailing slash here; keep user input visible
    return x;
  }

  bool _isValidHost(String input) {
    final s = input.trim();
    if (s.isEmpty) return false;
    if (s == '/') return true; // allow server-relative root
    if (s.contains(' ')) return false;
    // Split optional path after host[:port]
    final firstSlash = s.indexOf('/');
    final hostPortPart = firstSlash >= 0 ? s.substring(0, firstSlash) : s;
    final pathPart = firstSlash >= 0 ? s.substring(firstSlash) : '';
    // Allow localhost
    if (hostPortPart.toLowerCase() == 'localhost') return true;
    // Allow host:port
    final hostPort = RegExp(r'^(\[?[A-Za-z0-9\-.:]+\]?):?(\d{1,5})?$');
    if (!hostPort.hasMatch(hostPortPart)) return false;
    final parts = hostPortPart.split(':');
    final host = parts.first;
    // IPv4
    final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    final m = ipv4.firstMatch(host);
    if (m != null) {
      for (int i = 1; i <= 4; i++) {
        final v = int.tryParse(m.group(i)!);
        if (v == null || v < 0 || v > 255) return false;
      }
      // For an IPv4 host, accept optional path
      if (pathPart.isEmpty) return true;
      if (!pathPart.startsWith('/')) return false;
      if (pathPart.contains(' ')) return false;
      return true;
    }
    // Hostname labels (non-IP)
    if (host.length > 253) return false;
    final labels = host.split('.');
    if (labels.any((l) => l.isEmpty || l.length > 63)) return false;
    final labelRx = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$');
    if (!labels.every((l) => labelRx.hasMatch(l))) return false;
    // Optional base path allowed; must start with '/' and contain no spaces
    if (pathPart.isEmpty) return true;
    if (!pathPart.startsWith('/')) return false;
    if (pathPart.contains(' ')) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final initialUrl = app.baseUrl == null ? '' : _stripScheme(app.baseUrl!);
    _url = TextEditingController(text: initialUrl);
    _hostValid = initialUrl.isEmpty ? true : _isValidHost(initialUrl);
    _slashMode = initialUrl.trim().startsWith('/');
    _user = TextEditingController(text: app.username ?? '');
    _pass = TextEditingController(text: '');
    // live cleanup: strip any entered scheme so the field stays domain-only
    _url.addListener(() {
      if (_updatingUrl) return;
      final t = _url.text;
      final n = _stripScheme(t);
      if (t != n) {
        _updatingUrl = true;
        _url.value = TextEditingValue(
            text: n, selection: TextSelection.collapsed(offset: n.length));
        _updatingUrl = false;
      }
      final valid = n.isEmpty ? true : _isValidHost(n);
      final slash = n.trim().startsWith('/');
      if (valid != _hostValid || slash != _slashMode) {
        setState(() {
          _hostValid = valid;
          _slashMode = slash;
        });
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

  @override
  void reassemble() {
    super.reassemble();
    setState(() {
      _sectionHelpOpen = false;
      _sectionStartupOpen = false;
    });
  }

  Future<void> _saveAndTest() async {
    final app = context.read<AppState>();
    final l10n = L10n.of(context);
    final hostOnly = _stripScheme(_url.text);
    if (!_isValidHost(hostOnly)) {
      setState(() {
        _testMsg = l10n.invalidServerAddress;
      });
      return;
    }
    final fullUrl = hostOnly.startsWith('/') ? hostOnly : 'https://$hostOnly';
    await app.setCredentials(
        baseUrl: fullUrl, username: _user.text, password: _pass.text);
    setState(() {
      _testing = true;
      _testMsg = null;
      _testOk = false;
    });
    try {
      final ok = await app.testLogin();
      if (!ok) {
        setState(() {
          _testing = false;
          _testMsg = l10n.errorMsg('Login');
          _testOk = false;
        });
        return;
      }
      // Prüfen, ob Deck aktiviert ist
      final hasDeck =
          await app.api.hasDeckEnabled(app.baseUrl!, app.username!, _pass.text);
      if (!hasDeck) {
        setState(() {
          _testing = false;
          _testMsg = l10n.errorMsg('Deck-App nicht verfügbar');
          _testOk = false;
        });
        return;
      }
      // Use new sync system - direct call without runWithSyncing wrapper
      try {
        // Listen to boot messages during sync
        void syncListener() {
          if (mounted && app.bootSyncing) {
            setState(() {
              _testMsg = app.bootMessage ?? 'Synchronisiere...';
            });
          }
        }

        app.addListener(syncListener);

        await app.configureSyncForCurrentAccount();

        app.removeListener(syncListener);

        if (!mounted) return;
        final count = app.boards.length;
        setState(() {
          _testing = false;
          _testMsg = count == 0
              ? l10n.loginOkNoBoards
              : 'Login OK - $count Boards gefunden, alle Stacks und Karten synchronisiert';
          _testOk = true;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _testing = false;
          _testMsg = l10n.errorMsg(e.toString());
          _testOk = false;
        });
      }
    } catch (e) {
      setState(() {
        _testing = false;
        _testMsg = l10n.errorMsg(e.toString());
        _testOk = false;
      });
    }
  }

  Future<void> _confirmClearLocalData() async {
    final l10n = L10n.of(context);
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.clearLocalDataConfirmTitle),
        content: Text(l10n.clearLocalDataConfirmMessage),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel)),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.clearLocalDataConfirmAction,
              style: const TextStyle(color: CupertinoColors.white),
            ),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      final app = context.read<AppState>();
      await app.runWithSyncing(() async {
        await app.clearLocalData();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l10n = L10n.of(context);
    return CupertinoPageScaffold(
      backgroundColor: AppTheme.appBackground(app),
      navigationBar: CupertinoNavigationBar(middle: Text(l10n.settingsTitle)),
      child: SafeArea(
        child: ListView(
          // Bottom-Reserve für die schwebende Tab-Bar — sonst wird die
          // letzte Sektion ("Support") teilweise verdeckt.
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + DT.tabBarReserve),
          children: [
            _SettingsSection(
              title: l10n.nextcloudAccess,
              expanded: _sectionAccountOpen,
              isDarkMode: app.isDarkMode,
              onToggle: () =>
                  setState(() => _sectionAccountOpen = !_sectionAccountOpen),
              children: [
                CupertinoTextField(
                  controller: _url,
                  placeholder: l10n.urlPlaceholder,
                  keyboardType: TextInputType.url,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  enableSuggestions: false,
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 6, right: 4),
                    child: Text('https://',
                        style: TextStyle(
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context))),
                  ),
                  suffix: _hostValid
                      ? null
                      : const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(CupertinoIcons.exclamationmark_circle,
                              color: CupertinoColors.systemRed, size: 18),
                        ),
                  decoration: BoxDecoration(
                    color:
                        CupertinoColors.tertiarySystemFill.resolveFrom(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _hostValid
                            ? CupertinoColors.separator.resolveFrom(context)
                            : CupertinoColors.systemRed,
                        width: _hostValid ? 0.5 : 1.0),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.httpsEnforcedInfo,
                  style: const TextStyle(
                      color: CupertinoColors.systemGrey, fontSize: 12),
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
                  placeholder: l10n.appPassword,
                  obscureText: true,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.appPasswordHint,
                  style: const TextStyle(
                      color: CupertinoColors.systemGrey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                CupertinoButton.filled(
                  onPressed: _testing ? null : _saveAndTest,
                  child: _testing
                      ? const CupertinoActivityIndicator()
                      : Text(l10n.loginAndLoadBoards),
                ),
                if (_testMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(_testMsg!,
                      style: TextStyle(
                          color: _testOk
                              ? CupertinoColors.activeGreen
                              : CupertinoColors.destructiveRed)),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: l10n.help,
              expanded: _sectionHelpOpen,
              isDarkMode: app.isDarkMode,
              onToggle: () =>
                  setState(() => _sectionHelpOpen = !_sectionHelpOpen),
              children: [
                Text(l10n.helpQuickStartTitle,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(l10n.helpQuickStartBody,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
                const SizedBox(height: 10),
                Text(l10n.helpTipsTitle,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(l10n.helpTipsBody,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: l10n.startupPage,
              expanded: _sectionStartupOpen,
              isDarkMode: app.isDarkMode,
              onToggle: () =>
                  setState(() => _sectionStartupOpen = !_sectionStartupOpen),
              children: [
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
                      if (v != null)
                        context.read<AppState>().setStartupTabIndex(v);
                    },
                  );
                }),
                const SizedBox(height: 12),
                Text(l10n.activeBoardSection,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(l10n.startupBoardChoice)),
                  ],
                ),
                const SizedBox(height: 8),
                Builder(builder: (ctx) {
                  final options = <String, Widget>{
                    'default': Text(L10n.of(ctx).startupBoardDefault),
                    'last': Text(L10n.of(ctx).startupBoardLast),
                  };
                  return CupertinoSlidingSegmentedControl<String>(
                    groupValue: app.startupBoardMode,
                    children: options,
                    onValueChanged: (v) {
                      if (v != null)
                        context.read<AppState>().setStartupBoardMode(v);
                    },
                  );
                }),
                const SizedBox(height: 6),
                Text(l10n.startupBoardHelp,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
                const SizedBox(height: 12),
                if (app.boards.isEmpty)
                  Text(l10n.noBoardsPleaseTest)
                else
                  _BoardPicker(
                    boards: app.boards.where((b) => !b.archived).toList(),
                    selected: () {
                      final d = app.defaultBoardId;
                      if (d != null) {
                        return app.boards.firstWhere(
                          (b) => b.id == d,
                          orElse: () =>
                              app.activeBoard ??
                              (app.boards.isNotEmpty
                                  ? app.boards.first
                                  : Board.empty()),
                        );
                      }
                      return app.activeBoard;
                    }(),
                    onChanged: (b) => app.setDefaultBoard(b),
                  ),
              ],
            ),
            if (Platform.isIOS) ...[
              const SizedBox(height: 16),
              _SettingsSection(
                title: l10n.notifications,
                expanded: _sectionNotificationsOpen,
                isDarkMode: app.isDarkMode,
                onToggle: () => setState(() =>
                    _sectionNotificationsOpen = !_sectionNotificationsOpen),
                children: [
                  Row(children: [
                    Expanded(child: Text(l10n.dueNotificationsEnable)),
                    CupertinoSwitch(
                      value: app.dueNotificationsEnabled,
                      onChanged: (v) => app.setDueNotificationsEnabled(v),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(l10n.dueNotificationsHelp,
                      style: const TextStyle(
                          color: CupertinoColors.systemGrey, fontSize: 12)),
                  if (app.dueNotificationsEnabled) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: Text(l10n.reminder1hBefore)),
                      CupertinoSwitch(
                        value: app.dueReminder1hEnabled,
                        onChanged: (v) =>
                            app.setDueReminderOffsetEnabled(60, v),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: Text(l10n.reminder1dBefore)),
                      CupertinoSwitch(
                        value: app.dueReminder1dEnabled,
                        onChanged: (v) =>
                            app.setDueReminderOffsetEnabled(1440, v),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: Text(l10n.overdueReminderToggle)),
                      CupertinoSwitch(
                        value: app.dueOverdueEnabled,
                        onChanged: (v) => app.setDueOverdueEnabled(v),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Text(l10n.activityNotificationsEnable)),
                    CupertinoSwitch(
                      value: app.activityNotificationsEnabled,
                      onChanged: (v) async {
                        final granted =
                            await app.setActivityNotificationsEnabled(v);
                        if (!mounted) return;
                        if (v && !granted) {
                          // iOS hat Permission blockiert / abgelehnt.
                          final wantSettings =
                              await showCupertinoDialog<bool>(
                            context: context,
                            builder: (ctx) => CupertinoAlertDialog(
                              title: const Text(
                                  'iOS blockiert Mitteilungen'),
                              content: const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'iOS verhindert gerade, dass Nextdeck '
                                  'Banner anzeigen kann. '
                                  'Bitte aktiviere die Mitteilungen in '
                                  'den iOS-Einstellungen für Nextdeck.',
                                ),
                              ),
                              actions: [
                                CupertinoDialogAction(
                                  isDefaultAction: true,
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(true),
                                  child: const Text('Zu Einstellungen'),
                                ),
                                CupertinoDialogAction(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(false),
                                  child: const Text('Später'),
                                ),
                              ],
                            ),
                          );
                          if (wantSettings == true) {
                            await app.openIosAppSettings();
                          }
                        }
                      },
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(l10n.activityNotificationsHelp,
                      style: const TextStyle(
                          color: CupertinoColors.systemGrey, fontSize: 12)),
                  // Permission-Status-Zeile — sichtbar wenn Toggle an,
                  // damit der User direkt sieht ob iOS blockiert.
                  if (app.activityNotificationsEnabled)
                    FutureBuilder<bool?>(
                      future: app.checkIosNotifPermission(),
                      builder: (context, snap) {
                        final ok = snap.data == true;
                        if (snap.connectionState != ConnectionState.done) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(
                                ok
                                    ? CupertinoIcons.checkmark_seal_fill
                                    : CupertinoIcons.exclamationmark_triangle_fill,
                                color: ok
                                    ? CupertinoColors.activeGreen
                                    : CupertinoColors.systemRed,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  ok
                                      ? 'iOS-Mitteilungen erlaubt'
                                      : 'iOS-Mitteilungen blockiert — Banner kommen nicht durch',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: ok
                                        ? CupertinoColors.systemGrey
                                        : CupertinoColors.systemRed,
                                  ),
                                ),
                              ),
                              if (!ok)
                                CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 0),
                                  onPressed: () =>
                                      app.openIosAppSettings(),
                                  child: const Text('Öffnen',
                                      style: TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                        );
                      },
                    ),

                  if (app.activityNotificationsEnabled) ...[
                    const SizedBox(height: 14),
                    const Text('Quelle',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    CupertinoSlidingSegmentedControl<String>(
                      groupValue: app.notificationSource,
                      children: const {
                        'activity': Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('Aktivitäten',
                              style: TextStyle(fontSize: 12)),
                        ),
                        'notifications': Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('Notifications',
                              style: TextStyle(fontSize: 12)),
                        ),
                        'both': Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('Beide',
                              style: TextStyle(fontSize: 12)),
                        ),
                      },
                      onValueChanged: (v) {
                        if (v != null) app.setNotificationSource(v);
                      },
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '„Aktivitäten" ist immun gegen Race-Conditions, '
                      'wenn die offizielle Nextcloud-App parallel läuft. '
                      '„Notifications" nutzt die zentrale Notifications-API '
                      '(kann mit der Nextcloud-App kollidieren).',
                      style: TextStyle(
                          color: CupertinoColors.systemGrey, fontSize: 12),
                    ),

                    const SizedBox(height: 14),
                    const Text('Welche Aktivitäten benachrichtigen?',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    _NotifFilterToggle(
                      label: 'Karten an mich zugewiesen',
                      filterKey: 'assigned',
                      app: app,
                    ),
                    _NotifFilterToggle(
                      label: '@-Erwähnungen (Beschreibung & Kommentare)',
                      filterKey: 'mention',
                      app: app,
                    ),
                    _NotifFilterToggle(
                      label: 'Neue Kommentare',
                      filterKey: 'comment',
                      app: app,
                    ),
                    _NotifFilterToggle(
                      label: 'Geteilte Boards/Karten',
                      filterKey: 'share',
                      app: app,
                    ),
                    _NotifFilterToggle(
                      label: 'Sonstige Deck-Aktivität',
                      filterKey: 'updates',
                      app: app,
                    ),

                    const SizedBox(height: 14),
                    const Text('Prüf-Intervall',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    CupertinoSlidingSegmentedControl<int>(
                      groupValue: _clampPollMinutes(
                          app.notificationPollMinutes),
                      children: const {
                        0: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child:
                              Text('Aus', style: TextStyle(fontSize: 12)),
                        ),
                        1: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child:
                              Text('1 min', style: TextStyle(fontSize: 12)),
                        ),
                        5: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child:
                              Text('5 min', style: TextStyle(fontSize: 12)),
                        ),
                        15: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child:
                              Text('15 min', style: TextStyle(fontSize: 12)),
                        ),
                        30: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child:
                              Text('30 min', style: TextStyle(fontSize: 12)),
                        ),
                      },
                      onValueChanged: (v) {
                        if (v != null) app.setNotificationPollMinutes(v);
                      },
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Im Vordergrund läuft der Poll als Teil des Sync-Ticks '
                      '(max. dieser Intervall). Im Hintergrund entscheidet '
                      'iOS — typisch alle 15–60 min.',
                      style: TextStyle(
                          color: CupertinoColors.systemGrey, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 16),
            _SettingsSection(
              title: l10n.appearance,
              expanded: _sectionAppearanceOpen,
              isDarkMode: app.isDarkMode,
              onToggle: () => setState(
                  () => _sectionAppearanceOpen = !_sectionAppearanceOpen),
              children: [
                Text(l10n.themeMode,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                CupertinoSlidingSegmentedControl<String>(
                  groupValue: app.themeMode,
                  children: {
                    'light': Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(l10n.themeLight),
                    ),
                    'dark': Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(l10n.themeDark),
                    ),
                    'system': Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(l10n.themeSystem),
                    ),
                  },
                  onValueChanged: (mode) {
                    if (mode != null) {
                      app.setThemeMode(mode);
                    }
                  },
                ),
                const SizedBox(height: 6),
                Text(l10n.themeModeHelp,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
                const SizedBox(height: 12),
                Text(l10n.boardBandMode,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                CupertinoSlidingSegmentedControl<String>(
                  groupValue: app.boardBandMode,
                  children: {
                    'nextcloud': Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(l10n.boardBandNextcloud),
                    ),
                    'hidden': Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(l10n.boardBandHidden),
                    ),
                  },
                  onValueChanged: (mode) {
                    if (mode != null) {
                      app.setBoardBandMode(mode);
                    }
                  },
                ),
                const SizedBox(height: 6),
                Text(l10n.boardBandHelp,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(l10n.smartColors)),
                    CupertinoSwitch(
                        value: app.smartColors,
                        onChanged: (v) => app.setSmartColors(v)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(l10n.smartColorsHelp,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(l10n.cardColorsFromLabels)),
                    CupertinoSwitch(
                        value: app.cardColorsFromLabels,
                        onChanged: (v) => app.setCardColorsFromLabels(v)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(l10n.cardColorsFromLabelsHelp,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(l10n.showDescriptionAlways)),
                    CupertinoSwitch(
                        value: app.showDescriptionText,
                        onChanged: (v) => app.setShowDescriptionText(v)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(l10n.showDescriptionHelp,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(l10n.overviewShowBoardInfo)),
                    CupertinoSwitch(
                        value: app.overviewShowBoardInfo,
                        onChanged: (v) => app.setOverviewShowBoardInfo(v)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(l10n.overviewShowBoardInfoHelp,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(l10n.upcomingSingleColumnLabel)),
                    CupertinoSwitch(
                        value: app.upcomingSingleColumn,
                        onChanged: (v) => app.setUpcomingSingleColumn(v)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(l10n.upcomingSingleColumnHelp,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: l10n.language,
              expanded: _sectionLanguageOpen,
              isDarkMode: app.isDarkMode,
              onToggle: () =>
                  setState(() => _sectionLanguageOpen = !_sectionLanguageOpen),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        app.localeCode == null
                            ? l10n.systemLanguage
                            : (app.localeCode == 'de'
                                ? l10n.german
                                : app.localeCode == 'es'
                                    ? l10n.spanish
                                    : l10n.english),
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
                              CupertinoActionSheetAction(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    app.setLocale(null);
                                  },
                                  child: Text(l10n.systemLanguage)),
                              CupertinoActionSheetAction(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    app.setLocale('de');
                                  },
                                  child: Text(l10n.german)),
                              CupertinoActionSheetAction(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    app.setLocale('en');
                                  },
                                  child: Text(l10n.english)),
                              CupertinoActionSheetAction(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    app.setLocale('es');
                                  },
                                  child: Text(l10n.spanish)),
                            ],
                            cancelButton: CupertinoActionSheetAction(
                                onPressed: () => Navigator.of(ctx).pop(),
                                isDefaultAction: true,
                                child: Text(l10n.cancel)),
                          ),
                        );
                      },
                      child: const Icon(CupertinoIcons.globe),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: 'Synchronisation',
              expanded: _sectionSyncOpen,
              isDarkMode: app.isDarkMode,
              onToggle: () =>
                  setState(() => _sectionSyncOpen = !_sectionSyncOpen),
              children: [
                const Text(
                  'Wie oft die App im Hintergrund Änderungen vom Server holt. '
                  'Bei jedem Sync werden Karten-Zuweisungen und @-Erwähnungen '
                  'geprüft – entsprechende Benachrichtigungen erscheinen, '
                  'sofern sie unter „Benachrichtigungen" aktiv sind.',
                  style: TextStyle(
                      color: CupertinoColors.systemGrey, fontSize: 12),
                ),
                const SizedBox(height: 14),

                // ---- Globaler Standard ----
                const Text('Standard für alle Boards',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                CupertinoSlidingSegmentedControl<int>(
                  groupValue: app.globalSyncIntervalMinutes,
                  children: const {
                    0: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Aus'),
                    ),
                    5: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('5 min'),
                    ),
                    15: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('15 min'),
                    ),
                    30: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('30 min'),
                    ),
                    60: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('60 min'),
                    ),
                  },
                  onValueChanged: (v) {
                    if (v != null) app.setGlobalSyncInterval(v);
                  },
                ),
                const SizedBox(height: 6),
                const Text(
                  '„Aus" deaktiviert den automatischen Sync. Pull-to-Refresh '
                  'in „Anstehend" wirkt jederzeit weiter.',
                  style: TextStyle(
                      color: CupertinoColors.systemGrey, fontSize: 12),
                ),

                // ---- Aktives Board ----
                if (app.activeBoard != null) ...[
                  const SizedBox(height: 18),
                  Text('Aktives Board: ${app.activeBoard!.title}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  _SyncIntervalSegmented(
                    currentOverride:
                        app.boardSyncIntervalOverride(app.activeBoard!.id),
                    onSelect: (v) {
                      final activeId = app.activeBoard!.id;
                      if (v == null) {
                        app.clearBoardSyncOverride(activeId);
                      } else {
                        app.setBoardSyncInterval(activeId, v);
                      }
                    },
                  ),
                ],

                // ---- Andere Boards ----
                const SizedBox(height: 18),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() =>
                      _sectionSyncOtherBoardsOpen =
                          !_sectionSyncOtherBoardsOpen),
                  child: Row(
                    children: [
                      Icon(
                          _sectionSyncOtherBoardsOpen
                              ? CupertinoIcons.chevron_down
                              : CupertinoIcons.chevron_right,
                          size: 14,
                          color: CupertinoColors.systemGrey),
                      const SizedBox(width: 6),
                      const Text('Weitere Boards',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (_sectionSyncOtherBoardsOpen) ...[
                  const SizedBox(height: 8),
                  for (final b in app.boards.where((bb) =>
                      !bb.archived &&
                      !app.isBoardHidden(bb.id) &&
                      bb.id != app.activeBoard?.id)) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Text(b.title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    _SyncIntervalSegmented(
                      currentOverride: app.boardSyncIntervalOverride(b.id),
                      onSelect: (v) {
                        if (v == null) {
                          app.clearBoardSyncOverride(b.id);
                        } else {
                          app.setBoardSyncInterval(b.id, v);
                        }
                      },
                    ),
                  ],
                ],
              ],
            ),

            const SizedBox(height: 16),
            _SettingsSection(
              title: l10n.performance,
              expanded: _sectionPerformanceOpen,
              isDarkMode: app.isDarkMode,
              onToggle: () => setState(
                  () => _sectionPerformanceOpen = !_sectionPerformanceOpen),
              children: [
                Text(L10n.of(context).fullSyncManualHint,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Text(L10n.of(context).showOnlyMyCardsLabel)),
                  CupertinoSwitch(
                      value: app.upcomingAssignedOnly,
                      onChanged: (v) async {
                        app.setUpcomingAssignedOnly(v);
                        if (v) {
                          await app.refreshUpcomingAssigneesIfNeeded();
                        }
                      })
                ]),
                const SizedBox(height: 6),
                Text(L10n.of(context).showOnlyMyCardsHelp,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
                const SizedBox(height: 8),
                Text(L10n.of(context).upcomingProgressHelp,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
                // Hinweis: Der frühere Per-Board-Sync-Selector ist in die
                // dedizierte Sektion „Synchronisation" weiter oben verschoben
                // (Globaler Default + Pro-Board-Override für alle Boards).
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: l10n.localBoardSection,
              expanded: _sectionLocalOpen,
              isDarkMode: app.isDarkMode,
              onToggle: () =>
                  setState(() => _sectionLocalOpen = !_sectionLocalOpen),
              children: [
                if (app.localMode) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemYellow.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: CupertinoColors.systemYellow),
                    ),
                    child: Text(l10n.localModeBanner,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(height: 12),
                ],
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
                                CupertinoDialogAction(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: Text(l10n.cancel)),
                                CupertinoDialogAction(
                                  isDefaultAction: true,
                                  onPressed: () async {
                                    Navigator.of(ctx).pop();
                                    await context
                                        .read<AppState>()
                                        .setLocalMode(true);
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
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: l10n.developer,
              expanded: _sectionDeveloperOpen,
              isDarkMode: app.isDarkMode,
              onToggle: () => setState(
                  () => _sectionDeveloperOpen = !_sectionDeveloperOpen),
              children: [
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
                  onPressed: () => Navigator.of(context).push(
                      CupertinoPageRoute(builder: (_) => const DebugLogPage())),
                  child: Text(l10n.viewLogs),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: l10n.supportAndData,
              expanded: _sectionSupportOpen,
              isDarkMode: app.isDarkMode,
              onToggle: () =>
                  setState(() => _sectionSupportOpen = !_sectionSupportOpen),
              children: [
                Text(l10n.helpContact,
                    style: const TextStyle(
                        color: CupertinoColors.systemBlue, fontSize: 13)),
                const SizedBox(height: 12),
                Text(L10n.of(context).clearLocalDataHelp,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.systemRed, context),
                    onPressed: app.isSyncing ? null : _confirmClearLocalData,
                    child: Text(
                      L10n.of(context).clearLocalData,
                      style: const TextStyle(color: CupertinoColors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    () {
                      final idx = kAppVersion.indexOf('+');
                      final pretty = idx > 0
                          ? '${kAppVersion.substring(0, idx)} (${kAppVersion.substring(idx + 1)})'
                          : kAppVersion;
                      return '${l10n.appVersionLabel}: $pretty';
                    }(),
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12),
                  ),
                ),
              ],
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
                      border: Border.all(
                          color: i == selected
                              ? CupertinoColors.activeBlue
                              : CupertinoColors.separator),
                      gradient: LinearGradient(colors: [
                        Color(AppTheme.palettesLight[i][0]),
                        Color(AppTheme.palettesLight[i][3]),
                      ]),
                    ),
                    alignment: Alignment.center,
                    child: Text('Theme ${i + 1}',
                        style: const TextStyle(fontSize: 12)),
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
  const _BoardPicker(
      {required this.boards, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final controller = FixedExtentScrollController(
      initialItem: selected == null
          ? 0
          : boards
              .indexWhere((b) => b.id == selected!.id)
              .clamp(0, boards.length - 1),
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

class _SettingsSection extends StatelessWidget {
  final String title;
  final bool expanded;
  final bool isDarkMode;
  final VoidCallback onToggle;
  final List<Widget> children;
  const _SettingsSection({
    required this.title,
    required this.expanded,
    required this.isDarkMode,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Row(
            children: [
              Icon(
                  expanded
                      ? CupertinoIcons.chevron_down
                      : CupertinoIcons.chevron_right,
                  size: 16,
                  color: CupertinoColors.systemGrey),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: DT.spaceS),
          Container(
            decoration: BoxDecoration(
              color: CupertinoTheme.of(context)
                  .barBackgroundColor
                  .withOpacity(isDarkMode ? 0.25 : 0.7),
              borderRadius: BorderRadius.circular(DT.radiusM),
              // Modernerer Look: Soft-Shadow statt 1-px-Border. Sektionen
              // wirken dadurch als eigene Karten statt umrandeter Boxen.
              boxShadow: DT.shadowS(isDarkMode),
            ),
            padding: const EdgeInsets.all(DT.spaceM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ],
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

/// Clamp-Helper für den Notification-Poll-Selector.
/// Wenn der gespeicherte Wert nicht zu unseren Buckets passt
/// (z. B. ein User hat 7 Min in einem alten Build gesetzt), zeigen wir
/// den nächsten gültigen.
int _clampPollMinutes(int v) {
  const allowed = [0, 1, 5, 15, 30];
  if (allowed.contains(v)) return v;
  // Fallback: nächst-näherer Wert
  if (v <= 0) return 0;
  if (v <= 3) return 1;
  if (v <= 10) return 5;
  if (v <= 22) return 15;
  return 30;
}

/// Toggle-Zeile für einen Activity-Filter — schreibt in das Set
/// `notificationFilters` der AppState.
class _NotifFilterToggle extends StatelessWidget {
  final String label;
  final String filterKey;
  final AppState app;
  const _NotifFilterToggle({
    required this.label,
    required this.filterKey,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    final active = app.notificationFilters.contains(filterKey);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          CupertinoSwitch(
            value: active,
            onChanged: (v) {
              final next = Set<String>.from(app.notificationFilters);
              if (v) {
                next.add(filterKey);
              } else {
                next.remove(filterKey);
              }
              app.setNotificationFilters(next);
            },
          ),
        ],
      ),
    );
  }
}

/// Segmented Control für Per-Board-Sync-Intervall.
/// `currentOverride == null`  → das Board nutzt den globalen Default
/// `currentOverride == 0`     → Auto-Sync explizit "Aus" für dieses Board
/// `currentOverride > 0`      → Override-Intervall in Minuten
///
/// `onSelect(null)` löscht den Override → fallback auf globalen Standard.
class _SyncIntervalSegmented extends StatelessWidget {
  final int? currentOverride;
  final ValueChanged<int?> onSelect;

  const _SyncIntervalSegmented({
    required this.currentOverride,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    // Marker-Wert -1 = "Standard" (kein Override) — null funktioniert in
    // CupertinoSlidingSegmentedControl<int> nicht zuverlässig.
    const allowedKeys = {-1, 0, 1, 5, 15, 30};
    final raw = currentOverride;
    // Robust gegen unbekannte Override-Werte aus alten Settings-Versionen
    // (z. B. "1 min" aus der früheren Performance-Sektion). Wenn der Wert
    // nicht zu unseren Keys passt, geben wir groupValue=null an den
    // SegmentedControl → kein Crash, einfach keine Auswahl markiert.
    final int? value = raw == null
        ? -1
        : (allowedKeys.contains(raw) ? raw : null);
    return CupertinoSlidingSegmentedControl<int>(
      groupValue: value,
      children: const {
        -1: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('Standard', style: TextStyle(fontSize: 12)),
        ),
        0: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('Aus', style: TextStyle(fontSize: 12)),
        ),
        1: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('1', style: TextStyle(fontSize: 12)),
        ),
        5: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('5', style: TextStyle(fontSize: 12)),
        ),
        15: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('15', style: TextStyle(fontSize: 12)),
        ),
        30: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('30', style: TextStyle(fontSize: 12)),
        ),
      },
      onValueChanged: (v) {
        if (v == null) return;
        if (v == -1) {
          onSelect(null);
        } else {
          onSelect(v);
        }
      },
    );
  }
}
