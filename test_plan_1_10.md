# Testplan Next Deck 1.10.0+21

Alle Tests auf echtem Gerät (iPhone + iPad), einmal mit frischer Installation, einmal als Update über 1.9.

## #75 — Erledigte Karten nicht mehr überfällig
- [ ] Karte mit Fälligkeit in der Vergangenheit anlegen → wird rot (überfällig) angezeigt
- [ ] Karte als erledigt markieren → Badge wird **grün mit Häkchen** (Board-Ansicht), nicht mehr rot
- [ ] Übersicht: Board-Statistik zählt die erledigte Karte nicht mehr bei „überfällig"
- [ ] Anstehend: erledigte Karte taucht in keiner Spalte auf
- [ ] App neu starten → Zustand bleibt (Cache-Test)

## #82 — Enter setzt Checkliste fort
- [ ] Karten-Beschreibung öffnen, `- [ ] Erste Aufgabe` tippen, Enter → neue Zeile beginnt automatisch mit `- [ ] `
- [ ] Text tippen, wieder Enter → nächste Task-Zeile
- [ ] Auf leerer Task-Zeile Enter → Marker verschwindet, Liste beendet
- [ ] Gleiche Tests mit einfacher Bullet-Liste (`- Text`)
- [ ] Gegenprobe: Enter mitten im Fließtext → KEIN Auto-Marker
- [ ] Gegenprobe: mehrzeiligen Text einfügen (Paste) → kein Auto-Marker-Chaos

## #84 — „Ohne Fälligkeit" in Anstehend
- [ ] Karte ohne Fälligkeitsdatum anlegen
- [ ] Anstehend (Spalten-Modus): neue 6. Spalte „Ohne Fälligkeit" per Wisch/Pfeil erreichbar, Karte da drin
- [ ] Anstehend (Einspalten-Modus): Sektion „Ohne Fälligkeit" am Ende
- [ ] Spalten-Auswahl-Sheet (Listen-Icon) zeigt „Ohne Fälligkeit" als Eintrag
- [ ] Karte in der Sektion zeigt Board-/Stack-Name (Meta-Zeile)
- [ ] Tap auf Karte öffnet Karten-Detail
- [ ] Karte bekommt Fälligkeitsdatum → wandert nach Refresh in die richtige Zeitspalte

## #83 — Attachment-Upload
- [ ] Datei (PDF, Bild, beliebig) über Büroklammer hochladen → erscheint in Anhängen
- [ ] In Nextcloud-Web gegenprüfen: Anhang da?
- [ ] Bei Fehlschlag: Settings → Logs prüfen, welche type-Variante (file/deck_file/none) versucht wurde und welcher HTTP-Status kam
- [ ] Test idealerweise gegen zwei Server (aktuelles Deck + ältere Version)

## #78 — PDF auf iPad öffnen
- [ ] iPad: PDF-Anhang antippen → Share-Sheet **erscheint** (vorher: nichts passierte)
- [ ] Quick Look / „In Dateien sichern" aus dem Sheet funktioniert
- [ ] iPhone-Gegenprobe: PDF öffnen geht weiterhin
- [ ] iPad: Karte teilen (System-Share aus Karten-Menü) → Popover erscheint
- [ ] Audio-Anhang (mp3) → öffnet weiterhin extern

## #70 — Karten-Drag auf iPad
- [ ] iPad: Durch Spalte mit vielen Karten scrollen → KEIN versehentliches Draggen mehr
- [ ] iPad: Karte gedrückt halten (~250ms) → Drag startet mit Haptik, Verschieben in andere Spalte klappt
- [ ] iPhone-Gegenprobe: LongPress-Drag wie bisher (500ms)

## #73 — Konfigurierbare Erinnerungs-Vorläufe
- [ ] Settings → Benachrichtigungen: neue Sektion „Weitere Vorlaufzeiten" unter 1h/1d-Toggles
- [ ] „Vorlaufzeit hinzufügen" → Sheet mit 15 Min / 30 Min / 2 Std / 4 Std / 8 Std / 2 Tage / 1 Woche
- [ ] Vorlauf hinzufügen (z. B. 30 Min), Karte mit Fälligkeit in ~35 Min anlegen → Notification kommt ~5 Min später
- [ ] Vorlauf per Minus-Button entfernen → keine Notification mehr dafür
- [ ] 1h/1d-Toggles funktionieren weiter wie vorher
- [ ] Mehrere Vorläufe gleichzeitig → alle feuern einzeln (keine ID-Kollision: unterschiedliche Zeiten)

## #80 — Xcode-Warnungen
- [ ] VOR dem Build im Terminal ausführen (Sandbox durfte nicht löschen):
      cd ios/Runner/Assets.xcassets/AppIcon.appiconset && rm Icon-App-50x50@*.png Icon-App-57x57@*.png Icon-App-72x72@*.png
- [ ] Xcode Archive: Warnung „AppIcon has 6 unassigned children" weg
- [ ] Warnung „'url' was deprecated in iOS 26.0" weg
- [ ] Deep-Link-Gegenprobe: App über nextdeck://-Link öffnen funktioniert noch

## #74 — macOS 26.5 (kein Code-Fix)
- Analyse: Gatekeeper/Notarisierung nach OS-Update, kein App-Bug.
- [ ] Auf GitHub beim Reporter nachfragen, was der Dialog genau sagt
- [ ] Falls „beschädigt/kann nicht geprüft werden": macOS-Build künftig notarisieren; Workaround für User: Rechtsklick → Öffnen oder `xattr -c /Applications/NextDeck.app`

## Regression (Kurzdurchlauf)
- [ ] Login Fresh-Install (der 1.9-Fix): App löschen, neu installieren, anmelden, force-quit, neu öffnen → noch angemeldet
- [ ] Kommentar auf Karte schreiben → Eingabefeld über der Tab-Bar sichtbar, Senden geht
- [ ] Board-Sync, Karten verschieben, Karte anlegen/bearbeiten
- [ ] Benachrichtigungen (Activity + Fälligkeit) kommen weiterhin
