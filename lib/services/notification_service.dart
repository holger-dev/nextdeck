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

  Future<void> init({bool requestPermissions = false}) async {
    if (!Platform.isIOS) return;
    if (!_tzInitialized) {
      tz.initializeTimeZones();
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        tz.setLocalLocation(tz.UTC);
      }
      _tzInitialized = true;
    }
    if (!_initialized) {
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(iOS: ios);
      await _plugin.initialize(settings);
      _initialized = true;
    }
    if (requestPermissions) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
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
      await _plugin.cancel(id);
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
        c.id,
        c.title,
        c.body,
        c.when,
        const NotificationDetails(iOS: DarwinNotificationDetails()),
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
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
    final limited =
        candidates.length <= maxScheduled ? candidates : candidates.sublist(0, maxScheduled);
    for (final c in limited) {
      await _plugin.zonedSchedule(
        c.id,
        c.title,
        c.body,
        c.when,
        const NotificationDetails(iOS: DarwinNotificationDetails()),
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
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
    final l10n = L10n(Locale(localeCode ?? 'en'));
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
