# Changelog

All notable changes are documented in this file.

This changelog is based on `STORE.md` and links to detailed release notes in `changelog/`.

## [2.4]
- CRITICAL login fix: tapping "Test login" with an empty password field silently overwrote the stored keychain password with an empty string — breaking existing accounts (401 everywhere) while fresh test accounts kept working. An empty field now reuses the stored password; with none stored, a clear message asks for the app password.
- Username and app password are trimmed on login (invisible spaces/newlines from iOS copy-paste caused 401s); password field disables autocorrect/suggestions.
- Auth circuit breaker: after repeated 401/403 the app pauses ALL background polling/sync (previously every poll fed Nextcloud's brute-force throttle until even correct logins failed), shows a tappable banner in Upcoming, and resumes after new credentials or a successful login test.
- Login test reports the actual reason: 401/403 → app-password/2FA guidance, 429 → throttling hint with wait advice, DNS failure → "server not found (try www.)"; retries once on transient errors — and no longer hammers 4 URL variants per attempt.
- Server URL input is normalized: everything from `/index.php`, `/login` or `/apps/` on is stripped, so URLs copied from the browser address bar just work (previously they produced 404 on every API call).
- Sync speaks BOTH URL forms: `/index.php/apps/…` and pretty URLs, falling back on 404 — fixes "boards load but cards never do" on servers that only route one form (seen on NC 35 subpath installs answering 404 with a correct body).
- Rate-limit circuit breaker: on HTTP/OCS 429 ("Reached maximum delay") the app enters a cool-down (no retries, background sync paused, orange self-healing banner) instead of keeping the server's brute-force throttle at maximum.
- Critical sync fix: after a failed login attempt, Nextcloud's brute-force protection throttles all responses; card loads then died silently in the 15 s timeout and boards showed endless skeletons. Sync requests now retry up to 3 times with backoff (25 s timeout, 429/5xx + Retry-After handling) plus a sequential healing pass for failed boards.
- Honest status: the login flow now reports boards whose cards could not be loaded yet instead of claiming "all synced"; login test retries once before showing an error (avoids triggering throttling).
- Board view: skeletons only while a sync is actually running; an empty board now shows a clear message with a Refresh button instead of loading forever.
- Hardened stacks parsing: `cards: null` in the boards response no longer caches empty columns.
- Details: `changelog/2.4.md`.

## [2.2]
- Collapsible sections: Nextcloud Deck's <details>/<summary> markup in card descriptions now renders as animated expandable panels (closed by default, `open` attribute honored, nested blocks supported, graceful fallback for broken markup) instead of raw tags.
- New editor toolbar button inserts a collapsible-section scaffold with smart placeholder selection; markdown help updated (DE/EN/ES).
- Card tiles on Board and Upcoming exclude <details> blocks from the description preview — no more raw markup on cards.
- Details: `changelog/2.2.md`.

## [2.1]
- Search everywhere: new glass search button in the top-left of Upcoming, Board (scoped to the current board) and Overview; redesigned search page with pill-style field, native clear button and live results.
- Upcoming auto-refreshes after local card changes (label, title, text, due date) via a cache revision counter — no manual sync needed.
- Attachment transfers show a modal progress overlay with a hint and a working Cancel button (uploads and downloads are truly aborted via a cancel token).
- Fixed: labels could not be assigned to or removed from existing cards (405) — label calls rewritten against the real Deck routes; board context priority fixed in card detail.
- Unified glass design: `GlassIconButton` in all navigation bars, new `GlassBackButton` on all sub-pages; version shown without build number.
- Details: `changelog/2.1.md`.

## [2.0]
- Complete "Liquid Glass" redesign (iOS 26 style): refractive floating tab bar with morphing indicator, glass popover board menu, glass FAB, pager pill, light-edged cards with tinted due badges and assignee avatars, redesigned Overview/Upcoming/Settings/Card detail, board-color accent across the whole chrome, iPad grid up to 4 columns.
- Edit PDF attachments in-app (native Markup: draw, sign, annotate) and attach the result as a new version with an auto-suffixed filename (#77/#86.3).
- File upload fixed for current Deck servers (missing required `data` parameter; hardened with timeouts, duplicate protection, fallback routes) (#83, #86.2).
- Configurable due-date reminder lead times from 15 minutes to 1 week (#73); "No due date" bucket in Upcoming (#84); Enter continues checklists (#82).
- Fixes: done cards no longer flagged overdue (#75), PDFs open on iPad (#78), no accidental card moves while scrolling (#70, #85), person filter in wide iPad layout (#87), hidden boards excluded from Upcoming everywhere, instant card open from Upcoming, reliable credential storage on fresh installs (#69).
- Sync: parallel boot sync, official lightweight `/reorder` endpoint, per-board error isolation (a failing board can no longer wipe cached cards), hidden boards skipped in delta refresh.
- Platform: UIScene lifecycle migration (required by upcoming iOS versions), deep links via SceneDelegate.
- Details: `changelog/2.0.md`

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
