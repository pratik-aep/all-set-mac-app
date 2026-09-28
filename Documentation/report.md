# All Set — Wallpaper Library: report

Read only the CURRENT STATE block at the start of a session. HISTORY is a terse
log; it never needs reading in full.

---

## CURRENT STATE
_(overwritten every checkpoint — 2026-09-29, personal-server fetch feature)_

### Working right now (verified only)
- **1164 wallpapers — 1006 live, 158 stills**, self-contained on this Mac
  (~12 GB of actual playback assets in `live/`+`stills/`+`thumbnails/`).
  Fourth source folder merged this session (465 new); an R1 gap (silently
  dropped interactive wallpapers) and 11 blank/broken scene renders were
  found and fixed — see HISTORY for detail, not repeated here.
- **A personal home server is fully stood up and proven, end to end:**
  a second Mac, reachable only over Tailscale (never the public internet).
  - Postgres (`allset` db) holds a full copy of the catalog metadata —
    1164/1164 rows verified, reachable only through an SSH tunnel
    (`scripts/cloud/tunnel.sh`), password in this Mac's Keychain, synced
    with `scripts/cloud/sync_catalog.py` (one-way, run by hand after real
    changes — not automatic).
  - Caddy serves the actual files (`live/`, `stills/`, `thumbnails/`, 12.2
    GB, 2611 files) at `http://100.71.191.101:8080/`, plain HTTP (Tailscale
    already encrypts the transport), verified reachable and byte-identical
    to the local copies.
  - Server won't sleep (`pmset sleep 0`, found and fixed a config that had
    only been set to 1 minute despite being asked for 0).
- **The app can now fetch a missing wallpaper back from that server**,
  proven with a real deleted-and-refetched file (SHA-256 identical), not
  just a mock:
  - `WallpaperConfig.libraryServerURL` (nil by default — R2 holds exactly as
    verified when it's unset).
  - `WallpaperStore.fetchLibraryVideo(id)`: local/reachable-root check first
    (never touches the network when it doesn't need to), else downloads
    from the server into the *same relative path* it lives at locally, so
    every other resolution method sees it as an ordinary local file
    afterward. Mirrors `AerialCatalog.download`'s shape exactly.
  - `checkServerReachable()`: cached, age-gated probe (mirrors
    `StatusService`), so the Library grid never does a network call per card.
  - `WallpaperView`'s `.library(id)` case triggers a fetch automatically
    when a wallpaper is set as active but missing locally; `LibraryTile`
    shows "Fetch from Server" instead of "Drive Not Connected" when the
    server can help.
  - **Deliberately not built yet:** any way to actually delete a local copy
    to free space. That's the natural next step now this is proven, not
    bundled in — agreed with the user before starting.
- 210 tests pass (3 new: already-local skips the network, a successful
  fetch lands at the right path with the right bytes, a failing server
  throws and leaves no partial file — all against a stubbed `URLProtocol`,
  serialized so parallel test runs can't stomp the shared stub). 0
  warnings, Dock app rebuilt and relaunched.

### Files touched this checkpoint
- `Sources/AllSetCore/Wallpaper/WallpaperStore.swift` — `libraryServerURL`,
  `fetchLibraryVideo`, `checkServerReachable`, `fetchSession` (instance
  property, deliberately not `static` — see architecture.md).
- `Sources/AllSet/Wallpaper/WallpaperController.swift` — fetch trigger in
  `WallpaperView`'s `.library` case.
- `Sources/AllSet/Wallpaper/WallpaperPages.swift` — `LibraryTile`/
  `LibrarySection` messaging for "recoverable from server" vs. truly gone.
- `Tests/AllSetCoreTests/WallpaperLibraryTests.swift` — `StubURLProtocol`,
  `LibraryServerFetchTests`.
- `scripts/cloud/tunnel.sh`, `push_wallpapers.sh`, `sync_catalog.py`,
  `schema.sql` — the server-side half of this (all from earlier this
  session, now proven, not just written).
- `Documentation/architecture.md`, `report.md` — this feature, decisions.
- Two live, outside-the-repo changes with no commit: `wallpaper.json` now
  has the real `libraryServerURL` set; one wallpaper's local copy was
  deleted-then-refetched as the real proof (back where it started).

### Known issues / blockers
- **Pre-existing ~700 items from the other two source folders** still lack
  both the crossfade fix and the blank-render check (see prior HISTORY).
  Needs the old "KALI LINUX" drive reconnected, or a new code path that
  re-renders from this Mac's own `originals/` copies.
- The remaining ~34 (of 45) near-duplicate flags from the fourth-dataset
  import weren't reviewed past the sample checked last checkpoint.
- `WallpaperConfig.libraryServerURL` has no settings UI — set once, by hand,
  directly in `wallpaper.json`. Fine for one person, one server; would need
  real UI before this could ever be anything else.
- The SSH key used for the tunnel/push has no passphrase (needed for
  unattended sync) — anyone with disk access to this Mac could use it.
- Not carried: SceneScript code, particle turbulence/vortex/mouse
  attraction, event-spawned child particles, text, 3D models, audio input,
  ~30 cosmetic effects in HLSL-only syntax; all reported per scene.

### Next step
Awaiting the user: build the actual "delete a local copy to free space"
action (now safe to, with fetch proven), re-render the pre-existing library
under the fixed renderer, review the remaining near-duplicate flags, or
something else entirely.

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
