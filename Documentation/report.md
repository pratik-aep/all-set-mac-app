# All Set — Wallpaper Library: report

Read only the CURRENT STATE block at the start of a session. HISTORY is a terse
log; it never needs reading in full.

---

## CURRENT STATE
_(overwritten every checkpoint — 2026-09-27)_

### Working right now (verified only)
- **181 wallpapers — 138 live, 43 stills.** Every one resolves to a file on
  this Mac. Measured: 181/181 local, 0 needing the source folder.
- **The library survives the pendrive being wiped.** Verified end to end by
  unmounting `/Volumes/KALI LINUX` and rendering the page: the gallery drew in
  full, thumbnails intact, header read "138 live, 43 stills, kept on this Mac",
  and no drive warning appeared. The volume was remounted afterwards.
- **63 scene stills play as seamless loops** rebuilt from their own parallax
  depths and effect settings. Measured: loop seam 0.000/255; all 63 pass
  `playcheck.swift`; all 63 first frames reviewed on contact sheets.
- **16 scenes measured as barely moving stayed sharp stills** (threshold 0.8/255).
- **206 tests pass, 0 build warnings**, Dock app rebuilt from this branch.

### Files touched this checkpoint
- `scripts/wallpaper_library.py` — `--self-contained`, `originals/` reuse and cleanup.
- `Sources/AllSet/Wallpaper/WallpaperPages.swift` — drive warning only when something needs it; corrected wording.
- `Tests/AllSetCoreTests/WallpaperLibraryTests.swift` — `copiedLibraryOutlivesTheFolderItCameFrom`.
- `Documentation/spec.md`, `Documentation/architecture.md`, `Documentation/report.md` — created.

### Commit
`30e2479` — Wallpaper library: make it self-contained. Branch `perf-audit`.

### Known issues / blockers
- The library is **~10 GB** in Application Support. Deliberate: it is the cost of independence.
- Rebuilt motion is not Wallpaper Engine's: layers move as wholes where the
  original warps the picture. Reads as gentle life, not an exact copy.
- A loop (2560 px video) is softer than the 3840 px still it replaced.
- 19 items could not be imported (3D scenes, interactive clips, effect-dependent
  scenes, 1 duplicate) — each with a recorded reason.
- Fast-scroll hitches (33–43 ms) over ~1,000 cards. Unchanged, pre-existing.
- **Waiting on the user:** the F15 seconds-clock decision; whether to merge
  `perf-audit` into `main` and push.

### Next step
The pendrive can now be wiped. After that, re-run the drive-absent check once
more for final confirmation, then decide on merging `perf-audit`.

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
