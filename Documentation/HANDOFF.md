# All Set: Handoff

**Read this first at the start of every session, instead of reviewing the codebase.** It's rewritten at the end of every session. Dated session logs are in `Documentation/Reports/` (newest last). For what the app contains (widgets, themes, pages), see `CONTENT.md`. Only open the source files that the task at hand needs.

_Last updated: 2026-09-27 (wallpaper library: self-contained). Read Documentation/spec.md, architecture.md and report.md's CURRENT STATE first._

---

## Standing instructions from the user
1. **After every change, rebuild and replace the Dock app:**
   ```sh
   ./scripts/build-app.sh
   osascript -e 'tell application id "com.pratik.allset" to quit'
   open build/AllSet.app
   ```
2. **Optimise at the core level** with every change: CPU, GPU and WindowServer cost. Measure it; don't assume.
3. **Copyright:** themes are *original*, inspired by an era, genre or mood. No logos, album art, promo photos or trademarks. Real people's names may appear only in hidden search tags, never in UI text (a test enforces this). The user's player photos stay on their Mac, never in the repo.
4. **Save tokens:** read this file and the latest report instead of re-reviewing the project. End every session by updating this file and writing a report.
5. Commit or push only when asked. The remote is `origin` → github.com/pratik-aep/all_set-dynamic-island-.

## Machine quirks
- The first `python3` on PATH is an empty file that prints nothing: use `/opt/homebrew/bin/python3`, or awk, grep or perl.
- zsh doesn't split words: use arrays or `${=var}`.
- Screenshot file names contain a narrow no-break space: use globs.
- `sed` has no `\b`: use perl.
- Perl `s{}{}` breaks on Swift code full of braces: use the Edit tool.
- macOS has no `timeout` command.
- M4 MacBook Air: fanless, screen 1470×956 pt (2940×1912 px), 16 GB.
- Signing identity "All Set Development" is in the login keychain; `build-app.sh` uses it so permissions survive rebuilds.

## Build, test, verify
| What | Command |
|---|---|
| Debug build (expect 0 warnings) | `swift build 2>&1 \| grep -c warning:` |
| Tests (currently 205 in 64 suites) | `swift test` |
| Optimised build with DEBUG tools | `swift build -c release -Xswiftc -DDEBUG --build-path .build-probe` |

Run DEBUG tools as `.build-probe/release/AllSet <flag> -skip window,wallpaper,widgets,notch`.

**`-probe <name>`** prints numbers:

CI's `probe` job runs `scroll`, `pages` and `galleryparts` on every push (debug build) and puts the numbers in the run summary.

| Name | Measures |
|---|---|
| `islandmotion` | Frames lost per open, tab switch and close; `COLD=1` skips the warm-up |
| `systembuild` | System-tab build time |
| `search` | Live search results per source |
| `mystic` | CPU of the newest widgets |
| `fans` | Football and music widgets |
| `widgets` | Widget CPU |
| `gallery` | Gallery page CPU |
| `apply` | Theme apply cost |
| `reveal` | Theme reveal cost |
| `windowserver` | WindowServer CPU |
| `pages` | Page CPU (the default when no name is given) |
| `scroll` | Themes, Gallery, Art and Wallpaper scrolled a step a frame, twice each (first sight, then warm): CPU, frame gaps, worst stall. Holds off App Nap and posts live-scroll notifications like a trackpad. On a GPU-less CI VM frame gaps sit near 80 ms on every page (the window server, not the app): compare CPU and the worst stall |
| `galleryparts` | Build time of one Gallery card and of each of its parts |
| `windowclose` | Monitor viewers, CPU and footprint around opening and closing the main window (Themes page) |
| `covered` | A widget visible vs. covered; `ENTRY=`/`SIZE=` pick it |
| `desktopwidgets` | Each of the user's desktop widgets alone; `ONLY_KIND=`, `SECONDS=` |
| `neon` | Neon flicker on vs. off over 60 s |
| `wallpaperlibrary` | 1,008 library entries in the real main window: scroll, switch, close, 5 cycles, plus pausing rules. **Quit the Dock app first**; restores your wallpaper |

**`-render<X> <folder>`** saves PNGs to look at:

| Flag | Shows |
|---|---|
| `-renderIsland` | Island states and mid-spring frames |
| `-renderPhotos` | The Photos page after real searches |
| `-renderEntries dir -entryCategories a,b -entryIDs x,y` | Gallery widgets, live and still |
| `-renderThemeSets` | Theme set previews and pages |
| `-renderScaling` | Widget scaling |
| `-renderGPUArt` | GPU art |
| `-renderDesign` | Real-window capture of design themes |
| `-renderWallpaperLibrary` | My Videos with the imported library |
| `-renderPages` | Every main-window page at 900×600, 1280×800, 1728×1080 (`-pages a,b`, `-pageSizes WxH,…`). CI runs it on every push and force-pushes the latest set as JPEGs to the `ci-screenshots` branch (`git fetch origin ci-screenshots`) |

**Design system (2026-09-30):** the main window is always dark. Tokens and shared components are in `Sources/AllSet/Design/` (`DS.Space`, `DS.Radius`, `DS.Ink`, `DS.Surface`, `.dsText(role)`, `.dsFormStyle()`, `PageScaffold`, `PageHeader`, `HeroSection`, `MediaCard`, `MediaRail`, `GlassPanel`, `.pill`/`.pillProminent`/`.floating`, `FilterPill`, `SearchField`, `EmptyState`, `FlowLayout`, `FormPage(eyebrow:title:subtitle:lead:content:)`). New or reworked pages use these instead of literals. **Backdrop (2026-10-01):** the window draws one `WindowBackdrop` (`Design/WindowBackdrop.swift`): a deep navy canvas and four blue glows drifting on Core Animation layers, frozen by `PerformancePolicy.pausesDecorativeMotion` and while the window is occluded. Pages don't paint a background over it (`AppBackground` is only an accent glow); keep page and list backgrounds transparent. Pages that lead with media use `BleedScrollPage` with `HeroSection(bleed:)`: the hero runs under the navigation and fades into the backdrop, and sets `UIState.mediaUnderNavigation` so the navigation drops its fade. Navigation is `FloatingNav` (`Design/AppNavigation.swift`): `NavSection.of(page)` maps every `AppPage` to one of five places, and `NavItem.items(in:)` lists each place's pages; a new page needs a case in both. The window has no visible title bar (`MainWindowController.dress`), so every page names itself with a `PageHeader` or `FormPage` title.

**Scratchpad helpers** (session temp directory; they may be gone): `sheetL out.jpg cols files…` makes a contact sheet (sizes from the `CW`/`CH` environment variables); `load.sh` reads WindowServer load.

**Profiling:** `xctrace record --template 'Time Profiler' --attach <pid> --time-limit 60s --output x.trace`, then `xctrace export --input x.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > x.xml`, then aggregate with `/usr/bin/python3` (the Homebrew python lacks expat) using the scratchpad `perf/agg.py`, `stacks.py` and `main.py`. The "CPU Profiler" template records nothing on this Mac; use "Time Profiler". `xctrace --launch` can leave a copy stopped at dyld (state `T`): check `ps -o stat` and kill it. `leaks <pid>`, `heap <pid>` and `footprint <pid>` work without sudo; `powermetrics` needs sudo (not available).

**Measure honestly:** app CPU doesn't include Core Animation, which runs in WindowServer. The user is active while you measure, so compare interleaved A/B runs.

## Architecture map
SwiftPM, macOS 14.2+, Swift 6. The targets are:
- `AllSet`: the app, AppKit plus SwiftUI.
- `AllSetCore`: models and services, unit-tested.
- `CPrivateAPIs`: IOKit sensors.
- `MediaHelper`: a dylib that `/usr/bin/perl` loads for Now Playing.

**Core pieces**
- `AppServices.swift` owns every store and service. `observe()` is a `withObservationTracking` loop; call it as `AllSet.observe` inside an NSView.
- `AppDelegate.swift` handles launch and all the DEBUG flags.
- `MainWindow.swift` defines `AppPage`, the list of every page.

**Dynamic Island** (`Sources/AllSet/Notch/`)
- `IslandView.swift`: an NSView that draws the island's body, shadow and mask as Core Animation spring paths, so the shape animates in WindowServer. It also has `warmUp`, which builds every tab off screen 2 seconds after launch.
- `NotchRootView`: the content only.
- `ExpandedPanel`: a fixed frame the size of the largest tab; only the current tab is mounted, and tabs slide with `.tab(direction:)`.
- `NotchAnimation`: springs, plus `RevealEffect`, `RetractEffect` and `SlideEffect`, which use opacity, scale and offset only (never blur).
- `NotchController`: the panel window, pointer handling, live activities and haptics.
- Tabs: `HomeTab`, `TrayTab`, the Mixer tab, the Notes tab and `SystemTab`. SystemTab's cards get exact frames from a GeometryReader.

**Widgets**
- Models live in `AllSetCore/Widgets/`:
  - `WidgetModels.swift`: `WidgetKind` (54 kinds), `WidgetCategory` (9), `WidgetOptions` (decoded per key, tolerant) and per-kind defaults.
  - `WidgetCatalog.swift`: 91 gallery entries.
  - `FanModels.swift` and `MysticModels.swift`: the zodiac, tarot, aura, charm and magic-ball data.
  - Themes: `WidgetTheme*.swift` (49 themes: moodboards, fandom, core) and `DesignTheme.swift` (15 skins).
- Views live in `AllSet/Widgets/Kinds/*.swift`. `WidgetHostView.swift` has the kind → view switch and `WidgetSurface`. `DesktopWidgetController` manages the desktop windows, scaled by `settings.widgetScale` (0.7–1.6).
- Motion goes through `Components/LiveLayers.swift`. `LiveLayerView` subclasses run Core Animation loops at capped frame rates and stop when covered or when Reduce Motion is on. Each one also draws a still SwiftUI version for snapshots (`widgetSnapshot` environment value). Building blocks:
  - `LiveArtwork`: float, shine and glow, cached in `ArtworkCache`.
  - `PulsingGlow`, `Sparkles`, `BlinkingLight`, `EqualizerBars`.
  - `TwinkleLayer`, `AuraLayer`, `FlameLayer` and `SpiralLayer`, in `MysticWidgets.swift`.

**To add a widget kind:**
1. `WidgetModels`: the case, category, title, symbol, summary, keywords, sizes, `isFreeform`, `paintsOwnBackground`, `defaultSize` and defaults switch.
2. An entry in `WidgetCatalog`.
3. A view, plus a case in the `WidgetHostView` switch.
4. `WidgetOptionsEditor`: its section and `showsStylePicker`.
5. The `looks` list in `WidgetStudio`.

**Search and photos**
- `AllSetCore/Aesthetics/PhotoSearch.swift` searches Wallhaven and Openverse in parallel.
- `Wallhaven.swift`: SFW only (`purity=100`), about 45 requests a minute, multi-word names in quotes.
- `Search/WallpaperQuery.swift`: aliases, exclusions, pop-culture detection, and aesthetic → Wallhaven tag or Openverse only.
- `Search/AestheticSearch.swift`: aesthetic vocabulary and spelling.
- Openverse allows at most `page_size` 20 for anonymous requests; more returns a 401.
- The UI is `Studio/LibraryPages.swift` (`WebPhotosPage`, `SearchFilters`, `RecentSearches`), shared by the Wallpaper page and the Library.

**Wallpaper library** (docs/wallpaper-import.md)
- `WallpaperSource.library(id)`:
  - videos play from a copy in `originals/` (`--self-contained`); nothing needs the source folder at run time;
  - stills (`LibraryVideo.kind == .image`, a Wallpaper Engine scene's artwork) play from the Mac through `MovingStill` with the photo drift.
- Catalog: `~/Library/Application Support/AllSet/Wallpaper/Library/catalog.json`, written by `scripts/wallpaper_library.py import <folder>` (needs Homebrew ffmpeg; run with `/usr/bin/python3`). The importer is idempotent, with IDs from SHA-256.
- The library folder also holds:
  - `live/`: scene loops, made from the layers by `compose_live()`;
  - `stills/`: scene artwork;
  - `extracted/`: videos taken out of scenes;
  - `transcoded/`;
  - `thumbnails/`;
  - `bin/wetex`: the texture decoder, compiled from `scripts/wetex.swift`;
  - `scenes.json`: the scene cache. Bump `SCENE_RENDERER` when compositing changes.
  
  3.4 GB in total.
- `WallpaperStore.library`, `libraryURL(id)` (disk check, for playback only) and `canPlay(video)` (no disk access, for cards).
- UI: the `LibrarySection` in My Videos.
- The user's library is a Wallpaper Engine folder on `/Volumes/KALI LINUX/Steam Wallpapers`:
  - **181 imported** (138 live, 43 stills), from 48 video items, 7 web loops and 126 of 138 scenes;
  - 63 scene stills are rendered as seamless loops from their own parallax depths and effect settings; a loop is kept only if `frame_movement()` measures real movement (threshold 0.8 of 255), else the sharp still wins;
  - all **QUARANTINED** (Workshop, no license). Personal use only; never bundle or commit them.
- Scenes left out after review are listed by Workshop id in `SCENE_REVIEWED_SKIP`, each with its reason. To check new scenes, lay the thumbnails out on a contact sheet and look: the preview hash can't tell.

**Other areas**
- Wallpaper: `Wallpaper/WallpaperController` (plays only if at least 15% of the screen is uncovered; shared video players).
- Workspace: `Workspace/` (Carbon hotkeys, Accessibility window moves).
- Clipboard: `Clipboard/`.
- Mixer: `Mixer/` (Core Audio taps).
- Knocks: `Knock/` (SPU accelerometer).
- AI screenshot editor: `Screenshot/`.
- Settings: `AllSetCore/Settings/AppSettings.swift`.
- Deep links: `Support/DeepLink.swift` (`allset://open|widget|arrange|fit|theme|focus`).

## Performance lessons (don't relearn these)
- **The main window is released on close** (`MainWindowController.windowWillClose`). A hidden SwiftUI window gets no `onDisappear`, so anything registered in `onAppear` leaks until quit. Don't reintroduce `isReleasedWhenClosed = false` with a kept reference.
- **SwiftUI redraws covered windows.** Desktop widgets must use `WidgetTimeline` (not `TimelineView`), which pauses via `widgetIsOnScreen`. Animated SwiftUI text every second (`.contentTransition(.numericText())`) costs about 10 % CPU: use Core Animation for anything per-second.
- **Caches are `CostCache`** (bytes plus count, LRU). Weigh images with `NSImage.decodedByteCount`. `ImageRenderer` output is 16 bits a channel: convert with `ImageLibrary.displayReady` before keeping.
- **Power and heat limits come from `PerformancePolicy`** (`services.ui.performance`). Add new limits there, never as constants in a subsystem.
- Anything that moves all day uses a Core Animation layer, not SwiftUI animation (5–30% CPU otherwise). Cap `preferredFrameRateRange`: 10–30 fps.
- Don't animate SwiftUI frames or clipShape on big views: RenderBox reallocates surfaces every frame. Animate a Core Animation path instead.
- Keep only the visible content mounted. Give grid cards exact frames; flexible nested stacks measure children many times over.
- No animated blur or shadows; set `shadowPath`. Rasterize layers that only rotate.
- Per-second text changes use `CATextLayer` (`TickingText`), not a SwiftUI `Text` with `.contentTransition`.
- Theme preview cache keys use a content fingerprint and `drawingVersion`: bump `drawingVersion` when preview drawing changes.

## Current state (2026-09-26, evening)
- Branch **`perf-audit`** (not merged, not pushed): baseline commit `6022ee5` (the island, search and widget work), the audit commits, then the wallpaper-library commits (`5b54296`, `7608ad4`, and the scenes/web import after `1e633b1`). `main` is still at `e8dc7bc`.
- The audit log and final report are in **`docs/perf-audit.md`**. 200 tests pass, 0 warnings, and the Dock app is rebuilt from the branch.
- For A/B: `git worktree add ../allset-baseline <commit>`, then build the probe there (removed after the audit).

## Backlog (not started unless the user asks)
- **Needs the user's decision:** a seconds clock costs 9–12 % CPU while visible (F15 in the audit). Either move the rolling digits to Core Animation, or let the digits change without rolling.
- Wallpaper library: fast-scroll hitches (33–43 ms) over 1,000 cards; GPU-drawn cards break the hover preview. See docs/wallpaper-import.md.
- Audit recommendations not done: align decorative frame rates to {10, 15, 30}; lazy calendar store; see `docs/perf-audit.md`, Phase 5.
- Audit findings F1–F16 from the Phase 0 report are waiting for the user's "go".
- Later waves: calendar in the notch, a brightness HUD, a menu-bar icon manager, Shortcuts/script live activities.
- Optional: Unsplash, Pexels or Pixabay search, if the user gets an API key.
