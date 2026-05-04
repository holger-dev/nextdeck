# NC 33 Test-Setup für Issue #67 (Anhang-Upload)

Lokaler Nextcloud-33-Stack zum Verifizieren, dass `uploadCardAttachment`
gegen aktuelle Deck-API durchgeht.

## Voraussetzungen
- Docker Desktop (oder OrbStack / Colima) auf macOS
- iOS-Simulator (iPhone 15 oder später, Cowork-Setup)
- ~2 GB freier Plattenplatz für die Volumes

## Schritt 1 — Stack starten

```bash
cd ~/Development/nextdeck/test/nc33
docker compose up -d
```

Erstmaliger Start: ~1–2 min, NC initialisiert die Datenbank. Status checken:

```bash
docker compose logs -f app | grep -m1 -E "Initializing finished|admin user"
```

Sobald die Zeile `admin user … created` (oder ähnlich) auftaucht, ist NC bereit.

## Schritt 2 — Deck-App im Container installieren

```bash
docker compose exec --user www-data app php occ app:install deck
docker compose exec --user www-data app php occ app:enable deck
docker compose exec --user www-data app php occ deck:export 2>/dev/null || true
```

Verifizieren:

```bash
docker compose exec --user www-data app php occ app:list | grep -i deck
```

Sollte etwas in der Form `- deck: …` zeigen.

## Schritt 3 — App-Passwort erzeugen

NC verlangt für REST-Calls ein App-Passwort statt des Klartext-Logins.

1. Im Browser: <http://localhost:8080>
2. Login: `admin` / `admin_pw`
3. Oben rechts → **Persönliche Einstellungen** → **Sicherheit** → **App-Passwort erstellen**
4. Name: „nextdeck-test", Passwort merken (1× sichtbar)

## Schritt 4 — Testdaten anlegen

Im Browser unter **Deck**:
1. Ein Board „NC33 Test" erstellen
2. Stack „To Do" hinzufügen, eine Karte „Anhang-Test" anlegen
3. (Optional) zweiten Stack „Done" anlegen, damit Move-Tests laufen

## Schritt 5 — Nextdeck-App gegen den Container

In Nextdeck (im iOS-Simulator):
1. Settings → Konto
2. Server-URL: `localhost:8080` *(http, kein https — App akzeptiert localhost ohne TLS)*
3. Username: `admin`
4. App-Passwort aus Schritt 3 einfügen
5. „Anmeldung testen & Boards laden" → es muss „Login OK – 1 Board gefunden" erscheinen
6. Board „NC33 Test" öffnen → Karte „Anhang-Test" → ➕ bei „Anhänge"
7. Datei aus Foto-Library auswählen
8. Erwartung:
   - **Erfolg**: Anhang erscheint in der Liste
   - **Fehler**: Settings → Entwicklung → Debug-Log → die letzten POST-Einträge zu `/apps/deck/api/v…/attachments` kopieren

## Schritt 6 — Aufräumen

```bash
docker compose down -v   # -v löscht auch die Volumes
```

## Troubleshooting

- **"Trusted domain" Fehler** → in `.env` nochmal prüfen oder
  `docker compose exec --user www-data app php occ config:system:set trusted_domains 1 --value=localhost`
- **App-Passwort funktioniert nicht** → manche NC-33-Builds wollen das Passwort URL-encodet im Header; die Nextdeck-App macht das automatisch. Falls trotzdem 401: nochmal neu erzeugen.
- **Port 8080 belegt** → in `docker-compose.yml` den Host-Port ändern (z. B. `8088:80`) und in der App entsprechend `localhost:8088` eintragen.
