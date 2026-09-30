# All Set — Everything In The App

A complete inventory of what All Set contains: every feature, page, widget, theme, and style choice. For build/architecture notes, see the code; this file is about *content* — what a user sees and can pick.

---

## 1. The app's shape

All Set is a macOS menu-bar/Dock utility built from these pieces:

- **Dynamic Island / notch hub** — a fake island under the camera notch (screens without a notch get a virtual one in the middle of the menu bar), with five tabs.
- **Desktop widgets** — draggable live cards and freeform pieces on your desktop, from a gallery of 91 catalog entries across 9 categories, arranged individually or applied as a whole-desktop **theme** (49 of them).
- **Live wallpaper** — art, photo, or video, matched to the system wallpaper.
- **Workspace manager** — hotkey window snapping and saved workspaces.
- **Clipboard & Shelf** — clipboard history, a picker, OCR, and a drag-and-drop shelf.
- **Per-app volume mixer** — Core Audio taps, per-app volume, output switching.
- **TapTap** — knocks on the Mac itself (single/double/triple, via the motion sensor) mapped to actions.
- **AI Screenshot editor** — Claude-powered structured edits, OpenAI image redraw.
- **System monitor** — CPU, GPU, memory, disk, network, battery, thermal, top apps.
- **Settings** — general, widgets, notch, wallpaper.

Main window pages (`AppPage`): Dynamic Island, Activities, Themes, one Theme Set's detail page, Widget Gallery (per category or all), Art library, per-widget customization, widget appearance, Wallpaper, Wallpaper Options, Window Snapping, Workspaces, Clipboard, Shelf, Mixer, Knocks (TapTap), Notes, AI Screenshot, System Monitor, General settings, About.

---

## 2. Dynamic Island / Notch

Five tabs, each with its own Core Animation–driven open/close/tab-switch motion:

1. **Home** — Now Playing (artwork and controls) beside quick system stats.
2. **Tray** — files parked on the shelf (drop any file on the island) and what was copied recently.
3. **Mixer** — per-app volume sliders, output device switch.
4. **Notes** — a quick note-taking pane (keyboard-focusable).
5. **System** — CPU, GPU, memory, network, disk, battery cards, plus a Top Apps panel (Energy / Memory modes with a "Clear Cache" action).

Also: live activities (volume HUD, audio-device switch, battery/charging events, low-battery warning, knock feedback), hover-to-swell, click-to-expand, Reduce Motion fallback (short dissolve instead of springs).

---

## 3. Widget Gallery — 91 entries across 9 categories

Widgets are built from **54 underlying kinds**; a catalog entry is a kind pre-configured for a purpose (e.g. "CPU" and "Wi-Fi" are both the `metric` kind). Sizes: **Small, Medium, Large, Extra Large** (not every kind supports every size). Every widget can use a **Material** (Glass, Dark, Light, Tinted, Paper, Frosted, Clear, Outline, Art, Photo, Mesh) unless it paints its own background.

### Time (9)
Digital Clock · Minimal Clock · Analog Clock (ticking hands) · World Clock (multiple cities) · Flip Clock (split-flap tiles) · Date · Countdown · Stopwatch · Year in Dots

### Productivity (9)
Calendar (EventKit) · Next Event · To-Do · Focus Timer (long deep-work) · Pomodoro (25/5×4) · Goals (daily) · Habits · Notes · Shortcuts (app/action launcher)

### System (12)
System Monitor · CPU · Memory · Disk (reads/writes) · Storage (free space) · Network (down/up speed) · Wi-Fi (signal + speed) · Battery · Battery Health (capacity/cycles) · Uptime · System Status (at-a-glance) · Terminal (green phosphor look)

### Developer (8)
GitHub Contributions · GitHub Activity · Pull Requests · Issues · Repository Status (stars/issues/last push) · CI/CD Status (GitHub Actions) · API Status · Server Status

### Lifestyle (8)
Weather (Open-Meteo) · Air Quality · Sunrise & Sunset · Moon Phase · Music (Now Playing) · Quote (affirmations and other sources) · Photo · Reading (current book)

### Aesthetic (22)
Classic Mac (retro window chrome) · Enso (zen circle) · Magazine (editorial layout) · Poster Quote (huge words on wallpaper) · Neon (glowing tube sign) · Sticker · Polaroids · Lock Screen (depth effect) · Live Scene (animated generative art) · Vinyl (spinning record) · Chrome Words / Gold Script / Neon Word / Glitter Word (word-art finishes) · Hypnotic Spiral / Red Spiral (op-art vortex) · Chrome Heart / Angel Wings / Gothic Cross / Chrome Butterfly (metal charms) · Perfume Label / Noir Label (fragrance-bottle labels)

### Football (11)
Shirt / Striped Shirt / Canary Shirt (jerseys) · Player Card / Legend Card (pearl foil) / Neon Card (glass) · Tactics Board (pitch) · Scoreboard / Final Score · Goal Counter (milestone tracker) · Match Ticket

### Music (6)
Cassette (turning reels) · VHS (tracking-band tape look) · Visualizer / Ring Visualizer / Waveform (audio-reactive bars) · Concert Ticket

### Mystic (6)
Card of the Day (tarot, changes daily) · Today's Aura (drifting color + mood) · Star Sign (your zodiac constellation) · Magic Ball (tap to shake, get an answer) · Candle / Study Candle (flickering flame)

### Underlying widget kinds (54 total)
clock · calendar · weather · system · battery · nowPlaying · note · photo · ambient · quote · countdown · lockScreen · vinyl · moon · daylight · polaroids · todo · focus · stopwatch · shortcuts · sticker · neon · terminal · dots · metric · date · nextEvent · goals · habits · reading · github · status · airQuality · retroWindow · enso · magazine · jersey · playerCard · pitch · scoreboard · milestone · cassette · vhs · visualizer · ticket · wordArt · spiral · charm · label · aura · tarot · zodiac · eightBall · candle

### Live / animated widgets (Core Animation, near-zero CPU, pause when covered)
Analog clock hands, flip clock, stat rings/bars, cassette reels, VHS tracking band, visualizer bars/ring/waveform, jersey shine, scoreboard flips, milestone counter, spiral rotation, charm shine + sparkles, aura color drift, zodiac star twinkle, candle flame flicker, ambient generative art (GPU shader), drifting/glowing photo art.

---

## 4. Whole-Desktop Themes — 49 total

Applying a theme replaces every widget on the desktop and matches the wallpaper. All are **original designs** — inspired by an era/genre/mood, never reproducing a real logo, celebrity photo, or trademark. Real names (when referenced) only ever appear in hidden search tags, never in visible UI text.

### Moodboard themes (14) — from Pinterest/TikTok desktop-aesthetic references
Leopard Noir · City Noir · Angelic · Hypnotic · After Dark · Streetwear · Gallery · Silver Faith · Peace of Mind · Cherry Night · Stardust · Soft Mono · Boho Sand · The Beginning

### Fandom-inspired themes (22) — football & music worlds
**Football:** Seven · Galáctico · Red Seven · Wonderkid · Bleu Royal · Milano Nights · Hall of Fame · Albiceleste · O Rei · Samba Neon · Miami Pink · Matchday
**Music:** Americana · Coastline · Velvet Noir · Rage Mode · Sad Hours · Slime Green · Deep Blue · Crimson Nights · Vamp Punk · Blond Summer

(Player photos are user-supplied only — "Use My Photos…" lets a user drop their own pictures into every photo slot; the app never bundles or scrapes real people's photos.)

### Gen Z / dark aesthetic themes (13) — original "worlds" with full kits
Cloud Nine · Good Things · Pink Latte · Coquette · Grunge · Diva · Luxe Noir · Sepia Swag · Vigilante (Batman-vibe, no DC branding) · Neon Nights · Dark Academia · Midnight Lo-fi · Goth

Each theme carries a name, tagline, description, philosophy, an inspiration note (dev-only), its own wallpaper, a `MotionLanguage`, and a `WallpaperAdaptation`.

---

## 5. Design Themes (widget skins) — 15

Applied per-widget or per-desktop as a coherent visual system, independent of the whole-desktop themes above:

Apple Minimal · Liquid Glass · Dark Glass · Aurora · AMOLED (true black) · Cyberpunk · Terminal (phosphor green) · Retro Macintosh (1984 window) · Japanese Zen · Editorial (newsprint) · Brutalist · Neumorphism · Paper · Monochrome · Dynamic Wallpaper (borrows wallpaper's accent color)

---

## 6. Generative Art — 23 styles × 41 palettes (943 combinations)

**Styles:** Glow (blobs) · Aurora · Sunset · Waves · Synthwave · Dunes · Stars · Bokeh · Lava · Rain · Orbits · Stripes · Clouds · Hearts · Spiral · Leopard · Film (grain) · Checker · Skyline · Embers · Stadium · Palms · Smoke

**Palettes:** Sunset · Ocean · Aurora · Neon · Midnight · Lavender · Forest · Desert · Mono · Pastel · Peach · Candy · Sky · Blush · Coquette · Diva · Mocha · Matcha · Cherry · Shadow · Ember · Emerald · Floodlit · Red/Green · Sky/White · Canary · Royal · Miami · Classic Red · Rossoneri · Blaugrana · Bleu · Hall of Fame · Americana · Coastline · Slime · Rage · Sad Blue · Crimson · Opium · Blond (the last dozen built for specific fandom themes)

Art renders on GPU (Metal shader) for moving pieces and via Canvas for still ones; used for Live Scene widgets, backgrounds, and wallpapers.

---

## 7. Photos & Wallpaper Search

Photo search and My Photos no longer have their own pages or Live Wallpaper tabs; they live in the picture picker of Photo, Polaroid and VHS widgets.

- **Two sources searched together:** Wallhaven (≈1M wallpapers — films, games, anime, cars, space; SFW-only) and Openverse (free-licensed photos: WordPress Photo Directory, Rawpixel, Flickr).
- **Understands nicknames:** "jjk" → Jujutsu Kaisen, "lambo" → Lamborghini, "gta 6" → Grand Theft Auto VI, and ~120 more.
- **Aesthetics become concrete searches:** Coquette, Y2K, Clean Girl, Dark Academia, Cottagecore, Fairycore, Grunge, Soft Girl, Old Money, Vaporwave, Cyberpunk, Lo-fi, Kawaii, Baddie, Coastal, Coastal Grandma, Boho, Indie, Gothic, Cozy, Barbiecore, Preppy, Skater, Anime, Minimalist, Luxury, Vintage, Retro, Dark/Gotham/Villain Era/Midnight/Dark Feminine/Night.
- **Typo correction**, **exclude words** (`-word`), **filters:** Sort (Best Match/Most Loved/Top This Year/Newest/Shuffle), Size (Any/HD/4K/Sharp on This Screen), Shape (Any/Landscape/Portrait), 18 color swatches.
- **Topic chips:** Marvel, Anime, Supercars, JDM, Gaming, Batman, Star Wars, Space, Cyberpunk, Nature, Minimal, Dark, Formula 1, Studio Ghibli, Motorcycle, plus all aesthetics above.
- **Recent searches** row; right-click a photo to open its source page or full size.
- **140+ curated licensed photos** (CC0/PDM/CC-BY) bundled for football/music theme photo slots, plus Picsum/Unsplash picks for the default "Photos" tab.
- **My Photos:** user-imported pictures, stored locally, used to personalize any theme's photo/player-card/VHS/polaroid slots.

---

## 8. Live Wallpaper

- **Art** (generative, any style×palette combo, animated or still)
- **Photo** (from search or My Photos, with slideshow interval)
- **Video** (Apple's aerial/scenic catalogue via sylvan.apple.com)
- Runs at desktop-window level, paused unless a real amount of desktop is visible (`ScreenCoverage`), matched to system wallpaper, shared player instances across screens for efficiency.
- **Fit to Screen:** themes/widget layouts scale and center to fill any screen size (0.7×–1.6× range), with a dedicated Settings control and `allset://fit` deep link.

---

## 9. Workspace Manager

- Global hotkeys (Rectangle-style defaults) for 20 window positions: Left/Right/Top/Bottom Half; Top Left, Top Right, Bottom Left, Bottom Right; First/Center/Last Third; First/Last Two Thirds; Maximize, Almost Maximize, Center; Restore; Next/Previous Display.
- Accessibility-API window moves; drag-to-snap disabled automatically when macOS's native edge tiling is on.
- **Saved Workspaces** — capture and restore window arrangements across apps.

---

## 10. Clipboard & Shelf

- Clipboard **history** with search.
- **⌃⌥V picker** overlay, auto-paste via synthetic ⌘V.
- **Vision OCR** — extract text from copied images.
- **Shelf** — drop files on the island to hold them in the Tray tab, then drag them out wherever they're needed.
- **PDF maker** from the shelf.

---

## 11. Per-App Volume Mixer

- Core Audio process taps — real per-app volume control (macOS 14.2+).
- The island's Mixer tab plus a full Sound Mixer page.
- Output device switching.
- Volume-change and audio-device-change live activities (with an on/off setting each).

---

## 12. TapTap (Knock Gestures)

- Single, double, and triple knock detection via the SPU accelerometer (custom driver wake sequence).
- Each knock count maps to an app launch or an action — kept deliberately simple (three rows, no per-app rule builder).
- Live activity feedback in the notch on a recognized knock (success/fail).

---

## 13. AI Screenshot Editor

- Has its own page in the main window, and a shortcut in the island's header.
- **Claude (claude-opus-5)** — structured, conversational edits to a screenshot, referencing the original image plus edit history (cached for follow-ups).
- **OpenAI (gpt-image-1)** — full image redraw option.
- Version history with undo; needs the user's own API key(s).

---

## 14. System Monitor

Live readings, each with history sparklines where relevant:
- **CPU** — total %, per-core (efficiency vs. performance), temperature, thermal state.
- **GPU** — utilization, memory in use.
- **Memory** — used/total, app/wired/compressed breakdown, pressure, swap.
- **Network** — download/upload rates with history.
- **Disk** — read/write rates, free/total space, SSD temperature.
- **Battery** — percent, charging state, health, cycle count, power draw, temperature, Low Power Mode flag.
- **Top Apps** — by Energy (watts/CPU%) or Memory, with a one-click **Clear Cache** (disk cache purge).
- Optional CPU % next to the menu-bar icon.

---

## 15. Settings

- **General** — show in Dock, show menu-bar icon, CPU % in the menu bar, launch at login, temperature unit (°C/°F), refresh interval.
- **Dynamic Island** — on/off, which display it's on, start tab (Home/System/Last), expand on hover + hover delay, haptic feedback; live-activity toggles for Now Playing, volume, battery and audio device.
- **Widgets** — show on desktop, Arrange mode, Size slider (0.7×–1.6×) + Fit to Screen, font (Default/Rounded/Serif/Mono/Tall/Wide), corner roundness, the desktop's theme and design theme.
- **Wallpaper Options** — per-source settings (art/photo/video) and pause rules.
- **Motion** — follows the system's Reduce Motion (springs become short dissolves) and pauses animation in Low Power Mode.

Text styles available on aesthetic widgets: Classic, Modern, Bold, Elegant, Script, Handwritten, Typewriter, Poster, Chunky, Editorial, Gothic, Luxe (12 styles, each with matched typography/tracking/case).

---

## 16. Deep Links (`allset://`)

For Shortcuts, scripts and automation (used instead of App Intents, which SwiftPM builds can't carry):

| Link | Does |
|---|---|
| `allset://open/<page>` | Opens a page of the main window |
| `allset://widget/<id>` | Opens one desktop widget's settings |
| `allset://arrange` | Turns on Arrange mode |
| `allset://fit` | Fits the widgets to the screen |
| `allset://theme/<id>` | Applies a theme |
| `allset://focus/start` · `pause` · `reset` | Controls the Focus timer |

---

## 17. Distribution

- Free, monetization undecided.
- Ships outside the Mac App Store (Developer ID + notarization) — required by the notch overlay, private IOKit temperature APIs, and the Now Playing workaround.
- Bundle ID: `com.pratik.allset`. Name: **All Set**.

---

*This file is a content inventory, not a changelog — see git history and code comments for how things were built.*
