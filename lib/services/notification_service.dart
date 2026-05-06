import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/card_item.dart';
import '../l10n/app_localizations.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _tzInitialized = false;

  /// Initialisiert das Plugin und fordert ggf. iOS-Permissions an.
  /// Returnt:
  /// * `true`  — Permission erteilt (oder kein Request gemacht)
  /// * `false` — User hat „nicht erlauben" gewählt
  /// * `null`  — Plattform nicht iOS / Status unbekannt
  Future<bool?> init({bool requestPermissions = false}) async {
    if (!Platform.isIOS) return null;
    if (!_tzInitialized) {
      tz.initializeTimeZones();
      try {
        final timezone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(timezone.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.UTC);
      }
      _tzInitialized = true;
    }
    if (!_initialized) {
      // requestXxxPermission: true beim ersten initialize() lässt das
      // Plugin iOS gleich registrieren — sonst taucht die App in
      // System-Einstellungen → Mitteilungen gar nicht erst auf.
      // Der eigentliche Permission-Pop-up kommt erst, wenn der User
      // die Setting in der App aktiviert (siehe `init(requestPermissions: true)`).
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(iOS: ios);
      await _plugin.initialize(settings: settings);
      _initialized = true;
    }
    if (requestPermissions) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted;
    }
    return true;
  }

  /// Liefert den aktuellen iOS-Notification-Permission-Status.
  /// Returnt `true` wenn alle drei Kanäle (Alert, Badge, Sound) authorized
  /// sind, sonst `false`. `null` auf nicht-iOS.
  Future<bool?> hasIosPermission() async {
    if (!Platform.isIOS) return null;
    final impl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (impl == null) return null;
    final res = await impl.checkPermissions();
    if (res == null) return false;
    return res.isAlertEnabled == true || res.isAlertEnabled == null;
  }

  Future<void> cancelAll() async {
    if (!Platform.isIOS) return;
    await init();
    await _plugin.cancelAll();
  }

  Future<void> cancelForCard(int cardId) async {
    if (!Platform.isIOS) return;
    await init();
    for (final id in _idsForCard(cardId)) {
      await _plugin.cancel(id: id);
    }
  }

  Future<void> rescheduleForCard(
    CardItem card, {
    required List<Duration> offsets,
    required bool includeOverdue,
    required String? localeCode,
  }) async {
    if (!Platform.isIOS) return;
    await init();
    await cancelForCard(card.id);
    final candidates = _buildCandidates(
      [card],
      offsets: offsets,
      includeOverdue: includeOverdue,
      localeCode: localeCode,
    );
    for (final c in candidates) {
      await _plugin.zonedSchedule(
        id: c.id,
        title: c.title,
        body: c.body,
        scheduledDate: c.when,
        notificationDetails:
            const NotificationDetails(iOS: DarwinNotificationDetails()),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  Future<void> rescheduleAll(
    List<CardItem> cards, {
    required List<Duration> offsets,
    required bool includeOverdue,
    required String? localeCode,
    int maxScheduled = 50,
  }) async {
    if (!Platform.isIOS) return;
    await init();
    await _plugin.cancelAll();
    final candidates = _buildCandidates(
      cards,
      offsets: offsets,
      includeOverdue: includeOverdue,
      localeCode: localeCode,
    );
    candidates.sort((a, b) => a.when.compareTo(b.when));
    final limited = candidates.length <= maxScheduled
        ? candidates
        : candidates.sublist(0, maxScheduled);
    for (final c in limited) {
      await _plugin.zonedSchedule(
        id: c.id,
        title: c.title,
        body: c.body,
        scheduledDate: c.when,
        notificationDetails:
            const NotificationDetails(iOS: DarwinNotificationDetails()),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  Future<void> showActivityNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!Platform.isIOS) return;
    await init();
    // WICHTIG: presentBanner/presentList/presentSound MÜSSEN explizit
    // gesetzt sein, sonst zeigt iOS Foreground-Banner für `_plugin.show()`
    // gar nicht. Bei `zonedSchedule` ist das anders (System-managed),
    // deshalb funktionieren Due-Date-Reminders aber Activity-Notifs nicht
    // ohne diese Flags.
    await _plugin.show(
      id: id,
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
  }

  List<int> _idsForCard(int cardId) => [
        cardId * 10 + 1,
        cardId * 10 + 2,
        cardId * 10 + 3,
      ];

  List<_DueCandidate> _buildCandidates(
    List<CardItem> cards, {
    required List<Duration> offsets,
    required bool includeOverdue,
    required String? localeCode,
  }) {
    final now = DateTime.now();
    final resolvedLocale = _resolveLocaleCode(localeCode);
    final l10n = L10n(Locale(resolvedLocale));
    final out = <_DueCandidate>[];
    final seen = <int>{};
    for (final card in cards) {
      if (!seen.add(card.id)) continue;
      if (card.due == null || card.done != null) continue;
      final due = card.due!;
      if (offsets.isNotEmpty) {
        for (final offset in offsets) {
          final scheduled = due.subtract(offset);
          if (!scheduled.isAfter(now)) continue;
          final title = l10n.dueReminderTitle(_labelForOffset(l10n, offset));
          out.add(_DueCandidate(
            id: _idForOffset(card.id, offset),
            title: title,
            body: card.title,
            when: tz.TZDateTime.from(scheduled, tz.local),
          ));
        }
      }
      if (includeOverdue && due.isAfter(now)) {
        final overdueAt = due.add(const Duration(minutes: 5));
        out.add(_DueCandidate(
          id: card.id * 10 + 3,
          title: l10n.overdueReminderTitle,
          body: card.title,
          when: tz.TZDateTime.from(overdueAt, tz.local),
        ));
      }
    }
    return out;
  }

  int _idForOffset(int cardId, Duration offset) {
    final minutes = offset.inMinutes;
    if (minutes == 60) return cardId * 10 + 1;
    if (minutes == 1440) return cardId * 10 + 2;
    return cardId * 10 + 1;
  }

  String _labelForOffset(L10n l10n, Duration offset) {
    final minutes = offset.inMinutes;
    if (minutes == 60) return l10n.reminderIn1Hour;
    if (minutes == 1440) return l10n.reminderIn1Day;
    return l10n.reminderIn1Hour;
  }

  String _resolveLocaleCode(String? localeCode) {
    var code = localeCode?.toLowerCase().trim();
    if (code == null || code.isEmpty) {
      code = WidgetsBinding.instance.platformDispatcher.locale.languageCode
          .toLowerCase();
    }
    if (code == 'de' || code == 'es' || code == 'en') return code;
    return 'en';
  }
}

class _DueCandidate {
  final int id;
  final String title;
  final String body;
  final tz.TZDateTime when;
  const _DueCandidate({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
  });
}
