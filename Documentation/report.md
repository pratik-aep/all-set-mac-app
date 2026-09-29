# All Set — Wallpaper Library: report

Read only the CURRENT STATE block at the start of a session. HISTORY is a terse
log; it never needs reading in full.

---

## CURRENT STATE
_(overwritten every checkpoint — 2026-09-29, library UI: sizes, preview fix, two deletes)_

### Working right now (verified only)
- **File size** shown on every tile and in the new detail sheet.
- **Preview, fixed at the root cause**: hover never fetches (silent, cheap,
  shows "tap to preview" if not local — was silently blank for almost the
  whole library after offloading); tap opens a new bottom-up
  `LibraryDetailSheet` (title, category, resolution, size, duration/fps,
  rights note, a bigger preview) which *does* fetch, same
  `fetchLibraryVideoRetrying` + progress bar already proven.
- **"Owned" filter**: chip next to All/Live/Stills — wallpapers with a
  local copy right now. Delete behaviour is decided by this filter, not the
  tile: Owned → offload only (`offloadAll(only: [id])`, stays on the server
  and in the catalog); everywhere else → permanent, admin-gated.
- **Permanent delete now reaches the database and the server**, not just
  this Mac. New `WallpaperStore.deleteEverywhere(id)`: local cleanup first
  (unconditional, already proven), then a call to a new server-side delete
  API. Gated by `AdminGate` (Touch ID, falling back to the Mac password —
  `LAContext`, first use of `LocalAuthentication` in this app) *before*
  either deletion runs.
- **New server-side `scripts/cloud/delete_service.py`**: stdlib
  `http.server`, bound to `127.0.0.1` on the server (not the Tailscale
  interface — reached only through the SSH tunnel, `tunnel.sh` now forwards
  its port too), bearer-token auth (`~/.allset_delete_token` server-side,
  this Mac's Keychain client-side via new `DeleteAPIKeychain`), rejects any
  path resolving outside `~/AllSetStorage/wallpapers/`. Three layers before
  anything is deleted: SSH key, bearer token, Touch ID.
- **Real end-to-end proof** (not just unit tests): built a genuine
  disposable wallpaper — real file, real catalog entry, real row inserted
  in Postgres, real file pushed to the server — then called
  `deleteEverywhere` for real and independently confirmed all four were
  gone (local file, catalog entry, server file, database row).
  **Not personally verified**: the Touch ID/password prompt itself — I
  can't complete a biometric or type the Mac's login password. The
  mechanics it gates are proven; the prompt appearing and working is for
  the user to confirm once.
- 227 tests pass (5 new), 0 warnings, app rebuilt and relaunched.

### Files touched this checkpoint
- `Sources/AllSet/Wallpaper/WallpaperPages.swift` — size, tap→detail sheet,
  `LibraryDetailSheet` (new), Owned chip, `LibraryTile.DeleteKind`,
  hover-preview fix.
- `Sources/AllSetCore/Wallpaper/WallpaperStore.swift` — `deleteEverywhere`,
  `deleteServiceURL`/`deleteServiceToken` (instance, overridable for tests).
- `Sources/AllSetCore/Support/AdminGate.swift`,
  `Sources/AllSetCore/Wallpaper/DeleteAPIKeychain.swift` — new.
- `scripts/cloud/delete_service.py` (new), `tunnel.sh` (second forward).

### Known issues / blockers
- `delete_service.py` isn't a launchd service yet — started by hand on the
  server; can become one later the way Caddy/Postgres were.
- Deleting the *active* wallpaper via `.permanent` still leaves it as the
  active source pointing at nothing (matches `deleteLibraryVideo`'s
  existing behaviour, not changed here) — falls back to default art.
- Offloaded wallpapers still need Tailscale + server; ~700 older ones still
  lack the crossfade fix and blank-render check; no settings UI for the
  server URL; the SSH key has no passphrase.

### Next step
Awaiting the user: try the real delete button once (Touch ID prompt is the
one thing not self-verified), or any of the known issues above.

---

## DRIFT AUDIT — 2026-09-27
Code checked against `architecture.md`, section by section.
- Library folders, catalog and resolution rule: **match.**
- `originals/` reuse and orphan cleanup: **match.**
- **One mismatch:** `HANDOFF.md` still said videos play from the drive.
  Chose to **fix the doc to match the code**, since the code is verified.
Result: no code changes needed; docs now agree with reality.

## HISTORY
- Wallpaper library: importer, catalog, playback — 48 videos imported — `5b54296`
- Wallpaper library: gallery, scale probe, no-regression checks — `7608ad4`
- Handoff and session report for the import — `1e633b1`
- Scenes and web wallpapers imported (181 total, 75 live/106 stills) — `5704a87`
- Scene stills rendered as moving loops (138 live/43 stills) — `f4c2072`
- Self-contained library; survives the source folder being deleted — `30e2479`
- Phase-1 dataset (239 items) merged; cross-root dedup fixed; 408 total, self-containment reverified with both source folders absent — 29f75a4
- Scene renderer diagnosis: pipeline invents motion and drops masks, keyframes, sprites, tints; options A/B/C awaiting decision — see scene-renderer-diagnosis.md — diagnosis only, no code change
- Scenes rendered with their own shipped shaders (wescene.swift); 409 total (318 live/91 stills); dataset folder deleted after verified self-containment — pending commit
- Third dataset (all_set_mac, 516 new items) merged; 776 total (597 live/179 stills); 23 items auto-upgraded to the shader renderer; drive unmounted+remounted to prove independence — pending commit
- Particles, refraction, keyframe offsets, multi-pass geometry fixed; 24 duplicates removed; 753 total (608 live/145 stills) — pending commit
- Core bug found and fixed: loop crossfade blended the head toward a
  mismatched future frame instead of easing the tail into the true head,
  causing a white/colour flash at the start of every replay on scenes whose
  content doesn't fit the loop exactly. Confirmed on 49/321 scene loops by
  direct measurement. Fix compiled; re-render needs the drive (unmounted at
  time of fix) reconnected — not yet re-verified against real output.
- Added a manual delete button (top-right, on hover, with a confirm step) to
  each Library tile: permanently deletes this Mac's own copies, records the
  id in removed.json so re-imports never bring it back, and edits catalog.json
  as raw JSON (not through the app's narrower model) so other wallpapers'
  importer-only fields (sha256, sceneNotes...) survive untouched. New test
  proves both the permanence and the no-data-loss property. 207 tests pass,
  0 warnings, app rebuilt.
- Fourth source folder merged (all_set_mac, new drive "Nithin J", 465 new
  wallpapers); 1178 total (1008 live/170 stills); delete-button removal
  verified against real duplicate content; crossfade fix confirmed applying
  to new renders, pre-existing library still needs it — pending commit
- R1 gap fixed: a workshop item with no video and no scene package (pure
  interactive HTML/JS wallpapers) vanished with no reason logged anywhere.
  Found by checking "is everything from the pendrive actually there" against
  the raw folder, not assumed. Now every non-scene item either imports or
  gets a skip reason; 10 previously-silent items on the current dataset now
  correctly recorded as unsupported (interactive wallpapers, a documented
  non-goal) — pending commit
- Quality pass on the fourth dataset: R1 gap fixed (interactive/web items
  now logged, not silently dropped); is_blank() rejects scenes that render
  solid black or near-blank (3D-model dependency, usually); 11 already-blank
  items removed by hand after eye-checking the near-duplicate flags; 1164
  total (1006 live/158 stills); SCENE_RENDERER 9->10
- Personal home server stood up and fully proven: Tailscale + SSH key auth,
  Postgres metadata sync (1164 rows) via tunnel + Keychain password, Caddy
  serving 12.2GB/2611 files verified byte-identical, server sleep bug found
  and fixed. App-side fetch built: WallpaperStore.fetchLibraryVideo mirrors
  AerialCatalog's download shape, checkServerReachable mirrors StatusService,
  wired into WallpaperView's .library case and LibraryTile's messaging.
  Proven with a real delete-then-refetch (SHA-256 identical), not a mock.
  210 tests pass (3 new, stubbed URLProtocol, serialized). Delete-to-free-
  space deliberately not built yet, by agreement.
- Server-fetch feature proven in the real .app, not just swift test - found
  and fixed 3 real bugs invisible to the test suite: async library-load race
  (task never retried), a successful fetch not triggering a redraw
  (observed an ignored property), and App Transport Security silently
  blocking plain HTTP in a real bundle. Also found extracted/+transcoded/
  (70 wallpapers' real playback files, 7.9GB) were missing from the server
  backup entirely - pushed, now complete. Deleted the live desktop
  wallpaper's actual file and watched the running app recover it in ~12s,
  byte-identical. 211 tests pass, 0 warnings.
- Local copies made optional: thumbnails fetchable, offloadAll frees a
  playable file only after the server confirms an identical copy (HEAD +
  Content-Length), "Free Up Space…" in the Library. Real test: 4 files /
  119 MB freed from 3 real wallpapers, one fetched back by the running app
  in ~4s byte-identical. Full-library run left for the user. 216 tests.
- Full-library "Free Up Space" run for real, by explicit go-ahead: freed
  1509 files / 18.7 GiB, verified independently (disk free space, folder
  sizes, catalog/removed.json byte-identical, one freed wallpaper fetched
  back live in ~4s). Found a new real gap in the process: 294 wallpapers
  whose playback file lives under originals/ (never backed up) - the
  safety check correctly kept them rather than deleting unconfirmed
  copies. ~52GB there still has no off-Mac backup. 216 tests, no code
  changes this checkpoint (docs + the real run only).
- Audit findings fixed: retrying/shared/cancellable fetch, importer honours
  offloaded.json, active wallpaper never freed, system still refreshed after a
  late fetch, file work off the main thread. Proven in the real app with the
  server stopped at launch. 224 tests.
- originals/ pushed (280 files, 52.5 GB, verified by name+size) and freed:
  AllSet folder 797 MB, free disk 50 -> 98 GiB; one fetched back live.
- Per-wallpaper download progress bar (Library grid tiles + the desktop
  wallpaper itself): real % while a fetch is under way, replacing a bare
  spinner/nothing. Root cause of the user's "fetch not applying" report:
  clicking several tiles quickly cancels each fetch for the previous one
  (by design - correct), with zero feedback to show it was working at all.
  New WallpaperStore.fetchProgress(for:) is a plain, non-observed read;
  each view polls it on its own 150ms timer only while isFetching(id) is
  true, so redraws stay local to the one downloading tile. Verified against
  the real server: a 68 MB wallpaper landed byte-exact after hitting (and
  correctly recovering from) the async-load race on its first attempt.
  225 tests pass, 0 warnings.
- Library UI: file sizes shown, hover-preview root cause fixed (never
  fetched; now hints "tap to preview"), new bottom-up LibraryDetailSheet,
  Owned filter, two deletes (offload-only vs permanent+admin-gated).
  New server-side delete_service.py (localhost-only, tunnel+token+TouchID).
  deleteEverywhere proven for real: disposable wallpaper with a real DB
  row and server file, deleted, confirmed gone from all four places
  independently. Touch ID prompt itself not self-verified (physical
  limitation). 227 tests.
