import 'label.dart';
import 'user_ref.dart';

class CardItem {
  final int id;
  final String title;
  final String? description;
  final DateTime? due;
  final List<Label> labels;
  final List<UserRef> assignees;
  final int? order;

  const CardItem({required this.id, required this.title, this.description, this.due, this.labels = const [], this.assignees = const [], this.order});

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

    return CardItem(
      id: json['id'] as int,
      title: (json['title'] ?? json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      due: due,
      labels: labels,
      assignees: assignees,
      order: (json['order'] is num) ? (json['order'] as num).toInt() : (json['position'] is num ? (json['position'] as num).toInt() : null),
    );
  }
}
