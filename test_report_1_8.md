# Nextdeck 1.8 — Manueller Testbericht (iPhone 16e, iOS 26.3)

Stand: 2026-05-03
Tester: Claude (Cowork) auf Holgers Simulator
Build: uncommitteter Working Tree, `pubspec.yaml` 1.8.0+8
Testboard: `Summperparty` (id 31, NC 33 auf nc.heidkamp.dev)
Scope: Kernflows + Sync/Offline, gemäß `tasks_1_8.md`

Legende: ✅ ok · ⚠️ Auffälligkeit · ❌ Fehler · ⏳ noch offen

## Issue-Mapping

| Issue | Beschreibung | Status |
|---|---|---|
| #67 | Datei-Anhänge hochladen | ⏳ (Lesen ✅) |
| #62 | Board löschen | ✅ UI vorhanden |
| #63 | Listen umbenennen | ✅ UI vorhanden |
| #58 | Karten-Reihenfolge stabil | ⏳ |
| #50 | Markdown-Links klickbar | ⏳ |
| #61 | MP3-Anhänge öffnen | ⏳ |
| #53 | Markdown-Toolbar Bullet/Task | ⏳ |
| #54 | Per-Board manueller Sync-Intervall | ⏳ |
| #55 | Lokale Notifications | ⏳ |
| #65/66 | Status-Chips Layout (eher Tablet) | n/a auf iPhone |

## Befunde

### App-Start
✅ Build aus Working Tree läuft, App startet auf iPhone 16e ohne Fehler.
✅ Login auf nc.heidkamp.dev erfolgreich (durch Holger).
✅ `[refreshBoards] server returned boards (12)` — Board-Liste wird geladen.

### Board-Übersicht (Stack-View)
✅ Board `Summperparty` öffnet, Stack `Backlog` sichtbar mit einer Karte `Soundcheck`.
✅ Stack-Header zeigt Pfeil nach rechts → wahrscheinlich Stack-Navigation.
✅ Bottom-Tabs: Anstehend / Board / Übersicht / Einstellungen — alle gerendert.

### Card-Detail (Soundcheck)
✅ Card-Detail öffnet beim Tap.
✅ Markdown-Toolbar mit Buttons B / I / S / ` / Link / Bullet / Task — **#53 UI vorhanden**.
✅ Felder: Status-Toggle, Beschreibung, Fälligkeit, Liste, Schlagworte, Zugewiesen, Anhänge, Kommentare.
✅ Bestehender Anhang `photo_2026-01-20_20-58-18.jpg` (2.5 MB) wird gelistet.
✅ Bestehender Kommentar (Holger, 2025-10-12: "Total wichtig!") mit Antworten/Löschen-Buttons.
✅ Kommentar-Eingabefeld mit Senden-Button vorhanden.

### Anhang-Anzeige (#67 Lesen)
✅ Tap auf Anhang öffnet `AttachmentPreviewPage`.
✅ Bild wird gerendert.
✅ Backend-Call: `WebDAV /remote.php/dav/files/holger/Deck/photo_... -> 200 in 1567ms`.
⚠️ Layout: Hochformat-Foto wird zentriert dargestellt mit auffällig viel Whitespace oben/unten — kein Bug, aber Pixel-Effizienz schlecht. Könnte mit `BoxFit.contain` und Hintergrund-Color verbessert werden.

### Board-Aktionen-Menü (Hamburger oben rechts)
✅ Menü öffnet zuverlässig.
Einträge: Aktualisieren · Liste auswählen · Suchen · Archivierte Karten anzeigen · Neue Liste · **Liste umbenennen** (#63) · Listen sortieren · Board-Farbe ändern · **Board löschen** (rot, #62) · Abbrechen.
✅ #62 — Board löschen vorhanden, durch rote Farbe als destruktiv erkennbar (NICHT auf Testboard ausgeführt).
✅ #63 — Liste umbenennen als eigener Menüpunkt vorhanden.
✅ Bestätigt aus Code: `app_state.dart` enthält Board-Delete-Cache-Cleanup laut `tasks_1_8.md`.

### Bekannte Test-Limitierung
⚠️ Tippen via Computer-use-Tool wird im iOS-Simulator als Long-Press interpretiert — Akzent-Picker geht auf, restliche Tasten gehen verloren. Tipp-abhängige Tests (Karte anlegen mit Titel, Beschreibung mit Markdown-Link, Kommentar schreiben) müssen entweder von Holger getippt werden oder mit Software-Keyboard pro Buchstabe geklickt werden.

(weitere Befunde folgen)
