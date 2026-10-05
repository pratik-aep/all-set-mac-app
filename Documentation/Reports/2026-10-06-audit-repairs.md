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
