# All Set — Wallpaper Library: report

Read only the CURRENT STATE block at the start of a session. HISTORY is a terse
log; it never needs reading in full.

---

## CURRENT STATE
_(overwritten every checkpoint — 2026-09-29, local copies made optional)_

### Working right now (verified only)
- **1161 wallpapers** in the catalog (1164 last checkpoint; the 3 fewer are
  the user's own deletions through the app's trash button — `catalog.json`
  and `removed.json` both last written at 05:01, before any of this
  checkpoint's work, and 24 `removed.json` entries read "removed by the user
  in the app").
- **Personal home server** (second Mac, Tailscale-only): Postgres holds the
  catalog metadata; Caddy serves all five playable folders (`live/`,
  `stills/`, `thumbnails/`, `extracted/`, `transcoded/`), verified complete.
- **Local copies are now optional, proven in the real app:**
  - `fetchThumbnail(id)` joins `fetchLibraryVideo(id)`; both go through one
    `fetch(relative:)`, in-flight work keyed by relative path.
  - `offloadAll(only:)` deletes a local playable file only after a `HEAD`
    on the server answers 200 with the identical size; anything unconfirmed
    stays. Catalog and `removed.json` untouched. Thumbnails kept.
  - "Free Up Space…" in the Library header: estimate → confirm → per-file
    progress → freed vs. kept.
  - **Real test, small scale:** 3 real wallpapers (a live loop + its still,
    a still-only image, an `extracted/` video), 4 files, 119 MB — all 4
    verified on the real server and freed; thumbnails kept; catalog
    entries intact; server still serving them. Then set the freed still as
    the active wallpaper in the running app: fetched back in ~4s,
    byte-identical. The original active wallpaper was restored after.
  - Two of those three (Abandoned City, Formula 1) are **still offloaded**,
    deliberately — that's the intended state now, and they come back the
    moment they're played.
- 216 tests pass (5 new: thumbnail fetch, video+thumbnail fetched at once
  without colliding, offload deletes only server-confirmed files and
  round-trips, offload without a server keeps everything, offload limited
  to some wallpapers). 0 warnings, Dock app rebuilt and relaunched.

### Files touched this checkpoint
- `Sources/AllSetCore/Wallpaper/WallpaperStore.swift` — `fetch(relative:)`,
  `fetchThumbnail`, `fetchProgress(for:)`, `offloadAll`, `offloadableSpace`,
  `offloadProgress`; `libraryCopies` now observed.
- `Sources/AllSet/Wallpaper/WallpaperPages.swift` — thumbnail fetch in
  `LibraryTile`; `FreeUpSpaceRow`; header/banner counts that know about the
  server.
- `Sources/AllSet/Wallpaper/WallpaperController.swift` — reads
  `fetchProgress(for:)`.
- `Tests/AllSetCoreTests/WallpaperLibraryTests.swift` — stub answers HEAD
  like a file server; 5 new tests.
- `Documentation/architecture.md`, `report.md`.

### Known issues / blockers
- **The full-library "Free Up Space" has not been run** — by design; it
  needs the user's go-ahead. Expected: ~20 GB of playable files freed,
  thumbnails (~34 MB) kept.
- Once offloaded, every wallpaper depends on Tailscale + the server being
  up. Off that network, a not-yet-played wallpaper shows the default art.
- Hovering a tile doesn't fetch, so an offloaded wallpaper has no motion
  preview until played once.
- The system-wallpaper still (Mission Control/lock screen) isn't refreshed
  when an active wallpaper finishes fetching — it keeps the last one.
- ~700 older wallpapers still lack the crossfade fix and blank-render check.
- `libraryServerURL` has no settings UI; the SSH key has no passphrase.
- The 24 wallpapers the user deleted in the app are still on the server
  (`push_wallpapers.sh` never deletes there, by design).

### Next step
Awaiting the user: run "Free Up Space…" on the full library (their call,
~20 GB), or any of the known issues above.

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
