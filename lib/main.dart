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

class _RootTabs extends StatelessWidget {
  const _RootTabs();

  // Navigator keys to allow popping to root when re-tapping active tab
  static final GlobalKey<NavigatorState> upcomingNavKey = GlobalKey<NavigatorState>();
  static final GlobalKey<NavigatorState> boardNavKey = GlobalKey<NavigatorState>();
  static final GlobalKey<NavigatorState> overviewNavKey = GlobalKey<NavigatorState>();
  static final GlobalKey<NavigatorState> settingsNavKey = GlobalKey<NavigatorState>();

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
                ? upcomingNavKey
                : (index == 1)
                    ? boardNavKey
                    : (index == 2)
                        ? overviewNavKey
                        : settingsNavKey;
            nav.currentState?.popUntil((r) => r.isFirst);
          }
          app.selectTab(index);
        },
      ),
      tabBuilder: (context, index) {
        switch (index) {
          case 0:
            return CupertinoTabView(
              navigatorKey: upcomingNavKey,
              builder: (_) => const UpcomingPage(),
            );
          case 1:
            return CupertinoTabView(
              navigatorKey: boardNavKey,
              builder: (_) => const BoardPage(),
            );
          case 2:
            return CupertinoTabView(
              navigatorKey: overviewNavKey,
              builder: (_) => const OverviewPage(),
            );
          case 3:
          default:
            return CupertinoTabView(
              navigatorKey: settingsNavKey,
              builder: (_) => const SettingsPage(),
            );
        }
      },
    );
  }
}
