# All Set: performance and resource audit

Working log for the audit. Phases are appended in order. Every number says how it was obtained: **[measured]** means a profiler or OS counter on this Mac; **[reasoned]** means static analysis of the code.

Inventory corrections to the brief: the code has 54 widget kinds (not 52), 49 themes (not 43) and 41 palettes (not 33). The inventory file is `CONTENT.md`.

---

## Phase 0: tooling

| Tool | Available | Used for |
|---|---|---|
| `swift build` / `swift test` | yes | builds, 193 unit tests |
| Xcode 26.3, `xcodebuild` | yes | not needed (SwiftPM project) |
| `xctrace` (Time Profiler, Allocations, Leaks, Animation Hitches, Power Profiler) | yes | CPU sampling of the running app. The "CPU Profiler" template recorded no samples on this Mac; "Time Profiler" works. |
| `leaks`, `heap`, `footprint`, `vmmap`, `sample` | yes | leak and retain-cycle check, heap census, memory footprint |
| `powermetrics` | **no** (needs sudo) | no package-power numbers; energy is inferred from CPU time |
| App's own DEBUG probes (`-probe …`) | yes | CPU per view/page, frames lost, before/after comparisons |

**Mode: runtime profiling is possible.** I can build, launch and profile the app, so measured numbers are real. Limits:
- There's no power-rail data (no sudo).
- WindowServer CPU can't be attributed per app, so it's measured by quitting and relaunching All Set (A/B).
- The user was using the Mac during the runs, which adds noise.

## Measured baseline (before any change)

The Dock app was launched at 04:37 and had been running 12 h. It had 11 desktop widgets (Neon Nights–style set), a photo wallpaper, Now Playing and clipboard monitoring, and the main window had been opened and closed during the day.

| What | Number | How |
|---|---|---|
| App CPU, 12 h average | **0.24 %** of one core (104.5 s CPU in 11 h 59 m) | [measured] `ps cputime` |
| App CPU, idle, 60 s | **0.66 %** (397 ms of samples) | [measured] xctrace Time Profiler |
| Now Playing helper (perl) | 2.2 s CPU in 12 h (~0.005 %) | [measured] `ps` |
| WindowServer, app running vs quit | 7.5 % vs 7.0 % (difference within noise); 14.2 % in the minute after relaunch | [measured] `load.sh`, A/B |
| Memory footprint, fresh launch | **106 MB** | [measured] `footprint` |
| Memory footprint after 12 h | **533 MB (peak 790 MB)**: IOSurface 184 MB, malloc 161 MB, decoded images ("CG raster data") 116 MB | [measured] `footprint`, `heap` |
| Leaks | 38 blocks, 4 KB total; one retain cycle (see F9) | [measured] `leaks` |

Where the 0.66 % idle CPU went, from 60 s of samples [measured]:
- Main thread 0.48 %. Of that, 0.30 % is layer drawing (Core Animation commit), 0.10 % SwiftUI graph updates, 0.04 % timers and 0.04 % mouse-event monitors.
- System sampler 0.08 %: disk capacity, IOKit, battery, temperatures, process list.
- Blur re-rasterized on the CPU: 0.10 % (`vSepConvolveARGB8`, from `RB::CGContext::apply_blur` in an animating SwiftUI view: the neon sign's flicker).
- Wallpaper coverage check 0.04 %; clipboard poll 0.01 %.

**Takeaway:** steady idle CPU is already low. What goes wrong over a long session is (a) **background work left running after the main window closes**, and (b) **memory kept after it's no longer needed.** F1–F3 below prove both.

---

## Phase 1: resource map

Legend for the "hidden" column (does it keep running when its UI is hidden, covered or inactive?): **stops** / **slows** / **KEEPS RUNNING**.

| # | Subsystem (file) | Trigger | Interval | Thread / QoS | I/O or network | Owner, cancellation | When hidden |
|---|---|---|---|---|---|---|---|
| 1 | Island pointer tracking (`Notch/NotchController.swift`) | Global and local `NSEvent` monitors for mouse moved, drag, down and up | every mouse event system-wide | main | none | `eventMonitors`, app lifetime | **KEEPS RUNNING** (needed to detect hover; cheap: a rect test per event, 0.04 % [measured]) |
| 2 | Island backstop timer (same file) | `Timer` | 0.15 s | main | none | `pointerTimer`, invalidated on collapse | stops (only while expanded) |
| 3 | Island shape and animations (`Notch/IslandView.swift`) | Core Animation springs on state change | per change | WindowServer | none | layer, app lifetime | stops (no loop) |
| 4 | Island warm-up (`IslandView.warmUp`) | one `Task` 2 s after launch | once | main | none | a throwaway model and view, closed after | the throwaway model is **never freed** (retain cycle, F9) |
| 5 | Island live activities (`NotchController`) | media, volume, power and knock callbacks; transient `Task`s | per event | main | none | `transientTask` / `nowPlayingHideTask`, cancelled when superseded | stops |
| 6 | Island Home tab progress (`Notch/HomeTab.swift`) | `TimelineView` | 1 s while playing, 1 h paused | main | none | SwiftUI | stops (only mounted while expanded) |
| 7 | Desktop widget windows (`Widgets/DesktopWidgetController.swift`) | one window per widget; occlusion notifications | per change | main | none | `windows`, `occlusionObservers` | stops or slows (occlusion drives `widgetIsVisible` and `widgetIsOnScreen`) |
| 8 | Animated widget layers (`Components/LiveLayers.swift`, `MysticWidgets.swift`, …) | Core Animation loops, `preferredFrameRateRange` 10–30 fps | continuous in WindowServer | WindowServer | none | `LiveLayerView.isRunning` | stops when covered, in Low Power Mode, or with Reduce Motion |
| 9 | Widget clocks and text (`TimelineView` in 25 places: clocks, calendar, dates, quotes, mystic…) | SwiftUI schedule | 1 s (clock with seconds, running focus) to 1 h; mostly `everyMinute` | main | none | SwiftUI | **NEEDS VERIFICATION**: SwiftUI doesn't know a window is occluded, so these probably keep firing under covering windows. Cost per tick is one widget redraw. |
| 10 | Neon sign flicker (`Kinds/DarkWidgets.swift`) | `.task` loop | burst every 5–13 s | main | none | SwiftUI task, keyed on visibility | stops when covered; **each burst re-blurs four text shadows (up to radius 34) on the CPU** [measured 0.10 %] |
| 11 | Generative art (`Widgets/ArtView.swift`, `ArtShader.swift`) | MTKView (GPU) or `TimelineView(.animation)` fallback | 24 fps (15 on battery) | GPU / main | none | view | stops (`isVisible` gate) |
| 12 | Widget data refresh (`Design/WidgetComponents.swift` `widgetRefresh`) | `.task` loop | wakes every ≤ 60 s; work is due per `RefreshPolicy` | main | network through services | SwiftUI task, keyed on `widgetIsOnScreen` | stops when covered |
| 13 | Weather and air quality (`AllSetCore/Weather/Weather.swift`) | called by #12 | 15–60 min max age | async | HTTPS (Open-Meteo) | merged by an `inFlight` key; disk cache | stops (no callers) |
| 14 | GitHub, status checks (`AllSetCore/Developer/*.swift`) | called by #12 | 5 min–1 h / 30 s–10 min | async | HTTPS | merged by `inFlight`; GitHub disk cache | stops |
| 15 | System monitor (`AllSetCore/System/SystemMonitor.swift`, `SystemSampler` actor) | `Task` sleep loop | fastest viewer (1–5 s); idle 3 s (5 on battery, 10 in Low Power) | sampler actor off main; publishes on main | IOKit, `proc_pidinfo`, `statfs` | `loop` task; `viewers` dictionary | slows when idle but **never stops** (3 s quick sample; detailed every 30 s). **After the main window closes, its viewer stays registered: 2 s detailed sampling forever (F1).** |
| 16 | Main window (`MainWindow.swift`) | built on first open | — | main | — | `MainWindowController.window`, `isReleasedWhenClosed = false` | **KEEPS RUNNING**: the whole page tree stays alive after close (views, observation, timers, images, layers) (F1, F2) |
| 17 | Live wallpaper (`Wallpaper/WallpaperController.swift`) | occlusion, lock, sleep, power and app-switch notifications, plus a coverage `Timer` | coverage check every 2 s | main | reads the window list | `observers`, `coverageTimer` | playback stops (covered, locked, asleep, Low Power, optionally battery). **The coverage timer runs even for a still photo with no motion (F7).** |
| 18 | Wallpaper video (`SharedVideoPlayers`) | AVPlayer, reference-counted per URL | continuous while playing | AVFoundation | disk decode | released per viewer | stops (paused when hidden) |
| 19 | Core Audio mixer (`Mixer/MixerController.swift`, `AllSetCore/Audio/*`) | Core Audio property listeners; taps only for apps not at 100 % | events | main + audio IO thread | none | `router`; tap stopped 2 s after silence | stops (taps idle when silent) |
| 20 | Volume and device HUD (`AllSetCore/Audio/VolumeMonitor.swift`) | Core Audio listeners | events | main | none | app lifetime | event-driven |
| 21 | TapTap sensor (`AllSetCore/Knock/*`) | IOHID input reports (~1 kHz) plus a 1 s watchdog `Timer`, plus global key and mouse monitors | ~1 kHz while listening | HID callback thread | none | `sensor`, `watchdog`, `monitors` | stops when disabled, asleep, display asleep, locked or in Low Power Mode |
| 22 | Clipboard monitor (`Clipboard/ClipboardMonitor.swift`) | `Timer` comparing `changeCount` | 0.5 s (1 s on battery) | main | image save and OCR off main | `timer`, app lifetime | **KEEPS RUNNING** by design: macOS has no public clipboard-change event. Cost 0.01 % [measured]. |
| 23 | Clipboard OCR (`ClipboardMonitor`, Vision) | on demand per image | — | detached utility task | disk | — | on demand |
| 24 | Now Playing helper (`Sources/MediaHelper/MediaHelper.m`, a perl process) | MediaRemote notifications + a 10 s safety timer | 10 s | helper process, main queue | XPC to mediaremoted | `MediaController` restarts it on exit | **KEEPS RUNNING** (2.2 s CPU in 12 h [measured]; negligible) |
| 25 | Calendar (`AllSetCore/Calendar/CalendarService.swift`) | `EKEventStoreChanged` + a 300 s loop | 5 min | main | EventKit | `refreshLoop`, app lifetime | **KEEPS RUNNING** without any calendar viewer (cheap) |
| 26 | Window snapping (`Workspace/WindowManager.swift`) | global mouse down, drag and up monitor; Carbon hotkeys | per event | main | Accessibility calls on snap | app lifetime | event-driven |
| 27 | Workspace restore (`Workspace/WorkspaceController.swift`) | polls for new windows | 250 ms, at most 32 times | main | Accessibility | per restore | only during a restore |
| 28 | Photo and wallpaper search (`AllSetCore/Aesthetics/PhotoSearch.swift`) | typing, debounced 400 ms; paced per site | on demand | main + URLSession | HTTPS; disk cache | `task` cancelled when superseded | on demand. The in-memory page cache has no limit (small). |
| 29 | Image library cache (`AllSetCore/Aesthetics/ImageLibrary.swift`) | on demand | — | decode off main | disk, HTTPS | `memoryCache` (≤ 40 images), `smallCache` (≤ 80) | **count-bounded, not byte-bounded**: 40 × a decoded 3200 px image ≈ 1 GB worst case; clears everything at once when full (F4) |
| 30 | Artwork cache (`Components/LiveLayers.swift` `ArtworkCache`) | on demand | — | render main, glow blur off main | none | LRU, 60 entries | count-bounded only (F4) |
| 31 | Theme previews (`Studio/ThemePreviews.swift`) | on demand per visible card | — | serial render queue | disk cache | `images` dictionary, **never evicted** | 1136×768 px ≈ 3.5 MB decoded each, up to ~170 MB for all 49 [reasoned from the size]; kept after the window closes (F2) |
| 32 | AI screenshot editor (`Screenshot/ScreenshotStudio.swift`) | on demand | — | main + network | HTTPS (Anthropic, OpenAI) | `states`, one full image per edit, **no limit** | per session (F6) |
| 33 | Aerial download progress (`AllSetCore/Wallpaper/AerialCatalog.swift`) | `Task` loop | 250 ms | main | download | ends with the download | only while downloading |
| 34 | Energy policy (`AppServices.swift` `EnergyMode`) | power-state, accessibility and power-source notifications | events | main | none | app lifetime | read by the wallpaper, widgets, clipboard and monitor pace. **Thermal state is ignored; network refresh and the island don't use it (F5).** |
| 35 | Memory pressure | — | — | — | — | — | **nothing responds to memory pressure (F4)** |

---

## Phase 2: findings, ranked by evidence

### CRITICAL

**F1. Closing the main window leaves its work running until you quit.** [measured]
- **Evidence:**
  - `MainWindowController` keeps the window with `isReleasedWhenClosed = false`, so the SwiftUI tree survives a close.
  - SwiftUI does not send `onDisappear` when a window is ordered out.
  - The Dynamic Island page (the default page) registers `monitor.setViewer("window", visible: true, interval: 2)` in `onAppear`. The System Monitor page does the same.
- **Probe `-probe windowclose`:** viewers are `["window": 2.0]` while the window is open, and **still `["window": 2.0]` after it's closed.**
- **App CPU:** **0.09 %** in the 30 s before the window was ever opened, **0.89 %** in the 30 s after opening and closing it once. That's a 10× increase, for the rest of the session.
- **Criteria met:** runs continuously with no visibility gate; the resource has no cancellation path.

**F2. Memory built up by the main window is never given back.** [measured + reasoned]
- **Evidence:** the footprint is 106 MB at launch and 533 MB (peak 790 MB) after 12 h. Leaks account for 4 KB, so this is retained memory, not leaked memory.
- **The retained window keeps:**
  - its page's layers (IOSurface, 184 MB total);
  - theme previews at about 3.5 MB each in an `images` dictionary that's never evicted (#31);
  - photo thumbnails and search results.
- **Criteria met:** unbounded cache; no owner releases it.

### HIGH

**F3. The system monitor never stops sampling, even with no viewer at all.** [measured + reasoned]
- **Evidence:** the idle loop takes a quick sample every 3 s and a detailed one every 30 s, for as long as the app runs.
- **Why it exists:** only to keep the sparkline history warm and the optional menu-bar CPU readout. With no viewer and the readout off, nobody sees the result.
- **Cost:** measured idle cost of the sampler is about 0.08 %. Each sample also republishes `snapshot`, which invalidates observers.
- Not CRITICAL, because the interval is 3 s and not below 250 ms.

**F4. Image caches are bounded by count, not bytes, and nothing reacts to memory pressure.** [reasoned + measured context]
- **Evidence:**
  - `ImageLibrary.memoryCache` holds 40 full-size images (decoded up to 3200 px, about 25 MB each) and `smallCache` holds 80.
  - Both call `removeAll()` when full, which re-decodes everything visible at once.
  - `ArtworkCache` holds 60 entries.
  - No `DispatchSource.makeMemoryPressureSource` anywhere.
- **Measured context:** "CG raster data" (decoded images) was 116 MB after 12 h.

**F5. There's no single performance policy, and thermal state is ignored.** [reasoned]
- **Evidence:** `EnergyMode` covers Low Power, Reduce Motion and battery, but:
  - `ProcessInfo.thermalState` is only displayed, never acted on;
  - widget network refresh (`RefreshPolicy`) doesn't slow in Low Power Mode or when the Mac is hot;
  - frame-rate caps are constants scattered across the layer classes (10–30 fps).
- **Consequence:** a hot fanless Air keeps the same animation and refresh load.

### MEDIUM

**F6. The screenshot editor's undo history has no limit.**
- **Evidence:** `ScreenshotStudio.states` appends a full-resolution image per edit, with no cap, for the life of the editing session.

**F7. The wallpaper coverage timer runs when nothing can move.**
- **Evidence:** `scheduleCoverageCheck(active: allowed && config.pauseWhenCovered)` ignores whether the source animates at all. A still photo (motion `.still`) gets a window-list query every 2 s [measured 0.04 %].

**F8. The neon sign flicker re-blurs four shadows on the CPU every burst.**
- **Evidence:** the profile shows `RB::CGContext::apply_blur` → `vSepConvolveARGB8` from an interpolating display list, 58 ms per minute [measured]. The code comment claims it "costs nothing". That claim is wrong, though the cost is small (0.1 %).

### LOW

**F9. The island warm-up leaves one retain cycle.**
- **Evidence:** `leaks` shows `ROOT CYCLE: <NotchViewModel>` via its observation registrar.
- **Cause:** `IslandView.watch` captures the model strongly inside a closure stored in the model's own registrar. It's 2 KB, once, but it's a real lifecycle bug.

**F10. Calendar refreshes every 5 minutes with no viewer.** EventKit query, cheap.

**F11. The Now Playing helper keeps a 10 s safety poll.** It's a backstop for players that don't post notifications. 2.2 s CPU in 12 h [measured]. Keep.

**F12. The photo search page cache has no limit.** Small (a few KB per page), per session.

**F13. Mixer observers are never removed.** The `didBecomeActive` observer token is discarded; the object is app-lifetime, so this is harmless.

**F14. Widget `TimelineView`s may tick under covering windows** (NEEDS VERIFICATION, #9). The cost per tick is one small redraw.

### Checked and fine (no change planned)
- **Mixer taps** only exist for apps not at 100 % and stop 2 s after silence.
- **TapTap** is fully gated: enabled, awake, display awake, unlocked, not in Low Power Mode.
- **Network services** merge in-flight requests and cache by age.
- **Widget animations and art** stop when covered.
- **Wallpaper playback** is gated on many signals.
- **Sparkline histories** are bounded at 60; clipboard history at 200, and its images are deleted when trimmed.
- **Island animations** run in WindowServer; the 0.15 s timer runs only while the island is open.
