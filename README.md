# Next Deck

A lean, fast and privacy-friendly Nextcloud Deck client with native Cupertino UI. Built with Flutter, optimized for iPhone and iPad - also runs on macOS, Android, Windows, Linux and on the web.

> Prerequisite: A running Nextcloud instance with activated "Deck" app.


## Highlights

- Drag & Drop: Move cards within a list and to other lists
- Reorder & Position: Place cards in front of/behind other cards, move up/down
- Labels & colors: Immediate orientation through color codes (incl. board color from Nextcloud)
- Due dates: Overdue red, ≤24h orange - directly visible on the card
- Responsibilities: Assign team members and make responsibilities visible
- Markdown description: Editor with live display in the card detail
- Comments: Display, reply, delete; counter on the cards
- Attachments: Display, open/share, upload, delete (incl. WebDAV fallback)
- Search: In the active board or globally across all boards
- Pending: Due cards grouped (Overdue, Today, Tomorrow, Next 7 days, Later)
- Overview: Active board, other boards, hidden and archived boards
- Local mode: Local board that can be used completely offline (To Do / In progress / Done)
- Dark mode & smart colors: Pleasant contrasts, good readability
- Multilingual: German, English, Spanish (manually selectable or system language)

## Installation (local)

- Required: Flutter SDK (Dart ≥ 3.3), Xcode/Android Studio depending on target platform
- Clone project and load dependencies:
  ```bash
  flutter pub get
  ```
- Start (example):
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
- First steps in the app:
  - Enter the server address (without scheme; the app enforces HTTPS), user name and password (recommended: app password) in the settings under "Account"
  - Execute "Test login"; the app checks login, deck availability and then loads boards


## Security & data protection

- HTTPS enforced: Entries are automatically normalized to `https://`
- Local storage: Access data is stored securely on the device using `flutter_secure_storage`.
- Local cache: boards/lists/maps are cached in compressed form in `Hive` (faster views, "pending")
- No tracking, no external servers: Your data stays with you on your Nextcloud server


## Overview of functions

- Load boards, select and memorize active board
- Display, sort, move and delete lists (stacks) and cards
- Mark card as "done" (automatically move to Done) and set to "undone" again
- Edit title, description (Markdown) and due date
- Labels, assignees, comment counter and attachment counter
- Retrieve, create (incl. replies), delete comments
- Upload file attachments (multipart), download/open/share; robust against server deviations
- Global search with area (current board/all boards) and progress indicator
- "Pending" across all boards with due buckets
- Board overview with hide/show and archive section
- Languages (de/en/es) can be switched manually; system fallback


## Local mode (offline)

- Can be activated in the settings ("Local board")
- No network connection, no access data - ideal for quick local lists
- Predefined lists: To Do, In progress, Done
- Switch back to online mode at any time (reset access data)


## Development

- Tech stack: Flutter (Cupertino), Provider (State), Hive (Cache), flutter_secure_storage, http, flutter_markdown, file_picker, share_plus, url_launcher
- Folder structure:
  - `lib/pages`: Screens (board, overview, pending, settings, details, search)
  - `lib/state`: `AppState` incl. caching, warmup, sync logic
  - `lib/services`: Nextcloud Deck API client and logging
  - `lib/models`: board/stack/card/label/user/comment
  - `lib/theme`: Theme & color logic
  - `lib/l10n`: Localizations
- Linting: `analysis_options.yaml` (flutter_lints)
- Execute tests:
 ```bash
 flutter test
 ```


## Roadmap / Open points

- Make archived maps visible (filter)
- Further translations
- Push notifications for overdue cards
- Create new lists and boards (planned for v2.0)

For details and history see `TODO.md` and `STORE.md`.


## Frequently asked questions (FAQ)

- "The login fails": It is best to use an app password. Make sure that the Deck app is active in your Nextcloud.
- "Why only HTTPS?": For security reasons, all connections are forced to HTTPS.
- "Where is my data stored?": All content remains on your Nextcloud server; only encrypted access data and a slim cache are stored locally.


## Note

This project is not affiliated with Nextcloud GmbH. "Nextcloud" and "Deck" are trademarks of their respective owners.
