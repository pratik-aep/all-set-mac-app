# All Set: Handoff

**Read this first at the start of every session, instead of reviewing the codebase.** It's rewritten at the end of every session. Dated session logs are in `Documentation/Reports/` (newest last). For what the app contains (widgets, themes, pages), see `CONTENT.md`. Only open the source files that the task at hand needs.

_Last updated: 2026-10-02 (widget snap grid, drag from the gallery, right-click menu). For the wallpaper library, read Documentation/spec.md, architecture.md and report.md's CURRENT STATE first._

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
5. Commit or push only when asked (the user has approved commits at each verified checkpoint this session; never push without being asked). The remote is `origin` → github.com/pratik-aep/all-set-mac-app.

## Outside the repo (set up 2026-10-02)
- Claude Code has `ponytail@ponytail` (github.com/DietrichGebert/ponytail, MIT, hooks reviewed: local files only) enabled in `~/.claude/settings.json`, default level full; `/extension [status|on|off|lite|full|ultra]` (`~/.claude/commands/extension.md` → `~/.claude/ponytail-ctl.js`) shows and switches it. Needs a new session to load. Ponytail means: simplest working code, no unrequested abstractions.
- `.claude/settings.local.json` (git-ignored) allows routine build/test/git commands and denies `git push`, `rm -rf`, `git reset --hard`, `sudo` (a compound command containing `rm -rf` is refused).
- Testing hotkeys: synthetic `CGEvent` doesn't trigger Carbon hotkeys; use System Events `key code`. Driving the pointer: see the scratchpad `mouse` tool notes in the 2026-10-01/02 sessions (refuses to click unless an All Set window is topmost).

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
| Tests (currently 263 in 78 suites) | `swift test` |
| Optimised build with DEBUG tools | `swift build -c release -Xswiftc -DDEBUG --build-path .build-probe` |
| Everything, on GitHub | CI (`.github/workflows/ci.yml`, `macos-26`) on every push: `build-and-test` (fails on any warning), `screenshots` (`-renderPages`, published to the `ci-screenshots` branch) and `probe` (`-probe scroll`, `pages`, `galleryparts`, in the run summary). Cloud sessions without a Swift toolchain verify through CI only |

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
| `-renderPhotos` | Photo search (the picture picker's Photos view) after real searches |
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
  - Themes: `WidgetTheme*.swift` (57 looks: 14 moodboards, 22 fandom, 13 core, 8 Colour & Light in `WidgetTheme+Colour.swift`) and `DesignTheme.swift` (15 skins). `ThemeLibrary` holds the 57 complete desktops the Themes page shows.
- **Placement is a snap grid** (`AllSetCore/Widgets/WidgetGrid.swift`, tested in `WidgetGridTests`): slots the size of a small widget, `spacing` apart, centered in each screen's visible area, margin kept in *screen* points (`WidgetLayout.margin / widgetScale`, as `fitted` does, or themes lose a column). `place(near:)` for drops, `firstFree` for adds (columns from the left), `arranged` for Clean Up (group shifted onto the lattice first, so every theme keeps its exact shape; larger widgets choose first). `DesktopWidgetController.tidyIfShapeChanged` runs Clean Up whenever sizes, membership, screens or the widget scale change, so a new Mac or display reflows. Compare screens by `displayID`, never `NSScreen ==` (new objects each call). `WidgetGridOverlay` (Core Animation, shown only during drags) draws free slots and the target; gallery cards `.onDrag` set `ui.widgetDrop`, which lifts the widgets, dims the screen and makes the overlay a drop target. Right-click menu: `WidgetMenuItems` from the `widgetMenu` environment; widgets with their own `.contextMenu` append it after a divider.
- **Theme widgets in the gallery:** `ThemeWidgetCatalog` (core) flattens every set's widgets (623, repeats removed by an encoded fingerprint); setup themes' font and corners are copied onto each widget (`options.font`, `options.cornerRadius`). UI: `Studio/ThemeWidgetGallery.swift`, a lazy rail per theme; `ui.galleryFromThemes` picks it (`-renderPages … -pages gallery-themes`).
- **Text options on every widget** (`WidgetOptions.font`, `cornerRadius`, `textCase`, `renamedText`, `footnote`, `footnoteStyle`). Built-in labels go through `WidgetWord(...)` (`Widgets/Design/WidgetWord.swift`), which shows the rename and reports the original via `WidgetWordsKey`; the inspector's preview collects those, so the editor lists exactly the words on screen. New fixed labels in widgets should use `WidgetWord`, not `Text`. The caption draws in the window's bottom margin, so it never needs a slot.
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
- The UI is `Studio/LibraryPages.swift` (`WebPhotosPage`, `SearchFilters`, `RecentSearches`), reached only through `LibraryPicker`, the picture picker of Photo, Polaroid and VHS widgets. The Photos and My Photos pages are gone; the Wallpaper page embeds only `ArtLibraryPage`.

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
- The user's library: **1164 wallpapers** (1006 live, 158 stills) from four Wallpaper Engine folders, self-contained on the Mac, optionally fetched from (and offloaded to) a personal server. Current numbers and rules are in `Documentation/spec.md`; how it works is in `architecture.md`.
  - All **QUARANTINED** (Workshop, no license). Personal use only; never bundle or commit them.
- Scenes left out after review are listed by Workshop id in `SCENE_REVIEWED_SKIP`, each with its reason. To check new scenes, lay the thumbnails out on a contact sheet and look: the preview hash can't tell.

**Lid Plane** (`AllSet/LidPlane/`, `AllSetCore/LidPlane/`; System → Lid Plane): Jhey's lid-fold effect, GPL-3.0-or-later (notices in `Documentation/third-party/`; **distributing All Set means distributing it under the GPL**, fine for personal use). Core: `LidSensor` (IOHID lid angle, read-only), `AutoAnchor`, `LidMotionFilter`, `AngleActivation`, `CaptureDemand`, `DisplaySafetyGate`, `LidPlaneSettings` (UserDefaults `lidplane.*`), tested in `LidPlaneTests`. App: `LidPlaneController` (30 Hz timer only while enabled; 5 Hz readout while the page is open; none otherwise), `LidPlaneRenderer` (Metal, shader inline), `LidPlaneCapture` (ScreenCaptureKit), `LidPlanePage`. Differences from upstream: the stream excludes only the overlay **window** (upstream excludes its whole app, which would drop All Set's own wallpaper and widgets), and the overlay stays ordered in at alpha 0 while a stream runs so it can be found; shortcuts use `HotKeyCenter` with a `lidplane` group (window snapping's `unregisterAll()` now only drops its own group). Preserve upstream's safety rules (never fall back to an external display, wait 0.5 s of stable display before restarting capture, raw angle above the limit always hides). `-renderLidPlane dir` renders previews and runs the renderer checks. **Not verified by me:** a live capture with the effect on (needs All Set's own Screen Recording approval and a physical lid).
- **Keychain prompts:** never read Keychain at launch. `WallpaperStore.deleteServiceToken` now reads it only when a permanent delete runs; reading at launch asked for the login password after every rebuild (ad-hoc probe builds especially).

**AI Screenshot shortcut** (`Screenshot/ScreenshotShortcutController.swift`, core `ScreenshotShortcut` + `SymbolicHotKeys`): a Carbon hotkey for ⌘⇧5 **also** lets macOS's own toolbar open (both fire), so the controller switches off symbolic hotkey 184 in `com.apple.symbolichotkeys` (CFPreferences + `activateSettings -u`), keeps a UserDefaults marker (`screenshot.systemShortcutOffByAllSet`) and restores it on quit, on another choice, and at the next launch after a crash. Never leave 184 off without the marker. **Testing hotkeys:** synthetic `CGEvent`s don't trigger Carbon hotkeys; use `osascript -e 'tell application "System Events" to key code 23 using {command down, shift down}'`, and a CLI test needs `NSApplication.shared.run()`, not `RunLoop.main.run()`.

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
- **Drawing a theme preview holds the main thread** (2 s for a busy desktop in a debug build on CI). `ThemePreviewCache` therefore waits while any scroll view is live-scrolled (`NSScrollView.willStartLiveScrollNotification`) and 0.35 s after. A purge (memory pressure) bumps the observed `generation`, which is part of each card's `.task` id, so cards still on screen ask again instead of spinning forever.
- **Liquid Glass only on what doesn't scroll** (`GlassPanel`: the navigation's two capsules, its switches, the Undo toast). Glass on every pill and button tripled scrolling CPU in the probe (warm Themes 9.7% → 43.6%) because glass re-samples what moves behind it; back on the navigation only, 12.6%. Tinted glass also rendered dark over the canvas, so selected and prominent controls are solid white fills.
- **Glass needs something to show.** `GlassPanel` uses `.clear` glass plus a static lit rim (`GlassRim`): `.regular` over a dark picture in dark mode rendered as a solid dark capsule. Heroes darken their top only to 0.32 so the navigation's glass has picture to bend.
- **Motion when opening:** `MainView` cross-fades pages (`.id(ui.page)`, insertion scales from 0.985, 0.32 s); `.entrance(delay:)` (opacity and offset only) staggers a theme's page in; picking a wallpaper dips the hero to dark and fades up (one player, never two). All go through `Motion.resolved`, so Reduce Motion gets plain fades.
- **The backdrop's glows share one strength range** (alpha 0.09–0.13, bell-curve falloff). A small, brighter glow read as a hot spot.
- **Decorative motion in the main window is Core Animation** (`LensGlowView`): the probe showed no idle CPU change with the backdrop moving. Freeze it with `PerformancePolicy.pausesDecorativeMotion` and on window occlusion.
- **AppKit-backed containers ignore SwiftUI safe-area insets**: an `HSplitView` slid under the floating navigation. Use plain stacks under the navigation.
- **Size heroes by their frame, not their media**: `Color.clear.overlay { media }`. A filling picture otherwise grows the stack and pushes the words out of view.
- **Measuring on CI:** a nearly invisible probe window gets App Nap (hold it off with `ProcessInfo.beginActivity`), and a GPU-less VM's window server caps frame gaps near 80 ms on every page; compare CPU and the worst stall, not average frame time.

## Current state (2026-10-02)
- **In progress: a 7-step request** (in order): 1 widget snap grid, drag, right-click menu ✅; 2 every theme's widgets in the gallery + editable labels inside widgets and an optional caption below ✅; (extra, asked mid-way) Lid Plane tab ✅; 3 AI Screenshot on ⌘⇧5 ✅ (replaces the system shortcut, restored on quit); 4 analyse this Mac (hardware, sensors, permissions) and adapt; 5 measure and fix choppiness everywhere; 6 window UI toward the user's "Wallspace" reference (big featured hero, filmstrip, curated rows); 7 Island Notes tab: alarms, stopwatch, daily routines with notifications.
- Done since: Lid Plane tab (`0626efc`), AI Screenshot ⌘⇧5 (`bf59f1f`). Remaining: 4, 5, 6, 7 above, in that order.
- Step 1 verified in the real app (seeded layout tidied to the predicted slots, Arrange-mode drag landed in the predicted slot with the overlay showing, right-click menu, Remove). **Not yet seen working by a person:** dragging a gallery card onto the desktop, and dragging a widget straight off the desktop outside Arrange mode (the desktop was covered by the user's windows; synthetic clicks pass through the island panel, so don't drive the pointer near the notch).

## Earlier state (2026-10-01)
- `main` is at `e92ba9e`: the main-window redesign (design system, floating navigation, every page rebuilt), merged.
- Branch **`claude/festive-brown-ks0f3c`** is 7+ commits ahead of `main`, not yet merged: the navy backdrop with drifting blue light, full-bleed heroes on Wallpaper/Themes/Art, theme previews waiting while scrolling, and the `scroll`/`galleryparts` probes with the CI `probe` job. CI green: 0 warnings, 239 tests.
- Session logs: `Documentation/Reports/2026-10-01-ui-redesign.md` (this redesign), earlier ones beside it. The September performance audit is in `docs/perf-audit.md`.
- **Not yet seen by a person on a real Mac:** the backdrop's motion (CI only captures stills), the Island page's interactive header (pills and try-it buttons inside a form section header), and the redesigned Library with real wallpapers (CI has no catalog).

## Backlog (not started unless the user asks)
- Gallery cards take about 70 ms each to build in a debug build on CI, spread evenly over the widget preview, size picker, chips and button (`-probe galleryparts`): no single fix; a lighter card would be a design change.
- The first visit to Themes after an install or update can still stall once, on a preview already being drawn when scrolling starts.
- **Needs the user's decision:** a seconds clock costs 9–12 % CPU while visible (F15 in the audit). Either move the rolling digits to Core Animation, or let the digits change without rolling.
- Wallpaper library: fast-scroll hitches (33–43 ms) over 1,000 cards; GPU-drawn cards break the hover preview. See docs/wallpaper-import.md.
- Audit recommendations not done: align decorative frame rates to {10, 15, 30}; lazy calendar store; see `docs/perf-audit.md`, Phase 5.
- Audit findings F1–F16 from the Phase 0 report are waiting for the user's "go".
- Later waves: calendar in the notch, a brightness HUD, a menu-bar icon manager, Shortcuts/script live activities.
- Optional: Unsplash, Pexels or Pixabay search, if the user gets an API key.
