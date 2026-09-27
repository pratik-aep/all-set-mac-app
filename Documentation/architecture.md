# All Set — Wallpaper Library: architecture

_Living document. The moment implementation forces a deviation, this file is
updated in the same checkpoint and the deviation is logged in `report.md`.
Code and docs are never allowed to disagree._

_Last updated: 2026-09-27 (phase-1 dataset merged in)._

## Stack, and why
| Piece | Choice | Why |
|---|---|---|
| App | Swift 6, SwiftUI + AppKit | Matches the rest of All Set. |
| Playback | AVFoundation via the existing `LoopingVideo` | Hardware decoding and the pausing rules already exist; adding a player would be a second engine (spec R5). |
| Import | Python 3 (`/usr/bin/python3`) + ffmpeg | Offline, one-off work. Keeping it out of the app keeps the app free of new dependencies. |
| Texture decoding | Swift (`scripts/wetex.swift`), compiled once | Needs DXT/LZ4 and ImageIO; ships as source, built on demand. |

**Division of labour:** everything expensive and one-off happens at import;
the app only plays a file. This is why 408 wallpapers, from two separate
source folders, cost the app nothing beyond one video.

## Where things live
```
scripts/
  wallpaper_library.py   inventory + import: scenes, web, video, live loops
  wetex.swift            Wallpaper Engine .tex decoder (built to Library/bin/)
  playcheck.swift        does AVFoundation really play this file?
Sources/AllSetCore/Wallpaper/
  WallpaperLibrary.swift LibraryVideo, WallpaperLibraryCatalog, LibrarySort
  WallpaperStore.swift   owns the catalog; resolves a wallpaper to a URL
Sources/AllSet/Wallpaper/
  WallpaperController.swift  plays it (LoopingVideo / MovingStill)
  WallpaperPages.swift       LibrarySection, LibraryTile
~/Library/Application Support/AllSet/Wallpaper/Library/   (not in the repo)
  catalog.json  originals/  live/  stills/  extracted/  transcoded/
  thumbnails/   scenes.json  bin/wetex  import-report.json
```

## Data model
`LibraryVideo` — one wallpaper.
- `id`: first 16 hex of the content SHA-256. Identity survives renaming (R6).
- `kind`: `.video` (plays) or `.image` (a still that drifts). Missing ⇒ video.
- `root` + `file`: **provenance only** — where it came from. After R2 this is
  history, not a dependency.
- `playback`: the file on this Mac that actually plays. **The only path that
  matters at run time.**
- `status`: `quarantined` (default) / `published` / `unsupported`. Unknown
  values decode as `quarantined` — the safest reading (R4).

Decoding is deliberately tolerant: one unreadable entry is skipped, not fatal.

### Resolution rule (the heart of R2)
`WallpaperStore.libraryURL(id)`:
1. If `playback` exists on disk → use it. **Always wins.**
2. Otherwise, only for a video, fall back to `root + file` if reachable.
3. Otherwise nothing, and the caller shows the default wallpaper.

`canPlay` mirrors this without touching the disk, so grid cards never stat files.
After `--self-contained` every item has step 1, so step 2 is dead weight kept
only for a library imported without copying.

## How a scene becomes a wallpaper
```
scene.pkg ─▶ layers + scene.json ─▶ is there an MP4 inside?  ─yes─▶ extract
                                 ─▶ is it a GIF scene?       ─yes─▶ frames → loop
                                 ─▶ otherwise: composite layers
                                       │
                                       ├─ has depth/effect motion? ─▶ compose_live()
                                       │     └─ frame_movement() ≥ 0.8? ─▶ live/*.mp4
                                       │                          else  ─▶ keep still
                                       └─ no motion ─────────────────────▶ stills/*.jpg
```
Motion is rebuilt from the scene's own `parallaxDepth` and effect settings
(`ui_editor_properties_speed`, `_strength`). Every term runs a whole number of
cycles per loop, so the loop is seamless; the frame is drawn 6% oversized and
cropped so moving layers never uncover an edge.

## Design decisions, and what was rejected
| Decision | Rejected alternative | Why |
|---|---|---|
| Bake motion to a video at import | Animate layers live with Core Animation | 22 layers × 4K RGBA ≈ 730 MB of memory and per-frame GPU compositing; hardware HEVC decode is cheaper and needs no new app code. |
| Keep a still unless motion is measured | Convert every scene with any motion data | A loop is softer than a 4K still and runs the decoder; 16 scenes failed the measurement and stayed sharp. |
| Copy originals byte-for-byte | Transcode them to save space | Copying is lossless and cannot change playback; these already decode in hardware. |
| Skip broken scenes by Workshop id, with reasons | Guess from a preview-image hash | Previews are square crops, zoomed, or start on a black frame; a hash cannot tell. Judged by eye instead. |
| Identity from content hash | Path or Workshop id | Files get renamed and moved; content does not. |
| Cross-root dedup by id, not just by root | Filter `kept` by root only | A second source folder can share content with the first (12 items did); filtering by root alone left both copies in `catalog.json` with the same id — a duplicate `Identifiable` for SwiftUI's `ForEach`. Fixed in the merge step itself, not worked around per-root. |

## Open assumptions to confirm
1. **~10 GB in Application Support is acceptable.** It is the price of R2.
2. **2560 px, 15 s loops** are the right quality/size point.
3. **Motion threshold 0.8/255** is the right line between loop and still.
4. Whether `perf-audit` should be merged to `main` and pushed.
