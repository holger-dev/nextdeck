# Nextdeck offene Issues - konsolidiert + Prioritaet

Quelle: https://github.com/holger-dev/nextdeck/issues
Hinweis: Issue #8 (Transifex) wurde auf Wunsch entfernt.

## Prioritaetsliste (hoch -> niedrig)
P0
- Datenkonsistenz Anstehend + Assigned-Filter (Issues #27, #32)
- "Mark as done" setzt kein doneDate (Issue #24)

P1
- PDF-Attachments auf iOS oeffnen (Issue #36)
- Assignee-User fehlen in iOS Dropdown (Issue #37)
- Mentions in Kommentaren inkl. Benachrichtigungen (Issues #45, #28)
- Due-Date/Overdue Notifications (Issues #39, #9)

P2
- Photo Library Upload fuer Attachments (Issue #38)
- Task-Completion Count auf Karten (Issue #43)
- Owner-Kuerzel in Kartenuebersicht (Issue #44)
- Archiv-Filter (Issue #4)

P3
- macOS Text-Replacements / Quick Action (Issue #42)
- Kartenfarbe konfigurierbar (Issue #30)
- Hintergrundband zwischen Spalten (Issue #29)
- Logo verbessern (Issue #35)
- Board anlegen (Issue #6)
- Liste/Spalte anlegen (Issue #5)
- Multi-Account Management (Issue #17)

P4
- Home-Screen Widget (Issue #41)
- Voice Input (Speech-to-Text) (Issue #40)

## Konsolidierte Tasks

## Task A — Anstehend-Ansicht korrekt + Assigned-Filter (Done)
Zuordnung
- Issues #27, #32

Ziel
- "Anstehend" zeigt nur relevante Karten und bietet Filter "Assigned" (mir zugewiesen).

Scope
- Abgleich der Filterlogik mit Web-UI.
- UI-Filter fuer Assigned (Toggle/Option).
- Query/Filter und Cache/Permissions pruefen.

Akzeptanzkriterien
- App-Ansicht entspricht Web-Ansicht fuer denselben User.
- Filter "Assigned" zeigt nur zugewiesene Karten.
- Keine Karten ohne Verantwortlichkeit sichtbar.

Tests/Checks
- Web-UI vs App: gleiche Kartenanzahl und Titel fuer gleichen User/Board.
- Filter "Assigned" an/aus pruefen, nur zugewiesene Karten sichtbar.
- Karten in freigegebenen Boards ohne Assignee werden nicht angezeigt.

Blocker/Unklar
- Definition "assigned" (Owner vs Assignee vs Member).
- Repro-Board und Referenz-Screenshots aus Web-UI.

## Task B — Done-Status konsistent (doneDate)
Zuordnung
- Issue #24

Ziel
- App setzt doneDate wie die Web-UI (gruenes Haeckchen).

Analyse / Ablauf (aus Nextcloud Deck)
- API v1.x hat keinen dedizierten done/undone Endpoint.
- Der Web-Client nutzt `PUT /apps/deck/cards/{cardId}/done` (non-API, vermutlich CSRF-geschuetzt).
- API-Update akzeptiert `done` im Payload und setzt doneDate, aber ohne die Side-Effects von `done()`.
- Wichtig: `CardService::update()` setzt `done = null`, wenn das Feld nicht gesendet wird.

Umsetzung (Option 1 - realistisch)
- `done` Feld in App-Model/Cache aufnehmen (z. B. `CardItem`).
- Beim Update immer `done` mitsenden (sonst wird es geloescht).
- Beim "Mark as done" `done` auf ISO-Timestamp setzen (z. B. `DateTime.now().toUtc().toIso8601String()`).
- Beim "Mark as undone" `done` explizit auf `null` setzen.

Scope
- API-Call fuer doneDate setzen.
- UI-Status angleichen (Done-Liste vs. doneDate).

Akzeptanzkriterien
- doneDate gesetzt, sobald "Mark as done" in App.
- Web-UI zeigt done-Status fuer App-Updates.

Tests/Checks
- Karte in App als done markieren -> Web-UI zeigt gruene Done-Markierung.
- Danach Titel/Beschreibung aendern -> done bleibt gesetzt.
- "Mark as undone" -> done ist null in API und Web-UI.

Blocker/Unklar
- Bestaetigen, welches done-Format die API erwartet (ISO-String vs bool).

## Task C — iOS Attachment-PDF oeffnen
Zuordnung
- Issue #36

Ziel
- PDF-Attachments auf iOS lassen sich oeffnen/previewen.

Scope
- Download/Preview-Pipeline pruefen.
- MIME-Type/UTType Handling.

Akzeptanzkriterien
- PDF oeffnet sich in iOS (QuickLook o. a.).
- Keine Regression fuer andere Attachment-Typen.

Tests/Checks
- PDF am Desktop anhaengen -> in iOS oeffnen und anzeigen.
- "Teilen"/"In ... oeffnen" funktioniert.

Blocker/Unklar
- Beispiel-PDF und iOS Testgeraet benoetigt.

## Task D — Assignee User-Liste auf iOS korrekt
Zuordnung
- Issue #37

Ziel
- Alle berechtigten User erscheinen im iOS Assignee-Dropdown.

Scope
- User-Liste fuer Assignments laden.
- API-Filter/Permissions auf iOS checken.

Akzeptanzkriterien
- Vollstaendige User-Liste, korrekte Zuweisung.

Tests/Checks
- iOS Dropdown zeigt gleiche Nutzer wie Android/Web fuer dasselbe Board.
- Zuweisung an betroffenen User funktioniert.

Blocker/Unklar
- Konkrete Repro-Daten (Board, Rolle, User-ID) fehlen.
- API-Response fuer Members/Assignments benoetigt.

## Task E — Mentions in Kommentaren
Zuordnung
- Issues #45, #28

Ziel
- @-Mentions funktionieren wie in Nextcloud (Autocomplete + Notifications).

Scope
- Autocomplete fuer @.
- Speicherung im korrekten Mention-Format.
- Darstellung in Kommentaren.

Akzeptanzkriterien
- Mentions triggern Nextcloud Notifications.
- Mentions sind sichtbar/markiert.

Tests/Checks
- @Tippen zeigt User-Liste, Einfuegen setzt korrektes Format.
- Erwaehnter User bekommt Nextcloud-Notification.
- Web-UI zeigt die Mention korrekt.

Blocker/Unklar
- Genaues Mention-Format und User-Search API fehlen.

## Task F — Due-Date/Overdue Notifications
Zuordnung
- Issues #39, #9

Ziel
- Erinnerungen vor/bei/nach Due-Date, inkl. Overdue.

Scope
- Lokale Notifications auf Basis Sync-Daten.
- Konfiguration der Reminder-Intervalle.

Akzeptanzkriterien
- Notifications fuer Due/Overdue, opt-in und deaktivierbar.
- Keine Notifications ohne Due-Date.

Tests/Checks
- Reminder X Stunden/Tag vor Due-Date erscheint.
- Overdue-Notification erscheint nach Ablauf.
- Deaktivieren stoppt alle Notifications.
- Aenderung der Due-Date aktualisiert Schedule.

Blocker/Unklar
- Festlegen der Reminder-Intervalle und Plattform-Scope.
- Entscheidung local-only vs server-driven.

## Task G — Photo Library Upload
Zuordnung
- Issue #38

Ziel
- Fotos direkt aus der Galerie an Karten anhaengen.

Scope
- Photo Picker iOS/Android.
- Upload ueber bestehende Attachment-Pipeline.

Akzeptanzkriterien
- Foto erscheint als Attachment und ist oeffnbar.

Tests/Checks
- Foto aus Library auswaehlen -> Upload -> in Liste sichtbar.
- Oeffnen/Teilen funktioniert.
- Permissions-Flow (limited access) funktioniert.

Blocker/Unklar
- Auswahl des Plugins (image_picker/PHPicker) und Multi-Select.

## Task H — Task-Completion Count auf Karten
Zuordnung
- Issue #43

Ziel
- Anzeige erledigt/gesamt (z. B. 2/5) auf Karten.

Scope
- Parsing der Checklist im Beschreibungstext.
- Anzeige als Meta-Badge.

Akzeptanzkriterien
- Korrekte Zaehler, nur wenn Tasks vorhanden.

Tests/Checks
- Beschreibung mit - [ ] und - [x] -> korrektes 1/2.
- Toggle einzelner Tasks -> Zaehler aktualisiert.
- Ohne Tasks -> kein Badge.

Blocker/Unklar
- Genaue Parsing-Regeln (nur "- [ ]" oder auch "* [ ]").

## Task I — Owner-Kuerzel in Uebersicht
Zuordnung
- Issue #44

Ziel
- Owner/Assignee in der Kartenuebersicht anzeigen.

Scope
- UI-Element + Datenfeld aus Deck API.

Akzeptanzkriterien
- Owner-Kuerzel pro Karte sichtbar, Fallback bei leer.

Tests/Checks
- Karte mit Owner/Assignee zeigt Kuerzel/Name.
- Karte ohne Owner zeigt leeren Placeholder.

Blocker/Unklar
- Welches Feld ist die Web-UI-Entsprechung (owner vs assignedUsers).

## Task J — Archiv-Filter
Zuordnung
- Issue #4

Ziel
- Archivierte Karten anzeigen koennen.

Scope
- Filter/Toggle + API-Parameter fuer archived.

Akzeptanzkriterien
- Archiv-Ansicht zeigt nur archivierte Karten.

Tests/Checks
- Archiv-Filter an -> nur archivierte Karten.
- Archiv-Filter aus -> nur aktive Karten.

Blocker/Unklar
- API-Parameter fuer archived Cards muessen bestaetigt werden.

## Task K — macOS Text-Replacements / Quick Action
Zuordnung
- Issue #42

Ziel
- Schnellere Task-Erstellung via System-Replacements oder In-App Aktion.

Scope
- NSTextInput/Text Substitutions pruefen.
- Optional: "Mark line as task" Aktion.

Akzeptanzkriterien
- Replacements funktionieren ODER schnelle Alternative vorhanden.

Tests/Checks
- macOS Text-Replacement "ttd" -> Expand in Beschreibung.
- Wenn nicht moeglich: Toolbar-Aktion erzeugt "- [ ]".

Blocker/Unklar
- Entscheidung: System-Fix vs Quick-Action als Standard.

## Task L — Kartenfarbe konfigurieren
Zuordnung
- Issue #30

Ziel
- Kartenfarbe nicht nur vom ersten Tag ableiten.

Scope
- Einstellung fuer Farbregel (an/aus/konfigurierbar).

Akzeptanzkriterien
- Farbregel ist steuerbar, keine Regression.

Tests/Checks
- Farbregel aus -> Karten ohne Tag-Farbe.
- Farbregel an -> wie bisher.

Blocker/Unklar
- UX-Entscheidung: global, pro Board oder pro Karte?

## Task M — Hintergrundband zwischen Spalten
Zuordnung
- Issue #29

Ziel
- Stoerendes Band reduzieren/entfernen.

Scope
- UI/CSS Anpassung, Theme-Einfluss pruefen.

Akzeptanzkriterien
- Band ist weg oder deutlich reduziert.

Tests/Checks
- Board mit Theme-Farbe zeigt kein stoerendes Band.
- Layout/Abstaende bleiben stabil.

Blocker/Unklar
- Quelle der Farbe: App-Style oder Nextcloud Theme?

## Task N — App-Logo verbessern
Zuordnung
- Issue #35

Ziel
- Neues, eindeutiges Icon.

Scope
- Design abstimmen, Assets fuer alle Plattformen.

Akzeptanzkriterien
- Neue Icons integriert (iOS/Android/macOS).

Tests/Checks
- Build zeigt neues Icon in App/Launcher.

Blocker/Unklar
- Design-Assets fehlen, externe Abstimmung erforderlich.

## Task O — Board anlegen
Zuordnung
- Issue #6

Ziel
- Board-Erstellung in der App ermoeglichen.

Scope
- UI-Action + Deck API.

Akzeptanzkriterien
- Board wird erstellt und angezeigt.

Tests/Checks
- Neues Board erscheint in Board-Liste.
- Fehleranzeige bei fehlenden Rechten.

Blocker/Unklar
- API-Endpoint/Permissions fuer Board-Create bestaetigen.

## Task P — Liste/Spalte anlegen
Zuordnung
- Issue #5

Ziel
- Spalten-Erstellung in Board-Ansicht.

Scope
- UI-Action + Deck API.

Akzeptanzkriterien
- Spalte wird erstellt und angezeigt.

Tests/Checks
- Neue Spalte erscheint sofort.
- Rechtemodell greift (Fehleranzeige ohne Rechte).

Blocker/Unklar
- API-Endpoint/Permissions fuer Stack-Create bestaetigen.

## Task Q — Multi-Account Management
Zuordnung
- Issue #17

Ziel
- Mehrere Nextcloud Accounts verwalten.

Scope
- Add/Switch/Remove UI, getrennte Sessions.

Akzeptanzkriterien
- Kein Daten-Leak zwischen Accounts.

Tests/Checks
- Zwei Accounts anlegen, switchen, Daten getrennt.
- Logout eines Accounts entfernt nur dessen Daten.

Blocker/Unklar
- Gewuenschter Workflow (parallel vs switch) nicht definiert.

## Task R — Home-Screen Widget
Zuordnung
- Issue #41

Ziel
- Quick Add + Overviews ohne App-Start.

Scope
- Widget (Small/Medium), Konfiguration, Caching.

Akzeptanzkriterien
- Widget laedt schnell und oeffnet korrekten Kontext.

Tests/Checks
- Widget zeigt Kartenliste und aktualisiert sich.
- Tap auf Quick Add oeffnet Create-Flow.

Blocker/Unklar
- Plattform-Scope (iOS only vs Android parallel) offen.

## Task S — Voice Input (Speech-to-Text)
Zuordnung
- Issue #40

Ziel
- Diktat fuer Titel/Beschreibung.

Scope
- System-Diktat per Mic-Icon.

Akzeptanzkriterien
- Gesprochenes wird als Text eingefuegt.

Tests/Checks
- Mic starten -> Text erscheint im Feld.
- Permission denied -> klare Fehlermeldung.

Blocker/Unklar
- Auswahl der Speech-API pro Plattform.
