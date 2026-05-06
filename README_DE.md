# Next Deck

Ein schlanker, schneller und datenschutzfreundlicher Nextcloud‑Deck‑Client mit nativer Cupertino‑UI. Gebaut mit Flutter, optimiert für iPhone und iPad – läuft auch auf macOS, Android, Windows, Linux und im Web.

> Voraussetzung: Eine laufende Nextcloud‑Instanz mit aktivierter „Deck“‑App.


## Highlights

- Drag & Drop: Karten innerhalb einer Liste und in andere Listen verschieben
- Reorder & Position: Karten gezielt vor/ hinter andere Karten setzen, nach oben/unten bewegen
- Labels & Farben: Sofortige Orientierung durch Farbcodes (inkl. Board‑Farbe aus Nextcloud)
- Fälligkeiten: Überfällige rot, ≤24h orange – direkt auf der Karte sichtbar
- Zuständigkeiten: Teammitglieder zuweisen und Verantwortung sichtbar machen
- Markdown‑Beschreibung: Editor mit Live‑Anzeige im Kartendetail
- Kommentare: Anzeigen, Antworten, Löschen; Zähler auf den Karten
- Anhänge: Anzeigen, Öffnen/Teilen, Hochladen, Löschen (inkl. WebDAV‑Fallback)
- Suche: Im aktiven Board oder global über alle Boards
- Anstehend: Fällige Karten gruppiert (Überfällig, Heute, Morgen, Nächste 7 Tage, Später)
- Übersicht: Aktives Board, weitere Boards, versteckte und archivierte Boards
- Lokaler Modus: Komplett offline nutzbares, lokales Board (To Do / In Arbeit / Erledigt)
- Dark Mode & smarte Farben: Angenehme Kontraste, gute Lesbarkeit
- Mehrsprachig: Deutsch, Englisch, Spanisch (manuell wählbar oder Systemsprache)

## Installation (lokal)

- Erforderlich: Flutter SDK (Dart ≥ 3.3), Xcode/Android Studio je nach Zielplattform
- Projekt klonen und Abhängigkeiten laden:
  ```bash
  flutter pub get
  ```
- Starten (Beispiele):
  ```bash
  # iOS Simulator / macOS
  flutter run -d ios
  flutter run -d macos

  # Android Emulator
  flutter run -d android

  # Web (Chrome)
  flutter run -d chrome

  # Windows / Linux (wenn Flutter Desktop eingerichtet ist)
  flutter run -d windows
  flutter run -d linux
  ```
- Erste Schritte in der App:
  - In den Einstellungen unter „Konto“ die Server‑Adresse (ohne Schema; die App erzwingt HTTPS), Benutzername und Passwort (empfohlen: App‑Passwort) eintragen
  - „Anmeldung testen“ ausführen; die App prüft Login, Deck‑Verfügbarkeit und lädt anschliessend Boards


## Benachrichtigungen

Next Deck nutzt zwei komplementäre Wege für Aktivitäts-Benachrichtigungen
(Karten-Zuweisungen, @-Mentions in Kommentaren, Shares):

1. **Foreground-Polling**, solange die App offen ist – das aktive Board
   wird im konfigurierten Intervall gesynct, parallel die zentrale
   Nextcloud-Notifications-API gepollt (Latenz: unter einer Minute).
2. **Background-Fetch**, wenn die App im Hintergrund oder beendet ist –
   iOS weckt die App alle 15–60 min auf (Apple entscheidet; kann länger
   dauern bei Standby/niedrigem Akku) und führt denselben Poll aus.

Beide Wege erzeugen **lokale Banner**, die iOS rendert – sie sehen aus wie
echtes Push, sind technisch aber **kein** Push.

### Warum kein echtes APNs-Push?

Echtes Push (Sub-Sekunden-Latenz, App muss nicht laufen) geht über Apples
APNs. Die offizielle Nextcloud-iOS-App nutzt dafür den zentralen
`push.nextcloud.com`-Proxy, der **ausschließlich** für die offizielle
App-Bundle-ID `com.nextcloud.iOS` konfiguriert ist. Drittanbieter-Apps wie
Next Deck können sich dort nicht direkt anhängen. Echtes Push für Next
Deck würde verlangen:

- Apple Developer APNs Auth Key (`.p8`), Key-ID, Team-ID
- „Push Notifications"-Capability für die App-ID in App Store Connect
- Entweder:
  - Ein eigener Push-Proxy (z. B. `nextcloud/push-proxy`) auf dem eigenen
    Server, konfiguriert mit dem `.p8`-Key und der Next-Deck-Bundle-ID –
    *oder*
  - Ein Direkt-APNs-Service, der Nextcloud-`notifications`-Events
    abonniert und an APNs schickt
- Den App-seitigen Push-Subscribe-Flow gegen
  `/ocs/v2.php/apps/notifications/api/v2/push` mit RSA-Keypair

Realistisch heißt das ~ 1 Tag Code + Server-Admin + dauerhafte Wartung des
Push-Proxys. **Für die meisten Use-Cases ist das nicht nötig.** Das
Polling-Modell ist „gut genug", wenn man auf 15–60 min Latenz im
Hintergrund leben kann, und braucht keinerlei Server-Änderungen.

### Empfehlung, wenn du echtes Push *heute* willst

Wenn du sub-Sekunden-Push brauchst und keinen eigenen Proxy hosten
möchtest:

1. **Installiere die offizielle Nextcloud-iOS-App** zusätzlich zu Next
   Deck.
2. Die Nextcloud-App liefert echtes Push via `push.nextcloud.com`.
   Karten-Zuweisungen, Mentions und Shares poppen dort verlässlich auf.
3. **Deaktiviere die Activity-Benachrichtigungen in Next Deck**
   (Einstellungen → Benachrichtigungen), um Doppelbenachrichtigungen zu
   vermeiden.
4. Nutze Next Deck für die eigentliche Board-Arbeit – die Nextcloud-App
   fängt den Notification-Handoff ab.

Das ist der pragmatische Zero-Config-Weg, der die Stärken beider Apps
kombiniert. Wenn du später einen eigenen Push-Proxy aufsetzt, kannst du
die In-App-Benachrichtigungen wieder aktivieren und die der Nextcloud-App
abschalten.


## Sicherheit & Datenschutz

- HTTPS erzwungen: Eingaben werden automatisch auf `https://` normalisiert
- Lokale Speicherung: Zugangsdaten werden per `flutter_secure_storage` sicher auf dem Gerät abgelegt
- Lokaler Cache: Boards/Listen/Karten werden komprimiert in `Hive` gecacht (schnellere Ansichten, „Anstehend“)
- Kein Tracking, keine Fremdserver: Deine Daten bleiben bei dir auf deinem Nextcloud‑Server


## Funktionsüberblick

- Boards laden, aktives Board auswählen und merken
- Listen (Stacks) und Karten anzeigen, sortieren, verschieben, löschen
- Karte als „erledigt“ markieren (automatisch in Done/Erledigt verschieben) und wieder „unerledigt“ setzen
- Titel, Beschreibung (Markdown) und Fälligkeit bearbeiten
- Labels, Assignees, Kommentar‑Zähler und Anhang‑Zähler
- Kommentare abrufen, erstellen (inkl. Antworten), löschen
- Dateianhänge hochladen (Multipart), herunterladen/öffnen/teilen; robust gegen Server‑Abweichungen
- Globale Suche mit Bereich (aktuelles Board/alle Boards) und Fortschrittsanzeige
- „Anstehend“ über alle Boards mit Due‑Buckets
- Board‑Übersicht mit Verstecken/Einblenden und Archiv‑Sektion
- Sprachen (de/en/es) manuell umschaltbar; System‑Fallback


## Lokaler Modus (Offline)

- In den Einstellungen aktivierbar („Lokales Board“)
- Keine Netzverbindung, keine Zugangsdaten – ideal für schnelle lokale Listen
- Vordefinierte Listen: To Do, In Arbeit, Erledigt
- Wechsel zurück in den Online‑Modus jederzeit möglich (Zugangsdaten erneut setzen)


## Entwicklung

- Tech‑Stack: Flutter (Cupertino), Provider (State), Hive (Cache), flutter_secure_storage, http, flutter_markdown, file_picker, share_plus, url_launcher
- Ordnerstruktur:
  - `lib/pages`: Screens (Board, Übersicht, Anstehend, Einstellungen, Details, Suche)
  - `lib/state`: `AppState` inkl. Caching, Warmup, Sync‑Logik
  - `lib/services`: Nextcloud‑Deck‑API‑Client und Logging
  - `lib/models`: Board/Stack/Karte/Label/User/Kommentar
  - `lib/theme`: Theme & Farblogik
  - `lib/l10n`: Lokalisierungen
- Linting: `analysis_options.yaml` (flutter_lints)
- Tests ausführen:
  ```bash
  flutter test
  ```


## Roadmap / Offene Punkte

- Archivierte Karten einblendbar machen (Filter)
- Weitere Übersetzungen
- Push‑Benachrichtigungen für überfällige Karten
- Listen und Boards neu anlegen (für v2.0 geplant)

Details zum App Store inhalt finden Sie in `STORE.md`.


## Häufige Fragen (FAQ)

- „Die Anmeldung schlägt fehl“: Nutze am besten ein App‑Passwort. Stelle sicher, dass die Deck‑App in deiner Nextcloud aktiv ist.
- „Warum nur HTTPS?“: Aus Sicherheitsgründen werden alle Verbindungen auf HTTPS erzwungen.
- „Wo liegen meine Daten?“: Alle Inhalte verbleiben auf deinem Nextcloud‑Server; lokal liegen nur verschlüsselte Zugangsdaten und ein schlanker Cache.


## Hinweis

Dieses Projekt steht in keiner Verbindung zur Nextcloud GmbH. „Nextcloud“ und „Deck“ sind Marken ihrer jeweiligen Inhaber.

