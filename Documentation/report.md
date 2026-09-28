# All Set — Wallpaper Library: report

Read only the CURRENT STATE block at the start of a session. HISTORY is a terse
log; it never needs reading in full.

---

## CURRENT STATE
_(overwritten every checkpoint — 2026-09-29, fourth dataset + crossfade fix)_

### Working right now (verified only)
- **1178 wallpapers — 1008 live, 170 stills**, self-contained on this Mac
  (~12 GB of actual playback assets in `live/`+`stills/`+`thumbnails/`;
  `originals/` and pipeline scratch aren't needed to play one).
- **Fourth source folder merged** ("all_set_mac" on a new drive, "Nithin J"):
  371/374 scenes imported, 94/96 plain videos, 465 wallpapers added this
  round. 6 skipped with reasons (2 corrupt source files, 2 unsupported
  effects, 1 unreadable GIF, 1 already removed by the user). 45
  near-duplicates flagged for review, not yet resolved.
- **User-delete feature verified for real**, not just by test: an item
  deleted from the app last checkpoint (`3633951606`) came up in this
  content-matching drive as a duplicate and was correctly skipped on
  re-import — `removed.json` is doing its job end to end.
- **Loop crossfade bug fixed** (see previous checkpoint) applies to every
  scene rendered in *this* import, since `SCENE_RENDERER` bumped to 9. It
  does **not** yet apply to the pre-existing ~753 items from the other two
  source folders — `import <folder>` only re-renders scenes physically
  present in the folder it's given, not the whole catalog. Confirmed by
  reading the code, not assumed.
- 207 tests pass, 0 warnings, Dock app rebuilt and relaunched.

### Files touched this checkpoint
- `Documentation/spec.md` — current numbers, last-updated line.
- No code changes this checkpoint (import + doc sync only); crossfade fix
  and delete button were previous checkpoints, both now exercised on real
  data for the first time.

### Known issues / blockers
- **Pre-existing library still has the crossfade flash bug.** Fixing it
  needs either the old "KALI LINUX" drive reconnected (currently unmounted)
  to re-run `import` against it, or a new code path that re-renders straight
  from this Mac's own `originals/` copies instead of an external drive.
  Neither started yet.
- 45 near-duplicates from this round awaiting human review (not applied).
- Not carried: SceneScript code, particle turbulence/vortex/mouse
  attraction, event-spawned child particles, text, 3D models, audio input,
  ~30 cosmetic effects in HLSL-only syntax; all reported per scene.
- Engine particle sprites are generated stand-ins by family (documented).

### Next step
Cloud sync groundwork is in progress in parallel (Postgres + object-storage
accounts being created by the user; schema and sync script already written
in `scripts/cloud/`, untested — no credentials yet). Awaiting the user for
which to do first: review the 45 near-duplicates, re-render the pre-existing
library under the fixed renderer, or continue the cloud-sync setup.

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
