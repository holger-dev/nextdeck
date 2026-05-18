/// Repräsentiert eine Nextcloud-Instanz, mit der die App verbunden ist.
///
/// Multi-Account-Support seit 1.9: die App kennt mehrere Accounts
/// gleichzeitig und switcht zwischen ihnen (oder zeigt sie aggregiert).
///
/// IDs sind stabile 16-Zeichen-Hex-Strings, generiert beim Anlegen.
/// Sie tauchen als Prefix in Hive-Cache-Keys auf (`{id}__columns_{boardId}`),
/// um Cross-Account-Daten-Lecks zu vermeiden.
class Account {
  /// Stabile ID — wird beim Anlegen einmal generiert und bleibt.
  final String id;

  /// Server-URL ohne Scheme (z. B. `nc.heidkamp.dev` oder `nc.example.com/cloud`).
  final String baseUrl;

  /// Login-User (Nextcloud-User-ID, nicht Display-Name).
  final String username;

  /// Anzeige-Name vom Server (optional, wird beim ersten Login befüllt).
  final String? displayName;

  /// Vom User wählbarer Kurzname für die Aggregations-Ansicht
  /// (z. B. `Privat`, `Schule`, `Büro`). Default = abgeleitet aus baseUrl.
  /// Erscheint in der Aggregations-Ansicht als `[Kurzname]`-Prefix.
  final String shortName;

  /// Akzentfarbe für UI-Indikator (Avatar-Icon, Aggregations-Chip).
  /// ARGB-Integer.
  final int color;

  /// Zeitstempel des Anlegens (Unix-ms).
  final int createdAt;

  const Account({
    required this.id,
    required this.baseUrl,
    required this.username,
    this.displayName,
    required this.shortName,
    required this.color,
    required this.createdAt,
  });

  Account copyWith({
    String? baseUrl,
    String? username,
    String? displayName,
    String? shortName,
    int? color,
  }) {
    return Account(
      id: id,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      shortName: shortName ?? this.shortName,
      color: color ?? this.color,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'baseUrl': baseUrl,
        'username': username,
        if (displayName != null) 'displayName': displayName,
        'shortName': shortName,
        'color': color,
        'createdAt': createdAt,
      };

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String,
      baseUrl: json['baseUrl'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String?,
      shortName: json['shortName'] as String? ?? (json['baseUrl'] as String),
      color: (json['color'] as num?)?.toInt() ?? 0xFF1E88E5,
      createdAt:
          (json['createdAt'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Anzeige-Label für UI-Listen — Display-Name wenn vorhanden, sonst
  /// Username `@` Host.
  String get label {
    final host = baseUrl
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/.*$'), '');
    if (displayName != null && displayName!.isNotEmpty) {
      return '$displayName · $host';
    }
    return '$username · $host';
  }
}
