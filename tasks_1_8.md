# Nextdeck 1.8 - Aufgaben

Stand: 2026-04-15

Priorisierung: Erst offene GitHub-Issues mit Label `bug`, danach `enhancement`. Bestehende Release-/SDK-Pflichten bleiben ebenfalls relevant.

## Release-Pflichten

### Update auf Xcode 26

Status: Offen. Xcode-/SDK-Upgrade muss auf der Build-Maschine mit installiertem Xcode 26 final verifiziert werden.

Die gesamte App muss auf das aktuelle SDK aktualisiert werden:

90725: SDK version issue. This app was built with the iOS 18.4 SDK. Starting April 2026, all iOS and iPadOS apps must be built with the iOS 26 SDK or later, included in Xcode 26 or later, in order to be uploaded to App Store Connect or submitted for distribution.

### Update Flutter-Pakete

Status: Offen. Paketupdates wurden noch nicht durchgeführt, weil sie einen eigenen Regressionstest-Pass brauchen.

Alle Flutter-Pakete müssen aktualisiert werden.

## Bugs

### [#67] Datei-Anhänge lassen sich nicht mehr in Karten hochladen

Quelle: https://github.com/holger-dev/nextdeck/issues/67

Status: Umgesetzt, Test gegen NC 33 offen. Der Deck-Multipart-Upload setzt jetzt `OCS-APIRequest: true`, loggt Statuscode/Response-Snippet und versucht den Multipart-Upload zusätzlich ohne `type=file`.

Analyse:
- Betrifft laut Issue Nextcloud 33; ein Kommentar nennt NC `33.0.2` und App `1.7.0 (6)`.
- Upload in der Nextcloud-Deck-Webapp funktioniert, Fehler tritt in der App auf.
- Relevanter Code: `lib/pages/card_detail_page.dart` ruft `uploadCardAttachment`; Implementierung in `lib/services/nextcloud_deck_api.dart`.

Umsetzung:
- Normalen Upload gegen funktionierenden Server regressionstesten.
- Gegen NC 33 mit Debug-Log prüfen: HTTP-Status, Body-Snippet, ggf. Server-Log.
- Falls NC 33 weiter fehlschlägt: Fallback-Strategie prüfen, z. B. erst WebDAV-Datei hochladen und danach Attachment/Referenz an Deck hängen, sofern die Deck-API das stabil erlaubt.

Akzeptanz:
- Anhänge lassen sich auf aktuellen stabilen Nextcloud-/Deck-Versionen hochladen.
- Bei Fehlern wird eine diagnosefähige Meldung geloggt.
- Kein Regress bei Anzeige, Download und Löschen bestehender Anhänge.

### [#62] Boards lassen sich nicht löschen

Quelle: https://github.com/holger-dev/nextdeck/issues/62

Status: Umgesetzt. Board-Löschen ist in API, App-State und Board-Menü ergänzt.

Analyse:
- Im lokalen Code gibt es Board-Erstellung, Farbänderung und Ausblenden, aber keine echte Board-Löschfunktion.
- `toggleBoardHidden` ist nur lokale Sichtbarkeit, kein Löschen auf dem Server.
- Relevanter Code: `lib/state/app_state.dart`, `lib/services/nextcloud_deck_api.dart`, `lib/pages/overview_page.dart`, ggf. Board-Menü in `lib/pages/board_page.dart`.

Umsetzung:
- Deck-API-Methode für Board-Löschen/Archivieren sauber ergänzen und mehrere Endpoint-Varianten prüfen.
- UI-Aktion mit Bestätigungsdialog ergänzen; destruktive Aktion klar von "ausblenden" unterscheiden.
- Lokale Caches nach erfolgreichem Löschen vollständig entfernen: `columns_*`, `stacks_*`, `board_members_*`, `board_lastmod_*`, active/default board.

Akzeptanz:
- Board kann gelöscht oder, falls Deck nur Archivierung anbietet, eindeutig archiviert werden.
- Gelöschtes Board verschwindet nach Refresh nicht wieder aus Cache/UI.
- Aktives Board wird robust auf ein vorhandenes Board umgestellt.

### [#63] Listen lassen sich nicht umbenennen

Quelle: https://github.com/holger-dev/nextdeck/issues/63

Status: Umgesetzt. Listen können über das Board-Menü ausgewählt und umbenannt werden.

Analyse:
- API-Unterstützung existiert bereits: `updateStack` in `lib/services/nextcloud_deck_api.dart`.
- App-State nutzt `updateStack` aktuell vor allem für Reordering.
- In `lib/pages/board_page.dart` gibt es "Neue Liste" und "Listen neu anordnen", aber keinen klaren UI-Einstieg zum Umbenennen.

Umsetzung:
- Listen-Menü oder Titel-Edit für Stack-Titel ergänzen.
- Optimistisches lokales Update plus Server-Update; bei Fehler rollback oder sichtbare Fehlermeldung.
- Cache `columns_$boardId` nach erfolgreichem Rename aktualisieren.

Akzeptanz:
- Listen-Titel ist auf iPad/iPhone editierbar.
- Änderung bleibt nach App-Neustart und Server-Refresh erhalten.

### [#65] Status-Chips in Board-Übersicht überlappen Karten

Quelle: https://github.com/holger-dev/nextdeck/issues/65

Status: Umgesetzt. Tablet-Grids nutzen feste Kartenhöhe und Chips begrenzen Text per Ellipsis.

Analyse:
- Betroffen: iPad Air 4. Gen, iPadOS 26.3.1.
- Relevanter Code: `_BoardSummary` und `_StatChip` in `lib/pages/overview_page.dart`.
- Die Übersicht nutzt bei Tablets `GridView` mit festem `childAspectRatio`; lange Chip-Texte und viele Chips können die Kartenhöhe überschreiten.
- Das Enhancement #66 ist eng verwandt, aber der Layout-Bug hat Vorrang.

Umsetzung:
- Kartenhöhe in der Board-Übersicht dynamischer/robuster machen oder Chip-Darstellung kompakter gestalten.
- Text in Chips vor Überlauf schützen, z. B. Wrap, FittedBox, Short Labels oder MaxLines.
- Desktop/iPad und iPhone separat prüfen.

Akzeptanz:
- Keine Chips ragen aus Board-Karten heraus.
- Kein Überlappen bei deutscher, englischer und spanischer Sprache.
- Board-Karten bleiben gut antippbar und visuell stabil.

### [#61] MP3-Files not playable

Quelle: https://github.com/holger-dev/nextdeck/issues/61

Status: Umgesetzt. Audio-Anhänge werden explizit erkannt und bevorzugt per externer App geöffnet.

Analyse:
- Erwartung: MP3-Anhänge sollen mit der iOS-Standard-Audio-App/Preview geöffnet werden.
- Relevanter Code: Attachment-Öffnen in `lib/pages/card_detail_page.dart`.
- Aktuell werden Nicht-Bilder temporär gespeichert und per `url_launcher` geöffnet, mit Share-Sheet als Fallback. Für Audio kann das auf iOS unzuverlässig sein.

Umsetzung:
- MP3/M4A/WAV-MIME-Typen explizit erkennen.
- Geeigneten iOS-Open-Flow prüfen: Quick Look, Share Sheet, `open_filex`/UIDocumentInteractionController-ähnlicher Flow oder integrierter Player.
- Dateiendung/MIME sauber setzen, damit iOS die Datei erkennt.

Akzeptanz:
- MP3-Anhang lässt sich aus einer Karte öffnen/abspielen.
- Fallback per Share Sheet bleibt erhalten.

### [#58] Karten-Reihenfolge ändert sich beim Öffnen einer Karte im Browser

Quelle: https://github.com/holger-dev/nextdeck/issues/58

Status: Umgesetzt im Client. Server-Order wird beim Merge normalisiert und Stack-Order bei lokalem Reorder erhalten.

Analyse:
- Kritisch, weil Kartenreihenfolge die Tagesordnung abbildet.
- Beobachtung betrifft Browser-Nutzer; iPad/iPhone bleibt zunächst stabil.
- Relevanter lokaler Code: Order-Handling und Cache in `lib/state/app_state.dart`, Card-Parsing in `lib/models/card_item.dart`, Fetch-/Update-Endpunkte in `lib/services/nextcloud_deck_api.dart`.

Umsetzung:
- Prüfen, ob App beim Refresh serverseitige `order` korrekt respektiert und nicht durch Index-/Fallback-Sortierung überschreibt.
- Prüfen, ob Browser/Deck beim Öffnen `lastModified` oder Card-Daten so verändert, dass unsere Sortierung neu berechnet wird.
- Reproduktionsfall mit zwei Clients dokumentieren.

Akzeptanz:
- Öffnen einer Karte darf keine Reorder-Aktion auslösen.
- Nach Refresh bleibt die Reihenfolge identisch, solange keine echte Move-/Reorder-Aktion passiert.

### [#50] Links in Cards sind nicht klickbar

Quelle: https://github.com/holger-dev/nextdeck/issues/50

Status: Umgesetzt. Markdown-Links in der Preview öffnen per `url_launcher`.

Analyse:
- Issue ist als `bug` gelabelt, funktional aber nah an Enhancement.
- Relevanter Code: Markdown-Anzeige/Editor in `lib/widgets/markdown_editor.dart`; Kartenanzeige in `lib/pages/card_detail_page.dart` und Preview in `lib/pages/board_page.dart`.
- Attachments mit Weblinks werden bereits an Teilen der UI geöffnet; Markdown-Links in Card-Beschreibungen brauchen gezielte Link-Handler.

Umsetzung:
- `MarkdownBody` mit `onTapLink` ausstatten und `url_launcher` verwenden.
- URL-Schemata absichern: `http`, `https`, ggf. `mailto`.
- In Read-only-Preview und Editor-Preview konsistent machen.

Akzeptanz:
- Markdown-Links in Kartenbeschreibungen sind antippbar.
- Links öffnen extern und stören das Editieren nicht.

## Enhancements

### [#66] Option: Info-Chips in Board-Übersicht ausblenden

Quelle: https://github.com/holger-dev/nextdeck/issues/66

Status: Bereits vorhanden und beibehalten. Der bestehende Schalter `overviewShowBoardInfo` in den Einstellungen deckt den Wunsch ab.

Analyse:
- Eng verwandt mit Bug #65.
- Es gibt bereits `overviewShowBoardInfo` in `AppState`; prüfen, ob UI/Setting verständlich genug ist oder pro Board/gesamt erweitert werden soll.

Umsetzung:
- Nach Fix von #65 entscheiden, ob ein zusätzlicher Settings-Schalter nötig ist.
- Falls umgesetzt: globaler Toggle in Einstellungen, persistiert in Secure Storage/Cache; ggf. bestehende Logik wiederverwenden.

Akzeptanz:
- Nutzer kann Info-Chips in der Board-Übersicht deaktivieren.
- Einstellung bleibt nach Neustart erhalten.

### [#55] Mobile Push Notifications für Zuweisungen, Erwähnungen und Kommentare

Quelle: https://github.com/holger-dev/nextdeck/issues/55

Status: Teilumgesetzt. Lokale iOS-Benachrichtigungen für neu erkannte Zuweisungen und Erwähnungen werden beim Sync unterstützt; echte serverseitige Push/APNs-Integration bleibt offen.

Analyse:
- Aktuell existiert lokale Due-Date-Notification-Logik in `lib/services/notification_service.dart` und `lib/state/app_state.dart`.
- Echte Push-Notifications brauchen Server-/Push-Integration; reine lokale Polling-Benachrichtigungen wären nur ein eingeschränkter Zwischenschritt.

Umsetzung:
- Machbarkeit klären: Nextcloud Notifications/OCS Polling vs. echtes APNs/Push.
- Minimalvariante: regelmäßiger Sync erkennt neue Zuweisungen/Kommentare/Mentions und erzeugt lokale Benachrichtigung.
- Vollvariante: Push-Architektur mit Server-/Nextcloud-Unterstützung.

Akzeptanz:
- Nutzer wird bei neuer Zuweisung, Mention oder Kommentar zuverlässig informiert.
- Keine Doppelbenachrichtigungen bei wiederholtem Sync.

### [#54] Per-board manual sync interval

Quelle: https://github.com/holger-dev/nextdeck/issues/54

Status: Umgesetzt als per-Board-Preference mit vorsichtigem aktivem Board-Sync. Der große globale Hintergrundsync bleibt deaktiviert.

Analyse:
- Sync-Logik sitzt in `lib/state/app_state.dart`, `lib/sync/sync_service_impl.dart` und `lib/config/sync_config.dart`.
- Aktuell gibt es globale Sync-/Cooldown-Mechanismen und boardbezogene Caches.

Umsetzung:
- Datenmodell für board-spezifisches Sync-Intervall ergänzen.
- UI in Board-Einstellungen oder Board-Menü ergänzen.
- Scheduler so anpassen, dass globale Defaults und Board-Overrides zusammenarbeiten.

Akzeptanz:
- Pro Board kann ein Intervall wie 1/5/15/30 Minuten gesetzt werden.
- Boards ohne Override nutzen den globalen Standard.

### [#53] Markdown editor: einfachere Task- und Bullet-Listen

Quelle: https://github.com/holger-dev/nextdeck/issues/53

Status: Umgesetzt. Toolbar-Buttons für Bullet-Listen und Task-Listen sind sichtbar.

Analyse:
- `MarkdownEditor` kann Task-Listen anzeigen/toggeln, aber das Erstellen mehrerer Listenpunkte ist noch umständlich.
- Relevanter Code: `lib/widgets/markdown_editor.dart`.

Umsetzung:
- Toolbar-Aktionen für Bullet-List und Task-List ergänzen.
- Mehrzeilige Auswahl berücksichtigen: Prefix je Zeile setzen/entfernen.
- Enter-Verhalten prüfen: Folgezeile automatisch mit passendem Prefix starten.

Akzeptanz:
- Nutzer kann mehrere Bullet-/Task-List-Zeilen ohne manuelles Prefixing erstellen.
- Bestehendes Markdown bleibt unverändert kompatibel zu Nextcloud Deck.

## Infos

- GitHub-Issues wurden über `https://api.github.com/repos/holger-dev/nextdeck/issues` mit Labels `bug` und `enhancement` abgefragt.
- Lokale Analyse erfolgte gegen den aktuellen Workspace; vorhandene Änderung am Attachment-Upload bleibt separat im Diff.
