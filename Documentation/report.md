# All Set — Wallpaper Library: report

Read only the CURRENT STATE block at the start of a session. HISTORY is a terse
log; it never needs reading in full.

---

## CURRENT STATE
_(overwritten every checkpoint — 2026-09-28, particles + duplicates)_

### Working right now (verified only)
- **753 wallpapers — 608 live, 145 stills**, after removing 24 duplicates.
  All resolve to a file on this Mac; 361/361 scene videos play.
- **Scene loops are now alive, not flat.** Root cause of the flat loops:
  particle systems (rain, snow, embers, dust, fog — used by 60% of scenes)
  weren't rendered at all. Now simulated from each scene's own settings,
  looping exactly. Also fixed, each found by comparing against previews:
  - multi-pass effects (god rays, shine, blur) fed wrong geometry → now each
    pass gets the quad its own shader expects;
  - keyframes read as absolute values → they are offsets on the base value
    (layers with animated scale/position were vanishing);
  - single-channel sprites drawn as squares → brightness is their alpha;
  - refracting raindrops drawn as white squares → they bend the scene behind;
  - scenes with a small video inside (loading intros) taken as "just that
    video" → only full-scene videos are, the rest render normally.
  Result on the drive's dataset: 427 → 420 live after the stricter motion
  bar, up from 393; random samples match their Workshop previews.
- **Duplicates removed: 24**, reviewed by eye (same picture, or same subject
  in a different colour/background). Recorded in `removed.json`; re-imports
  skip them. Same background with a different car is kept.
- 206 tests pass, 0 warnings, Dock app rebuilt and relaunched.

### Files touched this checkpoint
- `scripts/wescene.swift` — particles, refraction, R8 sprites, additive
  keyframes, per-shader pass geometry, pass-dump debugging.
- `scripts/wetex.swift` — reports texture format.
- `scripts/wallpaper_library.py` — particle normalisation, sprite stand-ins,
  render time limit, full-scene-video rule, `removed.json` +
  `remove-duplicates`, stricter motion bar (2.0).
- `scripts/lookalike.swift` — Vision feature-print duplicate candidates.
- `Documentation/spec.md` (R7 bar, new R8), `architecture.md`.

### Known issues / blockers
- 163 scenes came only from the deleted "phase 1" folder: they keep their
  previous render (shaders, no particles) and can't be upgraded without that
  data. 8 older pendrive-era loops likewise.
- Not carried: SceneScript code, particle turbulence/vortex/mouse
  attraction, event-spawned child particles, text, 3D models, audio input,
  ~30 cosmetic effects in HLSL-only syntax; all reported per scene.
- Engine particle sprites are generated stand-ins by family (documented).

### Next step
Awaiting the user.

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
