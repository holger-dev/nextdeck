import 'label.dart';
import 'user_ref.dart';

class CardItem {
  final int id;
  final String title;
  final String? description;
  final DateTime? due;
  final DateTime? done;
  final bool archived;
  final List<Label> labels;
  final List<UserRef> assignees;
  final int? order;
  /// Server-Stempel (Unix-Sekunden) für Optimistic-Concurrency-Detection.
  /// Wird genutzt, um beim Save zu erkennen, ob ein anderer Editor die
  /// Karte zwischenzeitlich verändert hat.
  final int? lastModified;
  /// Letzter Editor laut Server (z.B. "freddie"). Optional.
  final String? lastEditor;

  const CardItem({required this.id, required this.title, this.description, this.due, this.done, this.archived = false, this.labels = const [], this.assignees = const [], this.order, this.lastModified, this.lastEditor});

  factory CardItem.fromJson(Map<String, dynamic> json) {
    DateTime? due;
    final rawDue = json['duedate'] ?? json['due'] ?? json['duedateAt'] ?? json['duedateTimestamp'];
    if (rawDue != null) {
      if (rawDue is int) {
        // Some APIs return unix timestamp (seconds or milliseconds)
        final ts = rawDue > 100000000000 ? rawDue ~/ 1000 : rawDue;
        due = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toLocal();
      } else {
        var s = rawDue.toString().trim();
        // Normalize common non-ISO formats from Deck servers
        if (!s.contains('T') && s.contains(' ')) {
          s = s.replaceFirst(' ', 'T');
        }
        final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
        if (dateOnly.hasMatch(s)) {
          s = s + 'T00:00:00';
        }
        due = DateTime.tryParse(s)?.toLocal();
      }
    }
    DateTime? done;
    final rawDone = json['done'] ?? json['doneDate'] ?? json['doneAt'];
    if (rawDone != null) {
      if (rawDone is bool) {
        if (rawDone) {
          done = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
        }
      } else if (rawDone is int) {
        final ts = rawDone > 100000000000 ? rawDone ~/ 1000 : rawDone;
        done = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toLocal();
      } else if (rawDone is String) {
        var s = rawDone.trim();
        final lower = s.toLowerCase();
        if (lower == 'true' || lower == '1') {
          done = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
        } else if (s.isNotEmpty && lower != 'false' && lower != '0') {
          if (!s.contains('T') && s.contains(' ')) {
            s = s.replaceFirst(' ', 'T');
          }
          final dateOnly = RegExp(r'^\\d{4}-\\d{2}-\\d{2}$');
          if (dateOnly.hasMatch(s)) {
            s = s + 'T00:00:00';
          }
          done = DateTime.tryParse(s)?.toLocal();
        }
      }
    }
    final archivedRaw = json['archived'] ?? json['isArchived'] ?? json['archivedAt'] ?? json['archived_at'];
    final archived = archivedRaw is bool
        ? archivedRaw
            : (archivedRaw is num
                ? archivedRaw != 0
                : (archivedRaw is String
                    ? (() {
                    final s = (archivedRaw as String).trim().toLowerCase();
                    if (s.isEmpty || s == 'false' || s == '0') return false;
                    return true;
                  })()
                : false));

    List<Label> labels = const [];
    final rawLabels = json['labels'] ?? json['label'];
    if (rawLabels is List) {
      labels = rawLabels
          .whereType<Map>()
          .map((e) => Label.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    // Assignees variants: 'assignedUsers', 'assigned', 'members'; entries may have nested 'participant'
    final List<UserRef> assignees = () {
      final raw = json['assignedUsers'] ?? json['assigned'] ?? json['members'];
      if (raw is List) {
        final out = <UserRef>[];
        for (final item in raw) {
          if (item is Map) {
            final map = item.cast<String, dynamic>();
            final participant = map['participant'];
            if (participant is Map) {
              out.add(UserRef.fromJson(participant.cast<String, dynamic>()));
            } else if (participant is String || participant is num) {
              final id = participant.toString();
              out.add(UserRef(id: id, displayName: id));
            } else {
              out.add(UserRef.fromJson(map));
            }
          } else if (item is String || item is num) {
            final id = item.toString();
            out.add(UserRef(id: id, displayName: id));
          }
        }
        return out;
      }
      return const <UserRef>[];
    }();

    int? lastModified;
    final rawLm = json['lastModified'] ?? json['last_modified'] ?? json['lastModifiedAt'];
    if (rawLm is int) {
      // Unix-Sekunden oder ms — normalisieren auf Sekunden.
      lastModified = rawLm > 100000000000 ? rawLm ~/ 1000 : rawLm;
    } else if (rawLm is String) {
      final parsed = int.tryParse(rawLm.trim());
      if (parsed != null) {
        lastModified = parsed > 100000000000 ? parsed ~/ 1000 : parsed;
      }
    }

    final lastEditor = (json['lastEditor'] ?? json['lastEditorDisplayName'] ?? json['lastEditorUid'])?.toString();

    return CardItem(
      id: json['id'] as int,
      title: (json['title'] ?? json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      due: due,
      done: done,
      archived: archived,
      labels: labels,
      assignees: assignees,
      order: (json['order'] is num) ? (json['order'] as num).toInt() : (json['position'] is num ? (json['position'] as num).toInt() : null),
      lastModified: lastModified,
      lastEditor: lastEditor,
    );
  }
}
