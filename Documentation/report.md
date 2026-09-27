# All Set — Wallpaper Library: report

Read only the CURRENT STATE block at the start of a session. HISTORY is a terse
log; it never needs reading in full.

---

## CURRENT STATE
_(overwritten every checkpoint — 2026-09-28, third dataset merged)_

### Working right now (verified only)
- **776 wallpapers — 597 live, 179 stills**, across three source folders:
  "Steam Wallpapers" (partly superseded), "wallpaper phase 1 data" (240),
  "all_set_mac" (516 new). All self-contained; no source folder is required
  to play, preview or set any wallpaper.
- **23 items automatically upgraded**: their exact content (same SHA-256)
  reappeared in the new dataset, so they were re-rendered with the current
  shader-accurate renderer instead of staying on the old pendrive-era
  whole-layer-slide version. Several also had their still/live classification
  corrected by the better motion measurement (e.g. "Bloodborne" was
  incorrectly live before, correctly a still now).
- **Verified:**
  - 776/776 unique ids, 0 duplicates; 0 items missing vs. the pre-import
    snapshot; 0 orphaned library files.
  - 776/776 resolve to a file on this Mac.
  - 379/379 locally-made videos play (`playcheck.swift`).
  - 24 newly-imported scenes sampled at random and checked against their
    Workshop previews: 22 clear matches, 1 correctly-dark scene (literally
    titled "Black Hole"), 1 ambiguous icon-style scene. No regressions found.
  - **Drive absence proven for real**: the pendrive was unmounted (confirmed
    gone from `diskutil list`), the app rendered in full — "597 live, 179
    stills, kept on this Mac", no warning — then remounted untouched (nothing
    on it was deleted; the user didn't ask for that this time).
  - 206 tests pass, 0 build warnings, Dock app rebuilt and relaunched.
- Disk: this dataset needed ~41 GB of video copied against ~54 GB free —
  tight but completed cleanly; 26 GB free afterward, library now 76 GB.

### Files touched this checkpoint
- No code changes. Same pipeline as the previous checkpoint
  (`scripts/wescene.swift`, `scripts/wallpaper_library.py`) applied unchanged
  to a third source folder.

### Commit
`991f4fc` and the commit immediately following this one, on branch `perf-audit`.

### Known issues / blockers
- 282 near-duplicate pairs flagged this round (up from ~15-25 before) — not
  reviewed individually; expected given ~150 items overlapped by Workshop id
  with earlier folders and the dhash is known to false-positive on dark,
  centred-subject art (documented limitation, unchanged).
- Everything from the previous checkpoint's Known Issues still applies
  (cosmetic-shader compile gaps; particles/text/sound/3D/audio not carried;
  fast-scroll hitches; F15 seconds-clock decision; merging `perf-audit`).

### Next step
Awaiting the user; no pending source folders. If more data arrives, same
pipeline, same verification sequence — no re-scan needed.

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
