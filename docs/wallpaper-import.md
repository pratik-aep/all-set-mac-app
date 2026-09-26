# Importing a live-wallpaper library

Working log and final report. Numbers are labelled **[measured]** or **[reasoned]**, following `docs/perf-audit.md`.

## Phase 0: the existing architecture

What's already there, and what this import will reuse.

### Model
`WallpaperSource` (`AllSetCore/Wallpaper/WallpaperStore.swift`) has three cases:
- `.art(ArtPiece)`
- `.photo(ImageSource)`
- `.video(String)`: a file **name inside `~/Library/Application Support/AllSet/Wallpaper/Videos`**.

`WallpaperStore` owns:
- `config` (saved to `wallpaper.json`);
- the list of imported videos;
- `importVideos(from:)`, which **copies** each file into that folder.

On launch, a `.video` whose file is gone falls back to art.

### Catalogs
- `AerialCatalog` (`AllSetCore/Wallpaper/AerialCatalog.swift`): Apple's remote aerial videos, with `Aerial.Category` chips, downloaded into the same Videos folder as `aerial-*.mp4`.
- There's no catalog, search, favourites or recents for user videos. My Videos is a flat list of file names.

### Playback
`WallpaperController` (`AllSet/Wallpaper/WallpaperController.swift`):
- one borderless window per screen, drawing `WallpaperRoot`;
- `.video` plays through `LoopingVideo`, which borrows from **`SharedVideoPlayers`** (one AVPlayer per URL, reference-counted, paused and released when its last viewer goes);
- playback is gated in `updatePlayback()` on lock, sleep, occlusion and ≥ 15 % uncovered, `PerformancePolicy.pausesDecorativeMotion` (Low Power, heat, Reduce Motion) and the "pause on battery" option;
- `PerformancePolicy.videoFrameRateLimit` caps the frame rate.

Every source flows through this one path, so anything that resolves to a video URL inherits all of it.

### Gallery UI
`LiveWallpaperPage` (`AllSet/Wallpaper/WallpaperPages.swift`) has tabs: Aerial Videos, Art, Photos, My Photos, My Videos.
- My Videos (`VideosPage`) is a `LazyVGrid` of `VideoTile`s.
- Each tile makes its thumbnail on appear with `AVAssetImageGenerator` (it decodes the video; the thumbnail isn't kept on disk).
- A tile plays a `LoopingVideo` preview on hover.

### Caches
`CostCache` (byte- and count-limited LRU) backs `ImageLibrary` (photos 160 MB, small copies 96 MB), `ArtworkCache` and theme previews. `AppServices.releaseCachedPictures` trims them when the main window closes and on memory pressure (audit Fixes 1–2). The main window is released on close, so its pages' state goes with it.

### Search and sort
Photo search (`PhotoSearch`, `WallpaperQuery`) is for online sources. There's no local wallpaper search.

### Plan, reusing all of the above
- **Model:** extend `WallpaperSource` with one case for a library item, resolved to a file where it already lives (no copy).
- **Catalog:** keep the library's catalog in `WallpaperStore` (the existing owner of user videos), loaded from a JSON the importer writes.
- **Playback:** unchanged. The library case resolves to a URL and goes through `LoopingVideo` → `SharedVideoPlayers` → `updatePlayback()`.
- **Thumbnails:** made once by the importer, saved to disk, and loaded through `ImageLibrary`'s byte-limited small-copy cache. No per-tile video decoding.
- **UI:** a library section inside the existing My Videos tab, using the same grid and tile style, with search, category chips and sort over catalog metadata.

## Phase 1: inventory of the source folder [measured]

**Source:** `/Volumes/KALI LINUX/Steam Wallpapers`, 14 GB on a USB drive (FAT). The tool only reads it; nothing in it was changed.
**Tool:** `scripts/wallpaper_library.py inventory`, with ffprobe, a 2 s ffmpeg decode test and a streamed SHA-256.
**Output:** `~/Library/Application Support/AllSet/Wallpaper/Library/inventory.json` (kept out of the repo because it lists your file names).

### What the folder is
A **Wallpaper Engine (Steam Workshop) library**: 196 numbered folders, each a Workshop item described by a `project.json`.

| Item type | Items | Can the existing player show it? |
|---|---|---|
| video | 48 | **yes**: a plain video file |
| scene | 138 | no: Wallpaper Engine's own `.pkg` scene format, which needs its renderer |
| web | 10 | no: HTML/JS pages that would need a web renderer |

Scene and web items would each need a second wallpaper engine, which this task rules out. They're **not imported**, and they're listed in the report.

### Video files

| | |
|---|---|
| Video files found | **62 (9.08 GB)** |
| Valid (probe and 2 s decode OK) | **62**; invalid 0 |
| Exact duplicates (SHA-256) | **0** |
| Resolution | 4K: 34, 1440p: 6, 1080p: 22 |
| Frame rate | 60: 35, 30: 17, 24: 4, and one each of 10, 12, 25, 50, 120, 144 |
| Codec | H.264: 48, VP9: 14 |
| Orientation | landscape 61, portrait 1 |
| Container | .mp4: 48, .webm: 14; **48 carry an audio track** (wallpaper playback is always muted) |

- **Importable: the 48 files that are the main file of a video item** (7.97 GB, all H.264 MP4).
- **Not importable as wallpapers: the 14 VP9 WebMs**, which are animation clips inside 2 web wallpapers (for example `anim4_open_phone.webm`) played by that item's HTML, not wallpapers on their own.

### Largest and outliers (importable)

| Size | Resolution | fps | Bit rate | Note |
|---|---|---|---|---|
| 1073 MB | 3840×2160 | **144** | 46 Mb/s | 2.4× more frames than a 60 Hz display shows |
| 931 MB | 3840×2160 | 60 | **99 Mb/s** | |
| — | 3840×2160 | 60 | **216 Mb/s** | the highest bit rate |
| — | 3840×2160 | **120** | 13 Mb/s | |
| 496 MB | **4810×2616** | 30 | 10 Mb/s | larger than 4K |
| — | 1080×1920 | 30 | 19 Mb/s | the only **portrait** video |

### Provenance and rights
- **None of the 196 items has any license or copyright field.** All are Steam Workshop uploads with no author in `project.json`.
- Many are clearly game or anime art (titles name Stray, Hollow Knight: Silksong, Arknights, Hunt: Showdown, Pokémon).
- One video has **no content rating** (`Apoc1`). One item is rated Mature, but it's a scene, so it isn't imported.
- **Decision:** every imported item is marked **`QUARANTINED` (provenance and license unknown)**. They play only from your drive, on your Mac. They're never copied into the app bundle or the repo, and never part of any shipped catalog.

## Phase 2: the importer

**Tool:** `scripts/wallpaper_library.py`. It uses macOS's own Python 3 plus Homebrew's `ffmpeg`/`ffprobe`, with no pip packages.

```sh
/usr/bin/python3 scripts/wallpaper_library.py inventory <folder>   # read-only report
/usr/bin/python3 scripts/wallpaper_library.py import <folder>      # catalog, thumbnails, the few transcodes
```

### What the importer does
- **Nothing is assumed about folder layout.** A Wallpaper Engine folder is recognised by its `project.json` files; any other folder's videos are all candidates.
- **Stable IDs:** each entry's ID is the first 16 hex digits of the file's SHA-256, not its name. A rerun updates entries by ID and replaces only that folder's entries, so the catalog never gains duplicates. Other folders' entries stay.
- **Incremental:** unchanged files (same path, size and modification time) aren't probed or hashed again. [measured] The first run over 9 GB took minutes (USB read); **a rerun took 2 s** and produced the same 48 IDs.
- **Duplicates:** exact duplicates (same hash) keep one canonical entry, and the rest are listed in `import-report.json`. Near-duplicates (difference hash of the thumbnail within 8 bits, and durations within 1 s) are **listed for review, never removed**.
- **Metadata** comes from the inventory: duration, size, resolution, fps, codec, bit rate, orientation. It goes into the **existing** model: a `LibraryVideo` entry kept by `WallpaperStore`, and `WallpaperSource.library(id)` (see Phase 3).
- **Titles:**
  - They come from the Workshop title, else the file name, else the folder name. Names made by cameras, downloaders or hashes (`ssstik.io_1761…`, `0519 (1)(1)`, `ab6896…`) are never used.
  - Wallpaper-site decorations are stripped (`【动态壁纸/4K/纯风景】`, `- 4K`, `(With BGM)`, `by b站@…`, `-moewalls-com`), and all-lowercase ASCII names are title-cased.
  - Examples: `horizon-sky-wanderer-moewalls-com` → *Horizon Sky Wanderer*; `Stray - Midtown - 4K` → *Stray - Midtown*.
- **Categories reuse the existing wallpaper categories** (`Aerial.Category`: landscapes, cities, underwater, space). **Two were added: games and abstract.**
  - Workshop "Game" → games.
  - Otherwise title keywords, then tags. Single ambiguous CJK characters (海, 星) were dropped after they put "云海" (sea of clouds) under Underwater.
  - The Aerial page shows only the categories Apple's list has.
- **Tags:** normalized Workshop tags, plus the category, resolution (`4k`, `1440p`…), `60fps`, and `portrait`/`ultrawide` where true.
- **Provenance:** source (steam-workshop / local-folder), Workshop ID and original title. Author and license are `null`, because the source doesn't provide them.
- **Status:** every entry is **`quarantined`** (license and author unknown; plus "no content rating" where missing).
  - Quarantined entries appear only in your local library, labelled *"For your own desktop … never copied into All Set or shared"*.
  - They're never bundled, never in the repo, and never part of a shipped catalog.
  - `unsupported` entries (couldn't be converted) are hidden.

### Result [measured]

| | |
|---|---|
| Video files scanned | 62 (9.08 GB) |
| Invalid | 0 |
| Skipped | 14 (the WebM parts of 2 web wallpapers) |
| Exact duplicates removed | 0 |
| Near-duplicates to review | 0 |
| **Unique wallpapers imported** | **48 (7.97 GB, played in place from the drive)** |
| Categories | games 30, landscapes 7, abstract 7, cities 2, underwater 1, space 1 |
| Status | quarantined 48 |
| Not imported (need another engine) | 138 scene items, 10 web items |

## Phase 3: thumbnails, playback, storage

- **Thumbnails:** one 640 px JPEG per video, made once by the importer (`Library/thumbnails/<id>.jpg`, 48 files).
  - The gallery loads them with the new `ImageLibrary.thumbnail(at:maxPixels:)`, decoded off the main thread at 512 px into the **existing byte-limited `smallCache`**.
  - So they're released with everything else when the window closes or memory runs short (audit Fix 2).
  - A card never touches the video unless you rest the pointer on it for 0.6 s, which plays the same hover preview the Aerials page uses.
- **Playback:** `WallpaperSource.library(id)` → `WallpaperStore.libraryURL(id)` → `LoopingVideo` → `SharedVideoPlayers`, inside `WallpaperRoot`.
  - That's the same path as `.video`, so occlusion and ≥ 15 % uncovered, lock, sleep, `PerformancePolicy` (Low Power, heat, Reduce Motion) and pause-on-battery all apply **with no separate logic**.
  - `moves()` counts it as moving, so coverage checks run.
  - The system-wallpaper still is taken from the same file (`videoStill`, shared with `.video`).
- **Storage:** nothing is copied from the drive.
  - The catalog stores each library folder once (`roots`, path plus label) and each video's path inside it. There are no hard-coded paths: the root comes from the folder you import.
  - If the drive is unplugged:
    - `reachableRoots` (refreshed on mount and unmount) says so;
    - cards stay browsable (thumbnails are local) but can't be set;
    - a wallpaper already set shows the default art until the drive returns, and your choice is kept.
- **Transcoding, only where measured necessary.** Real playback test (`scripts/playcheck.swift`, AVFoundation load, ready-to-play and a decoded frame): **all 48 play as they are.**
- **Efficiency,** measured with `scripts/playcost.swift` (15 s looping in a screen-sized window; the decoder is macOS's `VTDecoderXPCService`):

  | File | App | Decoder | Verdict |
  |---|---|---|---|
  | typical 4K60, 48 Mb/s | 3.7 % | 4.2 % | fine |
  | 4K60, **216 Mb/s** | 3.3 % | 3.2 % | fine: bit rate costs nothing with hardware decode |
  | 4K **144 fps** | 6.3 % | 7.9 % | about 2× for frames a 60 Hz screen can't show |
  | 4K **120 fps** | 7.2 % | 7.5 % | about 2× |
  | **4810×2616** | 1.7 % | **75.3 %** | beyond the hardware decoder: software decoding |

  So exactly those 3 files were converted: HEVC via VideoToolbox, at most 3840×2160 and 60 fps, no audio, into `Library/transcoded` (**1.19 GB** total). The originals on the drive are untouched. The rest (including 45 files with unused audio tracks) play as they are, muted, since the audio costs nothing measurable.
- **Tradeoff:** the 120 and 144 fps videos now play at 60 fps, which is identical on the MacBook's 60 Hz screen but fewer frames on a 120/144 Hz external display.

## Phase 4: the gallery

Built on what's there: the **existing My Videos tab** of the Live Wallpaper page. The design is unchanged; a **Library** section follows your own videos.

- **Grid:** the same `LazyVGrid` of cards as Aerial Videos (16:9, title and category icon, current-wallpaper outline, "Set as Wallpaper" on hover, video preview after a 0.6 s rest).
  - Only cards on screen are built.
  - Cards show the imported thumbnail and never a live video until previewed.
  - Cards don't touch the drive while drawing (`WallpaperStore.canPlay` reads the cached reachability). The file is looked up only when previewing or setting.
- **Search:** an in-memory match over each entry's title, original title, category and tags. It never scans video files.
- **Category chips:** the aerial chip style, showing only categories the library actually has. The Aerial page now also shows only categories Apple's list has, so the two new ones don't appear there empty.
- **Sort:** Name, Recently Added, Longest, Sharpest. All come from catalog metadata; nothing is invented (no "popularity").
- **Favourites and recents:** none exist anywhere in the app today, so none were added (a new state system would be out of scope).
- **Rights label:** a one-line note, and a tooltip per card with the quarantine reason.
- **Drive status:** an orange note when the drive isn't connected; cards say "Drive Not Connected" instead of "Set as Wallpaper".

`UIState.wallpaperTab` (default Aerial Videos, as before) lets the page open on a given tab. `LiveWallpaperPage` got an optional `tab:` initialiser.

**Visual check:** `-renderWallpaperLibrary <folder>` renders the tab at the top and scrolled.

## Phase 5: no regression

Probe `-probe wallpaperlibrary`, with the real main window, the real `WallpaperController` windows and the real shared players:
- **1,008 entries** (the 48 real ones repeated 21 times, each with its own thumbnail file, so the cache sees 1,008 distinct pictures);
- scrolled end to end (28,700 pt) at about 5,500 pt/s;
- 5 wallpaper switches;
- window closed;
- **5 cycles**.

It leaves your saved wallpaper exactly as it found it and deletes its synthetic thumbnails.

### Memory and players [measured]

| | Footprint | Thumbnail cache | Video players |
|---|---|---|---|
| Before (no window) | 29–37 MB | 0 | 0 |
| Window open | 103–136 MB | 15–82 cached | 0–2 |
| After scrolling 1,008 | 112–175 MB | **120 (68 MB): the count limit holds** | 1 |
| After 5 switches | 88–159 MB | up to 120 | **1** (plus 1 viewer for the page's preview) |
| **After closing, cycles 1–5** | **111, 90, 92, 94, 93 MB: no growth** | trimmed to 42 (24 MB) | 1 (the wallpaper itself) |
| After restoring the wallpaper | 107–109 MB | 42 | **0** |

- **Players never pile up:** switching five times keeps a single player, since each switch releases the previous video through `SharedVideoPlayers`.
- **Thumbnails stay within the cache's limits.**
- **Memory after close is flat across cycles.**

### Scrolling [measured]
28,700 pt in 5.1–5.2 s:
- CPU 115–118 % (thumbnail decoding runs on background threads in parallel);
- main thread: **longest stall 33–43 ms, 0.85–0.96 s of frames lost**.

**Tried:**
- Drawing whole cards on the GPU (`.drawingGroup()`) cut frames lost to 0.62–0.76 s. **Not adopted:** it can't contain the AppKit video view, so the hover preview would break.
- GPU-drawing the picture alone made it worse (1.9 s lost). Reverted.
- Removing per-card file checks had no measurable effect. Kept anyway: it removes main-thread disk access on a USB drive.

This is a very fast fling; see the remaining risks.

### The same pausing rules [measured]

| State | Library wallpaper playing? |
|---|---|
| Your windows cover the desktop ("pause when covered" on) | **no** |
| Covering ignored | yes |
| Low Power Mode (`PerformancePolicy`) | **no** |
| Back to normal | yes |

There's no separate logic: it's `WallpaperController.updatePlayback()`, which doesn't look at the source kind.

### The audit's own checks after this change [measured]
- **`-probe windowclose`:**
  - CPU: 0.03 % never opened, 0.04 % after closing; viewers released.
  - Themes footprint with previews on disk: **66 → 78 → 68 MB** (fully returned).
  - When the new build redrew some theme previews, the first run peaked higher (238 MB, 159 MB after closing). That's the audit's known remaining risk #2 (drawing previews from scratch), not this change.
- **Tests:** 205 pass, including 5 new `WallpaperLibraryTests`:
  - a tolerant catalog;
  - search;
  - sort from real metadata;
  - the source round-trips;
  - resolving to the converted copy, the original, or nothing when the drive is unplugged.
- **Build warnings:** 0.

### Thermal tiering [reasoned]
`PerformancePolicy`'s thermal tiers act through the same `pausesDecorativeMotion` and `videoFrameRateLimit` checks as Low Power, which were measured above. I couldn't heat the Mac on demand.

## Phase 6: SEO

**Skipped.** There's no public wallpaper website or SEO system in this repository; All Set is a desktop app. The catalog's titles, categories and tags would serve one if it existed.

---

## Final report

### Import stats
| | |
|---|---|
| Workshop items scanned | 196 (48 video, 138 scene, 10 web) |
| Video files scanned | 62 (9.08 GB) |
| Valid / invalid | 62 / 0 |
| Exact duplicates removed | 0 |
| Near-duplicates flagged for review | 0 |
| **Unique wallpapers in the library** | **48** |
| Categories | games 30, landscapes 7, abstract 7, cities 2, underwater 1, space 1 |
| Quarantined (provenance unknown) | **48 of 48**: all Workshop uploads with no author or license; 1 also has no content rating |
| Unsupported and not imported | 14 WebM clips inside 2 web wallpapers; 138 scene and 10 web items (they need Wallpaper Engine's renderers) |
| Size in the source | 7.97 GB (stays on the drive) |
| Size added on the Mac | **1.19 GB** transcoded copies (3 files) + 1.6 MB thumbnails + 44 KB catalog; nothing in the app bundle or repo |

### Files created
- `scripts/wallpaper_library.py`: inventory and importer.
- `scripts/playcheck.swift`, `scripts/playcost.swift`: playback test and decode-cost measurement.
- `Sources/AllSetCore/Wallpaper/WallpaperLibrary.swift`: `LibraryVideo`, `WallpaperLibraryCatalog`, `LibrarySort`.
- `Tests/AllSetCoreTests/WallpaperLibraryTests.swift`.
- `docs/wallpaper-import.md`: this file.

### Files changed
- `AllSetCore`:
  - `Wallpaper/WallpaperStore.swift`: `.library` source, catalog loading, URL resolution, reachability.
  - `Wallpaper/AerialCatalog.swift`: games and abstract categories.
  - `Aesthetics/ImageLibrary.swift`: `thumbnail(at:maxPixels:)`.
  - `Widgets/WidgetTheme.swift`, `Themes/ThemeSet.swift`: switches.
- `AllSet`:
  - `Wallpaper/WallpaperController.swift`: `.library` playback, a shared `videoStill`, mount observers, debug player report.
  - `Wallpaper/WallpaperPages.swift`: `LibrarySection`, `LibraryTile`, tab initialiser, aerial chip filter, hero text.
  - `Studio/ThemePreviews.swift`: switch.
  - `AppServices.swift`: `UIState.wallpaperTab`.
  - `MainWindow.swift`: tab routing.
  - `Widgets/PageCPUProbe.swift`, `Widgets/WidgetRenderHarness.swift`, `AppDelegate.swift`: DEBUG probe and render.

### Existing systems reused
- `WallpaperSource` and `WallpaperStore` (the model and its owner);
- `WallpaperController.updatePlayback()` (all pausing);
- `LoopingVideo` and `SharedVideoPlayers` (playback and preview);
- `PerformancePolicy`;
- `ImageLibrary`'s `CostCache`-backed small-copy cache and `releaseCachedPictures`;
- `Aerial.Category` (categories);
- the aerial page's chips and tile style;
- `SearchMatch` (word matching);
- the main-window release on close.

No second engine, cache, player, catalog model or state system was added.

### New dependencies
- `ffmpeg`/`ffprobe` (Homebrew), **for the import script only**. The app itself uses nothing new.
- The script runs on macOS's `/usr/bin/python3`, with no pip packages.

### Remaining risks and choices
1. **Rights.** Everything is quarantined. If any of these is ever to ship or be shared, it needs an author and a license first. Many are game or anime art, and several are re-uploads of TikTok/YouTube downloads (their file names say so).
2. **Scene and web wallpapers (148 items) aren't supported.** Supporting them would mean re-implementing Wallpaper Engine's scene renderer and a web view wallpaper: a second engine, out of scope.
3. **Fast scrolling hitches** (33–43 ms stalls while flinging through 1,000 cards).
   - The measured fix (GPU-drawn cards) conflicts with the hover preview.
   - Options: move the title and gradient into a lighter layer, or show the preview in a separate overlay window. Not done.
4. **Scale beyond ~1,000** is untested.
   - At 10,000 the catalog is ~9 MB of JSON, decoded off the main thread [reasoned: about 100–200 ms].
   - Search and sort are linear on every change (fine at 10,000 [reasoned]).
   - The grid stays lazy.
   - The importer's first run is bound by disk read speed for hashing; reruns only re-hash changed files.
5. **High-frame-rate originals now play at 60 fps.** That's identical on the MacBook's display, but fewer frames on a 120/144 Hz external display. The originals are untouched on the drive if you want them back.
6. **Unplugging the drive:** a playing library wallpaper falls back to the default art until the drive returns; your choice is kept. Cards stay browsable but can't be set.
7. **The catalog is per Mac**, in Application Support. Another Mac needs the import run there too, pointed at its own copy.
