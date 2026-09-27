# All Set — Wallpaper Library: report

Read only the CURRENT STATE block at the start of a session. HISTORY is a terse
log; it never needs reading in full.

---

## CURRENT STATE
_(overwritten every checkpoint — 2026-09-27, phase-1 dataset merged)_

### Working right now (verified only)
- **408 wallpapers — 303 live, 105 stills**, merged from two source folders
  ("Steam Wallpapers", 181 items; "wallpaper phase 1 data", 239 new items).
  Measured: 408/408 unique ids, 408/408 resolve to a file on this Mac.
- **Both source folders can be gone at once.** Verified for real, not
  simulated: the pendrive was physically unplugged (confirmed absent from
  `diskutil list`) and the dataset folder was renamed out of the way; the app
  still rendered "303 live, 105 stills, kept on this Mac" with no drive
  warning and every thumbnail intact.
- **Cross-root duplicate-id bug fixed and verified** before the real import:
  12 items in the new folder were byte-identical to items already catalogued;
  a synthetic two-root test confirmed 1 unique id where the old code would
  have produced 2.
- Yesterday's 181 items: **0 missing, 0 with a changed playback path** after
  the merge (regression check against a pre-merge catalog backup).
- All 194 videos made by this importer play (`playcheck.swift`, 0 failures).
- **206 tests pass, 0 build warnings**, Dock app rebuilt and relaunched
  after the dedup fix.

### Files touched this checkpoint
- `scripts/wallpaper_library.py` — cross-root dedup fix (`kept` also excludes
  ids already produced by this run's `entries`).
- `wallpaper_dataset_inventory.md` — created (Phase 2 discovery output).
- `Documentation/spec.md`, `architecture.md` — numbers updated; the dedup
  decision logged in architecture's decisions table.

### Commit
`29f75a4` and the dedup-fix commit before it, on branch `perf-audit`.

### Known issues / blockers
- 2 genuinely new failure modes seen in this batch (not content judgments):
  - a 128×128 "GraspOfTheAbyss" scene has nothing drawable (looks like a
    cursor-icon reskin, not a desktop wallpaper) — correctly skipped, message
    is just terser than usual (empty reason detail).
  - "Halloween Cat" has one layer sized ~59334×33375px, far past the canvas —
    likely a texture-tiling scene Wallpaper Engine repeats rather than
    stretches, which this importer doesn't model. Skipped safely, not crashed.
  Neither is a regression; both are recorded in `import-report.json`. Left
  as-is rather than extending the compositor for one scene each.
- The library is now **~35 GB** in Application Support, 33 GB free on disk.
  Same trade as before, larger now; flagged, not hidden.
- Everything from the previous checkpoint's Known Issues still applies
  (rebuilt motion isn't Wallpaper Engine's; fast-scroll hitches over ~1,000
  cards; F15 seconds-clock decision; merging `perf-audit` to `main`).

### Next step
Nothing blocking. The user can safely delete both source folders/drives.
Optional: investigate the "Halloween Cat" oversized-layer case if more scenes
like it turn up in a future batch (not worth a fix for one item alone).

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
