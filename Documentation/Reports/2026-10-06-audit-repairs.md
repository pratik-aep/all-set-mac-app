# Audit repairs, 2026-10-06

Repairs from the independent audit of 6 October, in its suggested order. Local commits only (git initialised this session; nothing pushed).

## Done
| Phase | Audit # | What changed | Verified by |
|---|---|---|---|
| 1 Layouts | 1, 2 | Picking a wallpaper keeps widgets. A theme preview is written to `desktop-preview.json` before the desktop changes, reverted on quit, restored at launch after a crash. Every whole-desktop change keeps `previous-desktop.json`; Widgets › Restore Previous Desktop. | `DesktopJournalTests` (4) |
| 2 Delete/offload (app) | 10, 13 | Delete Everywhere asks the server first; local copy removed only on 200/404; `pending-deletes.json`; failures delete nothing and retry works. Offload frees a file only if the server copy has the same SHA-256 (downloaded and hashed), after `offloaded.json` is written and read back. | `WallpaperLibraryTests` (retry, 404, same-size different content, unrecordable offload) |
| 2 Delete (server) | 11, 12, 15 | `delete_service.py` decides files from the id (`<folder>/<id>.*` + unshared DB keys), ignores request paths, stages through `.trash/<id>/`, restores on database failure, settles quarantines at startup, bounds requests. | `test_delete_service.py` (11, real Postgres) |
| 2 Catalog API | 15, 16, 17 | Only `published` listed/served unless `--include-quarantined`; binds the Tailscale address (or `--host`); psql timeouts, 503s, Range/206. | `test_catalog_service.py` (6) |
| 3 Catalog sync | 14 | Storage keys left out of the upsert; CSV line endings fixed (COPY failed on psql 17). | `test_sync_catalog.py` (3); reproduced `After|||` first |
| 4 UI | 5, 6, 7, 8, 9 | ⌘1–⌘5 in `CinemaNavigation`; weather from an existing city or the time zone, not London; calendar on the desktop shows events; Delete offers Remove Download / Delete Everywhere everywhere, filter renamed On This Mac; tiles keyboard/VoiceOver-usable (`KeyboardActivatable`); Trending/Popular shown as Recommended/Top Picks. | Build; `-renderPages -pages wallpaper,themes` |
| 5 Release | 22, 24, 25 | Missing TCC symbol → `.unverifiable`, not authorized; render harness fails on a partial set (`render-report.txt`); probe `pipefail`; CI job for server tests; personal server address out of `Info.plist` (build-app.sh injects it from `ALLSET_LIBRARY_SERVER_HOST` / `scripts/local.env`). | build-app.sh run + PlistBuddy |
| 6 Cleanup | 26 | Removed unused `FloatingNav` (and its private helpers) and `ClassicGalleryPage`. | Build, tests |

Totals at the end: 353 Swift tests, 20 server tests, 0 warnings.

## Not done (needs a decision or more than a code change)
- **#3, #4 navigation and visual hierarchy**: a product redesign of the Desktop section; not attempted without design direction.
- **#18, #20 coordinator and narrower dependencies**: only the durable desktop journal was added; AppServices and WidgetOptions were not restructured.
- **#19 stable display identity**: fixed in an earlier session, but that work was lost when the folder was replaced; not redone here.
- **#21 clipboard history default**: a privacy default change; not changed.
- **#23 app-level integration tests** (quit during a preview, end to end): core-level tests only.
- **#25 notarisation pipeline**: needs a Developer ID; not set up.

## Operational notes
- After restarting `catalog_service.py`, a tester sees only published wallpapers: the library is all quarantined, so start it with `--include-quarantined` to keep the current behaviour for your own tester.
- `delete_service.py` now ignores `paths`; older app builds still work against it.
- Server tests: `/usr/bin/python3 -m unittest scripts/cloud/test_*.py` (needs `brew install postgresql@17`).

## Comprehensive review (2026-10-06): status register

Findings from `2026-10-06-comprehensive-review.md`. Every fixed item has a test that failed (or would fail) on the earlier code.

| # | Finding | Status | Commit |
|---|---|---|---|
| R1 | Redaction not authoritative | Fixed | `7616c7f` |
| R2 | AI answer lands in the wrong screenshot | Fixed (late reply dropped; the request itself isn't cancelled) | `3734315` |
| R3 | Audio gain data race | Fixed (atomic helpers; ThreadSanitizer clean) | `8f91b43` |
| R4 | Shelf ownership by string prefix | Fixed (`ContainedPath`) | `4ead711` |
| R5 | Local wallpaper delete escapes the library | Fixed (rejected at load and at every delete/write) | `4ead711` |
| R6 | Server deletes a file another row uses | Fixed | `59f5d70` |
| R7 | Rollback discards an original on collision | Fixed (kept as a conflict) | `59f5d70` |
| R8 | Preview journal retired without confirmed save | Fixed | `9df2319` |
| R9 | Unreadable importer catalog triggers cleanup | Fixed (stops; cleanup moves to `.orphans/`) | `5c9ec48` |
| D1 | Clipboard history on by default | **Open: product decision** | |
| D2 | Pending capture after Clear/Turn Off | Fixed | `d84af1e` |
| D3 | GitHub cache not scoped to credential | Fixed (token fingerprint; external Keychain edits not detected) | `0a922e1` |
| D4 | Key replacement deletes first | Fixed (failure path verified by reading, not by test) | `48e612f` |
| D5 | Unreadable widgets erased by save | Fixed | `ea52076` |
| D6 | Inconsistent save-failure semantics | Fixed for user data: local delete, Notes, widgets, clipboard, shelf, workspaces and wallpaper settings each expose `saveError` until a save works; the main window lists them in one banner with Try Again. Still open: the review's export/restore backup format (a feature, not a fix) | `1b323e2`, see log |
| P2 | Screenshot history by count only | Fixed (600 MB byte budget) | `3734315` |
| P1 | Focus-timer completion owned by a view | Fixed (`FocusTimerCoordinator` in AppServices) | see log |
| P7 | Command timeout not an upper bound | Fixed (TERM, then KILL; bounded drain and output; task cancellation) | see log |
| P5 | Weather/GitHub retried every minute after failures; fetches outlived their widgets; stale data hidden | Fixed (`RetryBackoff` per key and credential, 401 waits longest; `SharedRequests` cancels a fetch once every waiting widget left; forecast and air errors kept apart; `WidgetStaleBadge` shows age and why) | see log |
| P6 | Status check identity lowercased whole URL | Fixed (only scheme and host fold case; path and query keep theirs) | see log |
| P4 | 20 Hz pointer timer ran with no widgets or all covered | Fixed (`NeededTimer`: scheduled only while a widget is shown uncovered; not hand-measured) | see log |
| P3 | Image import on main, thumbnails via full decode | Fixed (import off main, 4 at a time, progress + Stop on My Photos, cancellable; small copies and the wallpaper file skip the full decode). Still open: a quota for the downloaded-photo cache, which needs to know which photos the wallpaper and widgets still use | see log |
| U3 | Toggles exposed by their explanation; unnamed icon buttons | Fixed (`SettingToggle`: name as label, explanation as hint, 9 sites; 10 icon-only buttons labelled). Not checked with VoiceOver running; contrast/Reduce Transparency matrix not done | see log |
| U4 | Notes removed for good | Fixed (Undo for remove, Clear Done and edit-to-empty, in place; Clear Done shows its count; pencil and Edit menu, VoiceOver actions) | see log |
| U5 | "On your server" without checking | Fixed (`copyLocation`: checked on server only when freed after a hash match; otherwise "to download from your server (not checked)") | see log |
| U6 | Copy promising more than the code | Fixed (Monitor keeps sampling slower; About; On This Mac help) | see log |
| U1, U2 | Navigation redesign; compact utility pages | **Open: design decisions** (layout changes not made without seeing them) | |
| A1–A4, O1–O6 | Architecture, workspace restore, display identity, platform testing, backend ops, tests, CI budgets, release, docs, import input bounds | Open | |
