import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'state/app_state.dart';
import 'pages/overview_page.dart';
import 'pages/board_page.dart';
import 'pages/settings_page.dart';
import 'pages/upcoming_page.dart';
import 'pages/splash_page.dart';
import 'l10n/app_localizations.dart';
import 'navigation/nav_keys.dart';
import 'models/board.dart';
import 'models/column.dart' as deck;
import 'models/card_item.dart';
import 'theme/app_theme.dart';
import 'theme/design_tokens.dart';
import 'pages/card_detail_page.dart';
import 'services/background_poll_service.dart';

import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('nextdeck_cache');
  // NC 2.0: Liquid-Glass-Shader vorwärmen, bevor die UI hochkommt —
  // verhindert Ruckler beim ersten Glass-Rendering.
  await LiquidGlassWidgets.initialize();
  runApp(LiquidGlassWidgets.wrap(child: const NextDeckApp()));
  // iOS Background Fetch wird ERST NACH dem ersten Frame initialisiert,
  // damit ein langsamer BGTaskScheduler-Init die UI nicht blockiert.
  // Plus Try-Catch, falls das Plugin auf neueren iOS-Versionen
  // unerwartet wirft.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(seconds: 2), () async {
      try {
        await initializeBackgroundFetch();
      } catch (e, st) {
        debugPrint('[main] initializeBackgroundFetch failed: $e\n$st');
      }
    });
  });
}

class NextDeckApp extends StatelessWidget {
  const NextDeckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, app, _) {
          final platformBrightness = MediaQuery.platformBrightnessOf(context);
          app.updatePlatformBrightness(platformBrightness);
          final isDark = app.isDarkMode;
          final theme = CupertinoThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
          );
          // NC 2.0 „farbstark": der Glass-Glow folgt der aktiven Board-Farbe.
          // Dadurch färbt sich das UI-Chrome (Tab-Bar-Indikator, Buttons)
          // dezent nach dem Board, in dem der User gerade arbeitet.
          final Color accent =
              AppTheme.boardColorFrom(app.activeBoard?.color) ??
                  const Color(0xFF1E88E5);
          final glassTheme = GlassThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
            light: GlassThemeVariant.light.copyWith(
              glowColors: GlassGlowColors(
                primary: accent,
                glowBlurRadius: 24,
                glowOpacity: 0.55,
              ),
              borderRadius: DT.radiusXl,
            ),
            dark: GlassThemeVariant.dark.copyWith(
              glowColors: GlassGlowColors(
                primary: accent,
                glowBlurRadius: 24,
                glowOpacity: 0.6,
              ),
              borderRadius: DT.radiusXl,
            ),
          );
          return CupertinoApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            // honor manual language selection if set
            locale: app.localeCode == null ? null : Locale(app.localeCode!),
            localeResolutionCallback: (deviceLocale, supported) {
              // If device locale not supported and no manual override, fallback to English
              final code = app.localeCode ?? deviceLocale?.languageCode;
              if (code == 'de') return const Locale('de');
              if (code == 'es') return const Locale('es');
              if (code == 'en') return const Locale('en');
              return const Locale('en');
            },
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              L10n.delegate,
            ],
            supportedLocales: const [
              Locale('de'),
              Locale('en'),
              Locale('es'),
            ],
            home: GlassTheme(data: glassTheme, child: const _RootTabs()),
          );
        },
      ),
    );
  }
}

class _HomeSwitcher extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final needSplash = (!app.localMode && app.baseUrl != null && app.username != null)
        ? (app.bootSyncing || app.boards.isEmpty)
        : false;
    if (needSplash) return const SplashPage();
    return const _RootTabs();
  }
}

class _RootTabs extends StatefulWidget {
  const _RootTabs();

  @override
  State<_RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<_RootTabs> {
  AppState? _appRef;
  bool _openingFromWidget = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (_appRef == null) {
      _appRef = app;
      app.addListener(_handleAppChange);
    }
  }

  @override
  void dispose() {
    _appRef?.removeListener(_handleAppChange);
    super.dispose();
  }

  void _handleAppChange() {
    if (!mounted || _openingFromWidget) return;
    final app = _appRef;
    if (app == null) return;
    final pending = app.pendingOpenCard;
    if (pending == null) return;
    _openingFromWidget = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final app = _appRef;
      if (app == null) return;
      final board = app.boards.firstWhere(
        (b) => b.id == pending.boardId,
        orElse: () => Board.empty(),
      );
      if (board.id < 0) {
        _openingFromWidget = false;
        return;
      }
      await app.setActiveBoard(board);
      if (app.columnsForBoard(board.id).isEmpty) {
        await app.refreshColumnsFor(board, forceNetwork: true);
      }
      final columns = app.columnsForBoard(board.id);
      if (columns.isEmpty) {
        _openingFromWidget = false;
        return;
      }
      final stack = _resolveStackForCard(columns, pending);
      if (stack == null) {
        _openingFromWidget = false;
        return;
      }
      final list = app.boardArchivedOnly
          ? (app.archivedCardsForBoard(board.id)[stack.id] ??
              const <CardItem>[])
          : stack.cards;
      if (list.isEmpty) {
        _openingFromWidget = false;
        return;
      }
      final card = list.firstWhere(
        (c) => c.id == pending.cardId,
        orElse: () => list.first,
      );
      final colIdx = columns.indexOf(stack);
      final cardIdx = list.indexOf(card);
      final bg = AppTheme.cardBg(
          app, card.labels, colIdx < 0 ? 0 : colIdx, cardIdx < 0 ? 0 : cardIdx);
      app.consumePendingOpenCardAny();
      app.selectTab(1);
      final nav = AppNavKeys.boardNavKey.currentState;
      nav?.popUntil((route) => route.isFirst);
      await nav?.push(
        CupertinoPageRoute(
          builder: (_) => CardDetailPage(
            cardId: pending.cardId,
            boardId: board.id,
            stackId: stack.id,
            bgColor: bg,
            startEditing: pending.edit,
          ),
        ),
      );
      _openingFromWidget = false;
    });
  }

  deck.Column? _resolveStackForCard(
      List<deck.Column> columns, PendingCardOpen pending) {
    if (pending.stackId != null) {
      return columns.firstWhere(
        (c) => c.id == pending.stackId,
        orElse: () => columns.isNotEmpty
            ? columns.first
            : deck.Column(id: -1, title: '—', cards: const []),
      );
    }
    for (final col in columns) {
      if (col.cards.any((c) => c.id == pending.cardId)) return col;
    }
    return columns.isNotEmpty ? columns.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l10n = L10n.of(context);
    final mqBottom = MediaQuery.of(context).padding.bottom;

    // Wir hören direkt auf den `CupertinoTabController` (ChangeNotifier).
    // Wichtig: `app.selectTab(index)` setzt nur `tabController.index = …`
    // und ruft KEIN notifyListeners auf AppState. Ohne AnimatedBuilder
    // würde der Tab-Wechsel unsichtbar bleiben.
    return AnimatedBuilder(
      animation: app.tabController,
      builder: (context, _) {
        final currentIndex = app.tabController.index;

        void handleTap(int index) {
          if (index == currentIndex) {
            final nav = (index == 0)
                ? AppNavKeys.upcomingNavKey
                : (index == 1)
                    ? AppNavKeys.boardNavKey
                    : (index == 2)
                        ? AppNavKeys.overviewNavKey
                        : AppNavKeys.settingsNavKey;
            nav.currentState?.popUntil((r) => r.isFirst);
          }
          app.selectTab(index);
        }

        return CupertinoPageScaffold(
          child: Stack(
            children: [
              // 1) Tab-Inhalte: IndexedStack hält den State aller Tabs.
              Positioned.fill(
                child: IndexedStack(
                  index: currentIndex,
                  children: [
                    CupertinoTabView(
                      navigatorKey: AppNavKeys.upcomingNavKey,
                      builder: (_) => const UpcomingPage(),
                    ),
                    CupertinoTabView(
                      navigatorKey: AppNavKeys.boardNavKey,
                      builder: (_) => const BoardPage(),
                    ),
                    CupertinoTabView(
                      navigatorKey: AppNavKeys.overviewNavKey,
                      builder: (_) => const OverviewPage(),
                    ),
                    CupertinoTabView(
                      navigatorKey: AppNavKeys.settingsNavKey,
                      builder: (_) => const SettingsPage(),
                    ),
                  ],
                ),
              ),

              // 2) NC 2.0: Liquid-Glass-Tab-Bar mit echter Refraktion.
              // Icons neu gedacht: Kalender (Anstehend), Kanban-Spalten
              // (Board), App-Grid (Übersicht), Regler (Einstellungen).
              // Der Indikator glüht in der aktiven Board-Farbe.
              Positioned(
                left: 0,
                right: 0,
                bottom: mqBottom > 0 ? 0 : DT.spaceS,
                child: GlassTabBar.bottom(
                  selectedIndex: currentIndex,
                  onTabSelected: handleTap,
                  indicatorColor:
                      AppTheme.boardColorFrom(app.activeBoard?.color)
                          ?.withOpacity(0.35),
                  tabs: [
                    GlassTab(
                      icon: const Icon(CupertinoIcons.calendar),
                      activeIcon:
                          const Icon(CupertinoIcons.calendar_badge_plus),
                      label: l10n.navUpcoming,
                    ),
                    GlassTab(
                      icon: const Icon(CupertinoIcons.rectangle_split_3x1),
                      activeIcon: const Icon(
                          CupertinoIcons.rectangle_split_3x1_fill),
                      label: l10n.navBoard,
                      glowColor:
                          AppTheme.boardColorFrom(app.activeBoard?.color),
                    ),
                    GlassTab(
                      icon: const Icon(CupertinoIcons.square_grid_2x2),
                      activeIcon:
                          const Icon(CupertinoIcons.square_grid_2x2_fill),
                      label: l10n.overview,
                    ),
                    GlassTab(
                      icon: const Icon(CupertinoIcons.slider_horizontal_3),
                      label: l10n.settingsTitle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
