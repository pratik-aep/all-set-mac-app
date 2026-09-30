# All Set

A Dynamic Island and system monitor for the MacBook notch, built with SwiftUI.

- **Notch hub**: hover over or click the notch to open a panel with Now Playing controls and live stats. While closed, live activities appear beside the notch: now playing, volume changes, charging, low battery, and audio output switches.
- **System monitor**: CPU per core (efficiency and performance cores shown separately), GPU, memory and pressure, network, disk space and I/O, SoC/SSD/battery temperatures, battery health, cycles and power draw.
- **Theme library**: complete desktops led by 14 photo moodboards (Leopard Noir, City Noir, Angelic, Hypnotic, After Dark, Streetwear, Gallery, Silver Faith, Peace of Mind, Cherry Night, Stardust, Soft Mono, Boho Sand, The Beginning): black-and-white photo walls, script words, sticker tiles and textured wallpapers, plus the original aesthetic setups. Browse, search, preview on the desktop, apply with undo. Card previews are rendered pictures, cached on disk.
- **Football & music worlds**: 17 more complete desktops: Seven, Galáctico, Albiceleste, O Rei, Samba Neon, Miami Pink and Matchday for football; Americana, Coastline, Velvet Noir, Rage Mode, Sad Hours, Slime Green, Deep Blue, Crimson Nights, Vamp Punk and Blond Summer for music. Original designs inspired by eras and moods fans know; they name no one and use no official photos, crests, logos, album art or lyrics. Photos are CC0 (Openverse), wallpapers are generated (new Stadium Lights, Palm Sunset and Smoke styles), and "Use My Photos…" fills every photo slot with your own pictures: kept per theme on this Mac only (theme-photos.json), with player cards lifting the player out of the photo with Vision. Twelve football worlds now, including Red Seven, Wonderkid, Bleu Royal, Milano Nights and Hall of Fame.
- **Live football and music widgets**: Shirt (your name and number, seven kit patterns), Player Card (foil rating card with your photo and stats), Tactics Board (formation with the ball in play), Scoreboard (LED board counting down to kickoff, or a final score), Milestone, Cassette (reels turn while music plays), VHS (a photo as home video, tracking lines and REC), Visualizer (bars, waveform or ring), Ticket and Word Art (chrome, gold, neon, glitter, fire, ice, holographic). Glow, float, shine, sparkle and bars run in Core Animation, so a whole desktop of them idles at about 1% CPU.
- **Design themes**: 15 design languages that draw every widget through one theme engine (`DesignTheme` + `WidgetStyle` + shared components), each in light and dark with an Automatic setting: Apple Minimal, Liquid Glass, Dark Glass, Aurora, AMOLED, Cyberpunk, Terminal, Retro Macintosh, Japanese Zen, Editorial, Brutalist, Neumorphism, Paper, Monochrome and Dynamic Wallpaper (a subtle accent taken from your desktop picture). Per widget: theme, appearance, accent, transparency and refresh behavior.
- **Widget catalog**: about 50 widgets in Time, Productivity, System, Developer, Lifestyle and Aesthetic, registered in `WidgetCatalog` so a new one is a view plus an entry. New this round: Minimal and World clocks, Date, Next Event, Daily Goals, Habit Tracker, Reading Progress, System metrics (CPU, Memory, Disk, Storage, Network, Wi-Fi, Battery Health, Uptime, Status), GitHub (Contributions, Activity, Pull Requests, Issues, Repository, CI/CD), API and Server Status, Air Quality, and the Classic Mac, Ensō and Magazine Cover aesthetic widgets. Weather, System Monitor and GitHub come in Extra Large too.
- **Deep links**: `allset://open/monitor`, `allset://widget/<id>`, `allset://arrange`, `allset://theme/<id>`, `allset://focus/start|pause|reset`, for Shortcuts, Raycast and scripts.
- **Aesthetic setups**: thirteen whole-desktop looks, filterable by dark or light: Cloud Nine, Pink Latte, Coquette (light); Good Things, Grunge, Diva, Luxe Noir, Sepia Swag, Vigilante, Neon Nights, Dark Academia, Midnight Lo-fi, Goth (dark). "Apply Look" restyles every widget (card, colors, font, corners) and sets a matching live wallpaper; "Use Full Setup" lays out the theme's own starter set of widgets, with Undo.
- **Desktop widgets**: Clock (digital, analog, stacked, words or flip, any time zone), Calendar (month and upcoming events), Weather (any city, hourly and 5-day), System, Battery, Now Playing and sticky Notes. Each comes in small, medium or large, on a Glass, Dark, Light, Color, Solid (paper), Frosted, Outline or No Card style, with your own card, text and highlight colors. Choose the font and corner roundness for all of them. Arrange mode lets you drag widgets anywhere; they snap to an 8-point grid.
- **Aesthetic widgets**: Photo (your pictures, ~1,000 Unsplash photos or generated art, with filters, Polaroid, inset, collage and film strip frames, captions and slideshows), Live Scene (animated art with the time, date or your words on top), Quote (including Poster, Chunky, Editorial, Gothic and Luxe type), Neon Sign (glowing, flickering words), Countdown, Sticker (a big star, heart, sparkle or emoji: soft, glossy, chrome, die-cut or outline) and Shortcuts (cute icons that open apps and sites). Any widget can sit on one of 440 generative artworks (20 styles × 22 palettes), still or animated.
- **Focus & To-Do widgets**: To-Do (the notch's Notes as a checklist), a Pomodoro Focus Timer, a Stopwatch (running timers survive quitting the app) and Year in Dots. The System section adds a Terminal widget: live stats in green on black.
- **One main window**, opened from the Dock icon: a Dynamic Island page (live miniature, "Try it on your notch" buttons and every island setting), the widget gallery, art and photo library, a customizer for each widget on the desktop, a live system monitor, and general settings. "Show in Dock" can switch the app back to menu-bar-only.
- **Live wallpaper**: any of the 440 artworks animated (including Night Skyline with a searchlight, Embers, Cloud Nine, Floating Hearts, Hypnotic spiral, Leopard, Film Grain and Checkerboard), a photo with slow cinematic drift, or your own looping videos, drawn behind desktop icons. It pauses when covered, locked, asleep, in Low Power Mode or (optionally) on battery, and sets a matching still as the system wallpaper (your original comes back when you turn it off).
- **Workspace manager**: window snapping by keyboard (Rectangle's shortcuts: ⌃⌥ arrows for halves, ⌃⌥U/I/J/K quarters, ⌃⌥D/F/G thirds, ⌃⌥↩ maximize, ⌃⌥C center, ⌃⌥⌫ restore, ⌃⌥⌘ arrows to move between displays; all re-recordable), optional gaps, drag-to-edge snapping with a preview (when macOS's own tiling is off), and saved workspaces that reopen apps, put their windows back and hide everything else, from a click, the menu bar or a shortcut.
- **Clipboard & Shelf**: clipboard history (text, links, images, files; password managers and private copies skipped) with a ⌃⌥V picker that searches and pastes into the app in front, on-device OCR for copied images, and a Shelf where files dragged onto the notch wait until you drag them out. The notch's Tray tab shows both.
- **Photo search** across Creative Commons photos (Openverse), alongside ~1,000 featured Unsplash photos. It understands aesthetics ("coquette", "dark academia", "lo-fi" become concrete searches that pages take turns through), fixes typos, shows matching built-in art instantly, paces requests under Openverse's limit, and falls back to cached results when offline.
- **Menu bar panel** with the same stats.

On screens without a notch, All Set draws a virtual one in the menu bar.

## Requirements
- macOS 14.2 or later (developed on macOS 26, Apple Silicon)
- Xcode, for the Swift 6 toolchain and SDK
- VS Code with the **Swift** extension (`swiftlang.swift-vscode`)

## Commands
| Command                  | What it does                                                    |
|--------------------------|-----------------------------------------------------------------|
| `make run`               | Build and run the debug app                                     |
| `make preview TAB=home`  | Run with the notch panel held open (`home`, `tray` or `system`) |
| `make test`              | Run the tests                                                   |
| `make open`              | Build `build/AllSet.app` (release) and open it                  |
| `make clean`             | Remove build output                                             |
| `./scripts/setup-signing.sh` | One time: creates a local signing certificate so macOS remembers Accessibility permission across rebuilds |

In VS Code, **F5** builds and debugs the app, and the *Debug AllSet (notch open)* launch configuration holds the panel open. **Cmd+Shift+B** builds. Other commands are under *Terminal → Run Task*.

`.build/debug/AllSet -renderDesign /folder` captures every design theme in light and dark, and every catalog entry at every size, from real (hidden) windows, so glass draws as it does on the desktop.

While developing, `.build/debug/AllSet -widgetsFile /tmp/layout.json` tries a widget layout without touching your real one, and `-arrangeWidgets YES` starts in arrange mode, and `-openPage island|themes|gallery|art|photos|widget|monitor` opens the window on a page.

Use `make run` rather than `swift run`: `swift run` builds only the app, not the media helper it loads.

## Layout
```
Sources/
  AllSet/              The app: notch panel, menu bar, settings (SwiftUI + AppKit)
    Notch/             NotchController (window, hover, activities) and its views
    Widgets/           DesktopWidgetController (one desktop-level window per widget), widget views, ArtView
    Studio/            Widget gallery, library pages, widget customizer
    Wallpaper/         WallpaperController (desktop-level window per screen) and wallpaper pages
    Workspace/         Accessibility wrappers, hot keys, WindowManager, WorkspaceController, pages
    Clipboard/         ClipboardMonitor, the ⌃⌥V picker, OCR, Clipboard and Shelf pages
    Design/            Design tokens, shared components and the floating navigation
    MainWindow.swift   The main window: its pages, under the floating navigation
  AllSetCore/          Everything testable without UI
    System/            CPU, GPU, memory, network, disk, battery, temperature readers
    Media/             Now Playing: MediaController and the helper protocol
    Widgets/           Widget models, themes (WidgetTheme), timers, layout math, and WidgetStore (saved to
                       ~/Library/Application Support/AllSet/widgets.json)
    Weather/ Calendar/ Open-Meteo client and EventKit events for widgets
    Aesthetics/        Art styles and palettes, photo sources, ImageLibrary, PhotoSearch (Openverse)
    Search/            SearchMatch (fuzzy names) and AestheticSearch (aesthetic vocabulary, typos, pacing)
    Wallpaper/         WallpaperStore: live wallpaper settings and imported videos
    Workspace/         Window layout math, snap zones, shortcuts, WorkspaceStore
    Clipboard/         ClipboardStore (history) and ShelfStore
    Audio/ Power/      Volume/output device and power source monitors
  MediaHelper/         Objective-C helper that /usr/bin/perl loads (see below)
  CPrivateAPIs/        Declarations for private IOKit HID functions (temperatures)
Tests/AllSetCoreTests  Unit tests, plus live checks against this Mac and the helper
Resources/              Info.plist and AppIcon.icns (redraw it with `swift scripts/make-icon.swift`)
scripts/build-app.sh   Packages the release build into build/AllSet.app
```

## How the tricky parts work
- **Now Playing.** macOS 15.4 and later only give Now Playing info to Apple-signed processes. `MediaController` starts `/usr/bin/perl`, which is Apple-signed, with a short loader script. The script loads `libAllSetMediaHelper.dylib`, which reads MediaRemote and sends JSON lines back over stdout. Commands such as play/pause and seek go the other way over stdin. This is the same workaround other notch and music apps use, and a future macOS update could close it.
- **Temperatures** come from the IOKit HID event system through a few exported but undeclared functions (`CPrivateAPIs`), as in [Stats](https://github.com/exelban/stats).
- **The notch window** is a borderless, non-activating panel placed just above the menu bar. It only accepts mouse clicks while the pointer is over the shape. Everywhere else, clicks go through to the status items next to the notch.

Because of these, All Set can't be sandboxed and won't pass Mac App Store review. It's meant to be distributed directly, signed with Developer ID and notarized. Local builds are signed with the self-signed "All Set Development" certificate from `scripts/setup-signing.sh` (ad hoc if it's missing).

Weather data by [Open-Meteo.com](https://open-meteo.com) (CC BY 4.0). Photos by Unsplash photographers, served by [Picsum](https://picsum.photos); search by [Openverse](https://openverse.org).
