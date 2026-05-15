import 'package:background_fetch/background_fetch.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'nextcloud_deck_api.dart';

/// Hive-Box-Name des Background-Isolates. Bewusst getrennt vom
/// `nextdeck_cache` der Foreground-App: Hive 2 ist nicht safe für
/// concurrent Multi-Isolate-Zugriff auf dieselbe Box. Wenn iOS den
/// Headless-Task triggert, während die App gerade im Vordergrund ist,
/// würden beide Isolates dieselbe Datei beschreiben — Risiko sind
/// verlorene Writes oder im schlimmsten Fall Box-Korruption.
/// Mit separater Box pollt der Hintergrund eigenständig. Dedup auf der
/// UI-Seite läuft über die `flutter_local_notifications`-ID (identischer
/// Hash in beiden Isolates), iOS ersetzt Banner mit gleicher ID.
const String _kBgPollBoxName = 'nextdeck_bgpoll';

/// Hive-Cache-Key für die bereits gesehenen Server-Notification-IDs.
const String _kSeenNotifsKey = 'server_notifs_seen';
const String _kSeenActivitiesKey = 'server_activities_seen';

/// Headless-Background-Task — wird von iOS aufgerufen, wenn die App im
/// Hintergrund (oder gar nicht laufend) ist. Läuft in einem separaten
/// Isolate, hat also keinen Zugriff auf den UI-AppState.
@pragma('vm:entry-point')
Future<void> backgroundFetchHeadlessTask(HeadlessTask task) async {
  final taskId = task.taskId;
  try {
    if (task.timeout) {
      BackgroundFetch.finish(taskId);
      return;
    }
    await _runBackgroundPoll();
  } catch (e) {
    debugPrint('[bg-poll] headless error: $e');
  } finally {
    BackgroundFetch.finish(taskId);
  }
}

/// Konfiguriert das Plugin und startet den Foreground-Fetch-Loop.
/// Aufrufen direkt nach `runApp()` in main.dart.
Future<void> initializeBackgroundFetch() async {
  // Konfiguration: alle 15 min wäre ideal, iOS entscheidet aber selbst
  // (typisch 15-60 min, je nach Nutzungsmuster und Battery-State).
  final status = await BackgroundFetch.configure(
    BackgroundFetchConfig(
      minimumFetchInterval: 15,
      stopOnTerminate: false,
      enableHeadless: true,
      requiresBatteryNotLow: false,
      requiresCharging: false,
      requiresStorageNotLow: false,
      requiresDeviceIdle: false,
      requiredNetworkType: NetworkType.ANY,
    ),
    (taskId) async {
      // Foreground-/Background-Trigger via BGTaskScheduler.
      try {
        await _runBackgroundPoll();
      } catch (e) {
        debugPrint('[bg-poll] foreground error: $e');
      } finally {
        BackgroundFetch.finish(taskId);
      }
    },
    (taskId) {
      // Timeout — nichts mehr tun, sauber finishen.
      BackgroundFetch.finish(taskId);
    },
  );
  debugPrint('[bg-poll] configure status=$status');

  // Headless-Callback registrieren (für den Fall, dass die App
  // komplett beendet ist, wenn iOS triggert).
  BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
}

/// Eigentliche Polling-Logik: Server-Notifications fetchen und neue
/// Items als lokale Notifications rendern. Identisch zur Foreground-
/// Variante in app_state.dart, hier aber standalone (eigenes Isolate).
Future<void> _runBackgroundPoll() async {
  // 1) Hive im Hintergrund-Isolate initialisieren — eigene Box, damit
  // wir nicht parallel zu einem evtl. laufenden Foreground-Isolate auf
  // dieselbe Datei schreiben (siehe Kommentar zu `_kBgPollBoxName`).
  await Hive.initFlutter();
  final box = Hive.isBoxOpen(_kBgPollBoxName)
      ? Hive.box(_kBgPollBoxName)
      : await Hive.openBox(_kBgPollBoxName);

  // 2) Auth + Settings aus Secure Storage lesen.
  // Muss zur Accessibility in `AppState` passen, damit Items, die dort
  // mit `first_unlock_this_device` geschrieben wurden, hier gefunden werden.
  const storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  final baseUrl = await storage.read(key: 'baseUrl');
  final user = await storage.read(key: 'username');
  final pass = await storage.read(key: 'password');
  final activity = await storage.read(key: 'activity_notif_enabled');
  final source = await storage.read(key: 'notif_source') ?? 'activity';
  final filtersRaw = await storage.read(key: 'notif_filters');
  final filters = (filtersRaw == null || filtersRaw.trim().isEmpty)
      ? <String>{'assigned', 'mention'}
      : filtersRaw
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
  if (baseUrl == null || baseUrl.isEmpty) return;
  if (user == null || user.isEmpty) return;
  if (pass == null || pass.isEmpty) return;
  if (activity != '1') return;

  // 3) Beide Quellen je nach Settings.
  final api = NextcloudDeckApi();
  final newOnes = <Map<String, dynamic>>[];

  if (source == 'notifications' || source == 'both') {
    final raw = await api.fetchServerNotifications(baseUrl, user, pass);
    if (raw != null) {
      final seenList = box.get(_kSeenNotifsKey);
      final seen = seenList is List
          ? seenList.map((e) => e.toString()).toSet()
          : <String>{};
      final current = <String>{};
      for (final n in raw) {
        final idDyn = n['notification_id'] ?? n['id'];
        if (idDyn == null) continue;
        final id = idDyn.toString();
        current.add(id);
        if (!seen.contains(id)) newOnes.add(n);
      }
      await box.put(_kSeenNotifsKey, current.toList());
    }
  }

  if (source == 'activity' || source == 'both') {
    final raw = await api.fetchServerActivities(baseUrl, user, pass,
        limit: 50);
    if (raw != null) {
      final seenList = box.get(_kSeenActivitiesKey);
      final seen = seenList is List
          ? seenList.map((e) => e.toString()).toSet()
          : <String>{};
      final current = <String>{};
      for (final a in raw) {
        final idDyn = a['activity_id'] ?? a['id'];
        if (idDyn == null) continue;
        final id = idDyn.toString();
        current.add(id);
        if (seen.contains(id)) continue;
        if (_activityMatchesFilter(a, filters, user)) newOnes.add(a);
      }
      await box.put(_kSeenActivitiesKey, current.toList());
      // Bootstrap: bei leerem seen-Set nur seeden, kein Burst.
      if (seen.isEmpty) {
        // Nur Activity-Items wieder rauswerfen, die wir gerade neu gesehen
        // haben — andere Source-Items (Notifs) bleiben drin.
        newOnes.removeWhere((e) =>
            (e['activity_id'] ?? e['id'])?.toString() != null &&
            current.contains(
                (e['activity_id'] ?? e['id']).toString()));
      }
    }
  }

  if (newOnes.isEmpty) return;

  // 5) Lokale Notifications feuern (im Background-Isolate).
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );
  for (final n in newOnes.take(5)) {
    final subject = (n['subject'] ?? '').toString().trim();
    final message = (n['message'] ?? '').toString().trim();
    final objectName = (n['object_name'] ?? '').toString().trim();
    final title = subject.isNotEmpty ? subject : 'Neue Aktivität';
    final body = message.isNotEmpty
        ? message
        : (objectName.isNotEmpty ? objectName : subject);
    final hash = (n['notification_id'] ?? n['activity_id'] ?? n['id'])
        .toString()
        .hashCode
        .abs();
    final notifId = hash % 0x7FFFFFFF;
    try {
      await plugin.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
            presentBadge: true,
            interruptionLevel: InterruptionLevel.active,
          ),
        ),
      );
    } catch (_) {}
  }
}

/// Filter-Check für Activity-Items im Background-Isolate. Spiegelt die
/// Logik aus `AppState._activityMatchesFilter`.
bool _activityMatchesFilter(
    Map<String, dynamic> a, Set<String> filters, String me) {
  if (filters.isEmpty) return false;
  final app = (a['app'] ?? '').toString().toLowerCase();
  final type = (a['type'] ?? '').toString().toLowerCase();
  final subject = (a['subject'] ?? '').toString().toLowerCase();
  final user = (a['user'] ?? '').toString().toLowerCase();
  final myName = me.toLowerCase();
  if (myName.isNotEmpty && user == myName) return false;

  bool wants(String key) => filters.contains(key);
  // 'assigned' = NUR echte Zuweisungen — Foreground und Background
  // verhalten sich identisch.
  if (wants('assigned') &&
      (type.contains('assign') ||
          type == 'deck_user_added' ||
          subject.contains('zugewiesen') ||
          subject.contains('assigned'))) {
    return true;
  }
  if (wants('mention') &&
      (type == 'mention' ||
          subject.contains('mention') ||
          subject.contains('erwähnt') ||
          subject.contains('erwaehnt'))) {
    return true;
  }
  if (wants('comment') &&
      (type == 'comments' ||
          type == 'comment' ||
          subject.contains('comment') ||
          subject.contains('kommentar'))) {
    return true;
  }
  if (wants('share') &&
      (type.contains('share') ||
          subject.contains('shared') ||
          subject.contains('geteilt'))) {
    return true;
  }
  if (wants('updates') && app == 'deck') return true;
  return false;
}
