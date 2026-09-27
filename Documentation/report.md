# All Set — Wallpaper Library: report

Read only the CURRENT STATE block at the start of a session. HISTORY is a terse
log; it never needs reading in full.

---

## CURRENT STATE
_(overwritten every checkpoint — 2026-09-27, scenes rendered with their own shaders)_

### Working right now (verified only)
- **409 wallpapers — 318 live, 91 stills**, across two source folders
  ("Steam Wallpapers" 169, "wallpaper phase 1 data" 240). Both source
  folders are now **deleted from this Mac** (pendrive already gone; the
  dataset folder deleted this checkpoint after verification).
- **Scenes render with their own shipped shaders**, not invented motion.
  `scripts/wescene.swift`: offscreen OpenGL, runs each scene's own GLSL
  (masks, flow maps, keyframe tracks, sprite frames, transform hierarchy with
  rotation, alignment, colour/brightness), composites, writes a still and,
  if anything moves, a seamless HEVC loop.
- **Verified:**
  - 409/409 unique ids, 0 duplicates; the 169 original items completely
    unchanged (playback paths identical) after the second folder's import.
  - 409/409 resolve to a file on this Mac; 0 orphaned library files.
  - 209/209 locally-made videos play (`playcheck.swift`).
  - **The dataset folder's absence was proven, not assumed**: renamed away,
    app rebuilt and rendered — "318 live, 91 stills, kept on this Mac", no
    warning — then the folder was permanently deleted.
  - 206 tests pass, 0 build warnings, Dock app rebuilt and relaunched.
  - Motion threshold recalibrated per-scene (most-changed 10x10 block, not
    whole-frame average): static-picture noise floor 0.33, threshold 1.0.
- **1 item dropped vs the previous (whole-layer-slide) renderer**: the Senna
  scene, now correctly excluded — its animation is SceneScript code, which
  the old renderer's guesswork happened to produce *something* for; the new
  renderer reports it honestly as unsupported instead.

### Files touched this checkpoint
- `scripts/wescene.swift` — new: the shader-accurate scene renderer.
- `scripts/wallpaper_library.py` — `SceneNormaliser`, `plan_loop`,
  `render_scene`, `inspect-scene`/`render-scene` CLI commands; old
  whole-layer-slide compositor removed.
- `Documentation/spec.md`, `architecture.md` — R3/R7 rewritten; renderer
  decisions and rejected alternatives logged.
- `Documentation/scene-renderer-diagnosis.md` — the Phase 1 diagnosis.

### Commit
`b7e5f4c` and the commits before it this session, on branch `perf-audit`.
This checkpoint's commit follows immediately after.

### Known issues / blockers
- ~30 cosmetic effect shaders (chromatic aberration, vignette, sharpening,
  a few others) fail to compile against the GLSL 1.20 prelude; that one
  effect is skipped on its layer, everything else in the scene still renders,
  and it's reported per scene.
- Particles, on-screen text, sound, 3D models and audio-reactive effects
  (silent state) still don't carry over — unchanged, expected (spec non-goal).
- The 169 scenes imported from the now-gone pendrive keep their **old**
  (whole-layer-slide) loops; they can't be re-rendered without the source.
  Not a regression — they still play — just not upgraded.
- The library is now **36 GB** in Application Support, 54 GB free on disk.
- Everything from the previous checkpoint's Known Issues still applies
  (fast-scroll hitches; F15 seconds-clock decision; merging `perf-audit`).

### Next step
User is about to provide a third data source. Read this CURRENT STATE block
only; no re-scan needed. Same pipeline applies unchanged.

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
