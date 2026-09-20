/// Bereitet eine Kartenbeschreibung für die kompakte Kachel-Vorschau auf
/// (Board- und Anstehend-Karten): `<details>`-Blöcke werden komplett
/// ausgeklammert — sie sind zugeklappter Zusatzinhalt und würden in der
/// Vorschau nur als rohes Markup erscheinen. Verschachtelte Blöcke werden
/// von innen nach außen aufgelöst, unvollständiges Markup (fehlendes
/// `</details>`) wird ab dem öffnenden Tag gekappt, einzelne Rest-Tags
/// werden entfernt. Liefert null, wenn danach nichts Anzeigbares übrig
/// bleibt — die Kachel zeigt dann keine Text-Vorschau (das
/// Beschreibungs-Icon in der Meta-Zeile bleibt davon unberührt).
String? descriptionPreview(String? description) {
  final raw = description;
  if (raw == null || raw.trim().isEmpty) return null;
  var s = raw;
  // Innerste Blöcke iterativ entfernen — löst Verschachtelung auf.
  final block = RegExp(r'<details\b[^>]*>(?:(?!<details\b).)*?</details\s*>',
      caseSensitive: false, dotAll: true);
  String prev;
  do {
    prev = s;
    s = s.replaceAll(block, '');
  } while (s != prev);
  // Unvollständiger Block ohne schließendes Tag: ab <details bis Ende weg.
  s = s.replaceFirst(
      RegExp(r'<details\b[^>]*>.*$', caseSensitive: false, dotAll: true), '');
  // Einzelne stehen gebliebene Tags.
  s = s.replaceAll(
      RegExp(r'</?(details|summary)\b[^>]*>', caseSensitive: false), '');
  s = s.trim();
  return s.isEmpty ? null : s;
}
