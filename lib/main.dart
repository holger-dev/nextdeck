import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
import 'pages/card_detail_page.dart';

import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('nextdeck_cache');
  runApp(const NextDeckApp());
}

class NextDeckApp extends StatelessWidget {
  const NextDeckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, app, _) {
          final l10n = L10n.of(context);
          final platformBrightness = MediaQuery.platformBrightnessOf(context);
          app.updatePlatformBrightness(platformBrightness);
          final isDark = app.isDarkMode;
          final theme = CupertinoThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
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
            home: const _RootTabs(),
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
    return CupertinoTabScaffold(
      controller: app.tabController,
      tabBar: CupertinoTabBar(
        items: [
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.time),
            label: l10n.navUpcoming,
          ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.square_list),
            label: l10n.navBoard,
          ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.rectangle_grid_2x2),
            label: l10n.overview,
          ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.gear),
            label: l10n.settingsTitle,
          ),
        ],
        onTap: (index) {
          // If re-tapping the current tab, pop to root of that tab's navigator
          if (index == app.tabController.index) {
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
        },
      ),
      tabBuilder: (context, index) {
        switch (index) {
          case 0:
            return CupertinoTabView(
              navigatorKey: AppNavKeys.upcomingNavKey,
              builder: (_) => const UpcomingPage(),
            );
          case 1:
            return CupertinoTabView(
              navigatorKey: AppNavKeys.boardNavKey,
              builder: (_) => const BoardPage(),
            );
          case 2:
            return CupertinoTabView(
              navigatorKey: AppNavKeys.overviewNavKey,
              builder: (_) => const OverviewPage(),
            );
          case 3:
          default:
            return CupertinoTabView(
              navigatorKey: AppNavKeys.settingsNavKey,
              builder: (_) => const SettingsPage(),
            );
        }
      },
    );
  }
}
