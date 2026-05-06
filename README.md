# Next Deck iOS app

[<img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg"
alt="Demo of the Next Deck iOS app"
height="40">]([https://apps.apple.com/de/app/next-deck/id6752478755)

A clean, fast and privacy-friendly Nextcloud Deck client with native Cupertino UI. Built with Flutter, optimized for iPhone and iPad - also runs on macOS, Android, Windows, Linux and on the web.

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


## Notifications

Next Deck offers two complementary mechanisms for activity notifications
(card assignments, @-mentions in comments, shares):

1. **Foreground polling** while the app is open — the active board syncs on
   the configured interval, and the central Nextcloud notifications API is
   polled in parallel (latency: under one minute).
2. **Background fetch** when the app is in the background or terminated —
   iOS wakes the app every 15-60 minutes (Apple decides; can take longer if
   the device is idle or the battery is low) and the same poll runs.

Both mechanisms produce **local notifications** rendered by iOS — they look
identical to system push, but technically they are *not* push.

### Why not real APNs push?

Real push (sub-second delivery, app does not need to run at all) goes
through Apple's APNs. The official Nextcloud iOS app uses the central
`push.nextcloud.com` proxy, which is configured *only* for the official app
bundle ID `com.nextcloud.iOS`. Third-party apps like Next Deck cannot
attach to that proxy out of the box. A real push setup for Next Deck would
require:

- An Apple Developer APNs Auth Key (`.p8`), key ID, team ID
- The "Push Notifications" capability enabled on your app ID in App Store
  Connect
- Either:
  - Your own self-hosted push proxy (e.g. `nextcloud/push-proxy`) running
    next to your Nextcloud server, configured with the `.p8` key and the
    Next Deck bundle ID — *or*
  - A direct APNs sender service that subscribes to your Nextcloud
    `notifications` events
- The App-side Push subscription flow against
  `/ocs/v2.php/apps/notifications/api/v2/push` with an RSA key pair

That is roughly a day of development plus server-admin work, and ongoing
operational responsibility for the push proxy. **Most users will not need
this.** The polling-based approach is "good enough" for the vast majority
of workflows and requires no server changes.

### Recommended setup if you want real push *today*

If you absolutely need sub-second push and don't want to host a proxy
yourself:

1. **Install the official Nextcloud iOS app** alongside Next Deck.
2. The Nextcloud app handles real push via `push.nextcloud.com`. Card
   assignments, mentions and shares will pop up there.
3. **Disable activity notifications inside Next Deck** (Settings ->
   Notifications) to avoid duplicates.
4. Use Next Deck for the actual board work — the Nextcloud app for the
   notification handoff.

This is a pragmatic, zero-configuration approach that gives you the
combined strengths of both apps. If at some point you decide to set up a
custom push proxy for Next Deck, the in-app polling can be re-enabled and
the Nextcloud-app notifications can be turned off there.


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

For details about store content see `STORE.md`.


## Frequently asked questions (FAQ)

- "The login fails": It is best to use an app password. Make sure that the Deck app is active in your Nextcloud.
- "Why only HTTPS?": For security reasons, all connections are forced to HTTPS.
- "Where is my data stored?": All content remains on your Nextcloud server; only encrypted access data and a slim cache are stored locally.


## Note

This project is not affiliated with Nextcloud GmbH. "Nextcloud" and "Deck" are trademarks of their respective owners.
