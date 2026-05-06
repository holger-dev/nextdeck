# Changelog

All notable changes are documented in this file.

This changelog is based on `STORE.md` and links to detailed release notes in `changelog/`.

## [1.8]
- Modernized UI: floating glass tab bar (iOS 17/18 look), softer card shadows, design-token system.
- Faster sync: HTTP keep-alive pool, large JSON payloads decoded in a background isolate, ~80x fewer UI rebuilds per sync via notify coalescing.
- Conflict protection: optimistic-concurrency detection on every card save with a clear "Reload current / Overwrite anyway" dialog.
- iOS Shortcuts / Siri integration: create cards directly via `nextdeck://newcard?title=…`.
- Server-side notification polling: banners for assignments, comment-@-mentions, and shares come from the central Nextcloud notifications API — works across all boards.
- Bug fixes: clickable links (#50, #68), card order stability (#58), MP3 attachments (#61), board delete (#62), list rename (#63), status-chip overlap (#65), file uploads on current Nextcloud (#67), brighter board overview palette (#51).
- Improvements: two-row markdown toolbar with auto-selected placeholders (#53), per-board sync interval (#54), local notifications for assignments/mentions (#55), hideable info chips (#66), scrollable long descriptions, skeleton loaders, haptic feedback.
- Details: `changelog/1.8.md`

## [1.7]
- Added board/upcoming filters (`assigned to me` vs `all`) in views and settings.
- Added board actions (create boards, add/move columns, change board color).
- Added overdue notifications, @mentions, archive filters, and home screen widgets.
- Improved card handling (color mode, assigned-only filters, attachments, PDF opening on iOS).
- Details: `changelog/1.7.md`

## [1.6]
- Added done/undone toggle in card details.
- Improved dark-mode readability and localized tags label.
- Added due-date removal via `X` and improved description editing UX.
- Added theme selection (Light/Dark/System).
- Details: `changelog/1.6.md`

## [1.5]
- Improved loading speed and reduced network load.
- Added one-column mode in Upcoming.
- Added local-data delete button and stability improvements for many boards.
- Details: `changelog/1.5.md`

## [1.4]
- Overview sorted boards A-Z with pull-down search.
- Language texts refined and unified.
- App opens settings directly when credentials are missing.
- Improved dark-mode readability.
- Details: `changelog/1.4.md`

## [1.3.0]
- Board selection now opens the board directly (instead of Upcoming).
- Added `mark as undone` flow for cards from Done back to to-do.
- Details: `changelog/1.3.0.md`

## [1.2.0-3]
- Board selection now opens the board directly (instead of Upcoming).
- Added `mark as undone` in card menu.
- Details: `changelog/1.2.0-3.md`

## [1.2]
- Added global search, upcoming aggregation, archived-board section, delete card, and mark-as-done.
- Improved overdue highlighting and settings version visibility.
- Details: `changelog/1.2.md`

## [1.1]
- Bug fixes and stability improvements.
- Enforced HTTPS for server URLs.
- Details: `changelog/1.1.md`

[1.8]: changelog/1.8.md
[1.7]: changelog/1.7.md
[1.6]: changelog/1.6.md
[1.5]: changelog/1.5.md
[1.4]: changelog/1.4.md
[1.3.0]: changelog/1.3.0.md
[1.2.0-3]: changelog/1.2.0-3.md
[1.2]: changelog/1.2.md
[1.1]: changelog/1.1.md
