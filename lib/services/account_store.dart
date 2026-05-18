import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/account.dart';

/// Persistente Verwaltung der bekannten Nextcloud-Accounts.
///
/// Daten liegen in [FlutterSecureStorage]:
/// * `accounts_v1`             — JSON-Liste aller Accounts (ohne Passwort)
/// * `active_account_id`       — ID des aktuell aktiven Accounts
/// * `aggregation_mode`        — `1` = alle Accounts gleichzeitig anzeigen
/// * `password_{accountId}`    — Passwort/App-Password pro Account
///
/// Plus einmalige Migration: wenn die App vor 1.9 noch Single-Account-Keys
/// (`baseUrl`, `username`, `password`) hat, werden die in einen neuen
/// Default-Account umgezogen, die alten Keys bleiben als Backup bestehen
/// und werden erst in einer späteren Version entfernt.
class AccountStore {
  static const String _kAccountsKey = 'accounts_v1';
  static const String _kActiveAccountIdKey = 'active_account_id';
  static const String _kAggregationModeKey = 'aggregation_mode';
  static const String _kMigrationDoneKey = 'multiaccount_migrated_v1';

  final FlutterSecureStorage storage;
  const AccountStore(this.storage);

  // ---- Account list ---------------------------------------------------------

  Future<List<Account>> loadAll() async {
    final raw = await storage.read(key: _kAccountsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final accounts = <Account>[];
      for (final item in list) {
        if (item is Map) {
          try {
            accounts.add(Account.fromJson(item.cast<String, dynamic>()));
          } catch (e) {
            debugPrint('[account-store] skip invalid account: $e');
          }
        }
      }
      return accounts;
    } catch (e) {
      debugPrint('[account-store] loadAll failed: $e');
      return const [];
    }
  }

  Future<void> saveAll(List<Account> accounts) async {
    final raw = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await storage.write(key: _kAccountsKey, value: raw);
  }

  Future<void> addOrUpdate(Account account) async {
    final list = await loadAll();
    final idx = list.indexWhere((a) => a.id == account.id);
    if (idx >= 0) {
      list[idx] = account;
    } else {
      list.add(account);
    }
    await saveAll(list);
  }

  Future<void> remove(String accountId) async {
    final list = await loadAll();
    list.removeWhere((a) => a.id == accountId);
    await saveAll(list);
    await deletePassword(accountId);
    // Active-Account ggf. zurücksetzen
    final active = await readActiveAccountId();
    if (active == accountId) {
      await setActiveAccountId(list.isNotEmpty ? list.first.id : null);
    }
  }

  // ---- Active account / aggregation ----------------------------------------

  Future<String?> readActiveAccountId() {
    return storage.read(key: _kActiveAccountIdKey);
  }

  Future<void> setActiveAccountId(String? id) async {
    if (id == null) {
      await storage.delete(key: _kActiveAccountIdKey);
    } else {
      await storage.write(key: _kActiveAccountIdKey, value: id);
    }
  }

  Future<bool> isAggregationMode() async {
    return (await storage.read(key: _kAggregationModeKey)) == '1';
  }

  Future<void> setAggregationMode(bool enabled) async {
    await storage.write(
        key: _kAggregationModeKey, value: enabled ? '1' : '0');
  }

  // ---- Passwords ------------------------------------------------------------

  Future<void> savePassword(String accountId, String password) {
    return storage.write(key: 'password_$accountId', value: password);
  }

  Future<String?> readPassword(String accountId) {
    return storage.read(key: 'password_$accountId');
  }

  Future<void> deletePassword(String accountId) {
    return storage.delete(key: 'password_$accountId');
  }

  // ---- Migration ------------------------------------------------------------

  /// Einmalige Migration: vor 1.9 lag der Login als
  /// `baseUrl` / `username` / `password` direkt in der Secure Storage.
  /// Diese Methode erkennt das und legt einen neuen Default-Account an.
  ///
  /// Returnt den migrierten Account (oder einen existierenden), oder
  /// `null` wenn nichts zu migrieren war.
  Future<Account?> migrateLegacyIfNeeded() async {
    final done = await storage.read(key: _kMigrationDoneKey);
    if (done == '1') {
      // Schon migriert — aber falls noch keine Accounts da sind, prüfen.
      final list = await loadAll();
      if (list.isNotEmpty) return null;
    }

    final legacyBase = await storage.read(key: 'baseUrl');
    final legacyUser = await storage.read(key: 'username');
    final legacyPass = await storage.read(key: 'password');

    if (legacyBase == null ||
        legacyBase.isEmpty ||
        legacyUser == null ||
        legacyUser.isEmpty) {
      await storage.write(key: _kMigrationDoneKey, value: '1');
      return null;
    }

    // Falls schon Accounts existieren, nicht duplizieren.
    final existing = await loadAll();
    if (existing.any((a) =>
        a.baseUrl == legacyBase && a.username == legacyUser)) {
      await storage.write(key: _kMigrationDoneKey, value: '1');
      return existing.firstWhere(
          (a) => a.baseUrl == legacyBase && a.username == legacyUser);
    }

    final account = Account(
      id: _generateId(),
      baseUrl: legacyBase,
      username: legacyUser,
      shortName: _deriveShortName(legacyBase),
      color: 0xFF1E88E5,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await addOrUpdate(account);
    if (legacyPass != null && legacyPass.isNotEmpty) {
      await savePassword(account.id, legacyPass);
    }
    await setActiveAccountId(account.id);
    await storage.write(key: _kMigrationDoneKey, value: '1');
    debugPrint('[account-store] migrated legacy login → ${account.id}');
    return account;
  }

  // ---- Helpers --------------------------------------------------------------

  String _generateId() {
    final r = math.Random.secure();
    return List.generate(
        8, (_) => r.nextInt(0x100).toRadixString(16).padLeft(2, '0')).join();
  }

  static String _deriveShortName(String baseUrl) {
    var s = baseUrl.trim();
    s = s.replaceAll(RegExp(r'^https?://'), '');
    s = s.replaceAll(RegExp(r'/.*$'), '');
    final parts = s.split('.');
    if (parts.length >= 2) return parts[parts.length - 2];
    return s.isEmpty ? 'Server' : s;
  }

  /// Public Variant — UI nutzt das beim Anlegen eines neuen Accounts,
  /// damit der Default-Kurzname konsistent zur Migration ist.
  static String deriveShortName(String baseUrl) => _deriveShortName(baseUrl);

  /// Public Variant — UI/State nutzt das beim Erstellen eines Accounts.
  String generateId() => _generateId();
}
