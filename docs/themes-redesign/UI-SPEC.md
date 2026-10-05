# All Set — Complete UI Specification

Every number below was read from the source or measured on a 1400 × 900 render of the current build (branch `perf-audit`, 2026-10-05). All sizes are points (pt). Where a number is derived (a formula), the formula is shown so it can be re-checked. "Target" marks what the Themes redesign still has to build; everything else is **as built today**.

Companion to `All-Set-Design-Overview.md` (the shorter, structural version). Where the two disagree, this one is newer.

---

## 1. Product surfaces

| Surface | What it is | Size |
|---|---|---|
| Main window | Control center, always dark | Opens 1120 × 760, minimum 900 × 600, position remembered |
| Dynamic Island | Panel under the notch (virtual on notch-less screens) | Window 940 × 340; shape sizes in §10 |
| Desktop widgets | Draggable live cards on the desktop | 4 sizes, §11 |
| Menu bar item | Quick access | — |
| Live wallpaper | Video / generative art behind the desktop | Full screen |

Library counts: 54 widget kinds → 91 gallery entries in 9 categories; 57 complete themes holding 623 distinct widgets. The gallery header counts 714 widgets (91 + 623).

---

## 2. Design tokens (single source: `DesignTokens.swift`)

### Colour
| Token | Value |
|---|---|
| Canvas | rgb(0.027, 0.035, 0.059) ≈ #070910 |
| Canvas lift (top of canvas) | rgb(0.051, 0.067, 0.106) ≈ #0D111B |
| Surface · raised | white 5% |
| Surface · hover | white 8% |
| Surface · pressed | white 11% |
| Hairline border | white 8% |
| Ink · primary / secondary / tertiary | white 95% / 62% / 40% |
| Elevation shadow | black 35%, blur 18, y 8 (static only, never animated) |
| Selected control (filled pill) | white 92%, text black 88% |

The window is dark only. There is no light mode.

### Spacing
`xxs 4 · xs 8 · s 12 · m 16 · l 24 · xl 32 · xxl 48`; section gap **40**; page margin **24** below 1000 pt wide, **32** at 1000 and above.

### Corner radius
| Token | pt | Used for |
|---|---|---|
| control | 10 | text fields, small buttons, list rows |
| card | 16 | cards holding controls or text |
| media | 20 | wallpaper / theme / widget cards |
| panel | 20 | floating panels, sheets, carousel cards |
| hero | 28 | hero panels, large previews |
| capsule | full | every pill, search field, rail |

All rounded shapes use the continuous (squircle) corner style.

### Type (system font, SF Pro)
| Role | Size / weight | Tracking | Colour |
|---|---|---|---|
| Hero | 52 bold | −1.0 | primary (one per page at most) |
| Title | 28 semibold | −0.3 | primary |
| Section | 20 semibold | 0 | primary |
| Headline (card title) | 14 semibold | 0 | primary |
| Body | 13 regular | 0 | primary |
| Meta | 11 medium | 0 | secondary |
| Eyebrow | 11 semibold, uppercase | +1.2 | tertiary |

Component-specific sizes are in the component tables below.

### Motion vocabulary (`Motion.swift`)
| Name | Curve | Used for |
|---|---|---|
| quick | smooth 0.20 s | hovers, toggles, page pills |
| standard | smooth 0.30 s | content changing in place |
| gentle | smooth 0.60 s | slow cross-fades |
| responsive | spring response 0.35, damping 0.80 | lifting, picking, section switch |
| press | spring 0.25 / 0.65 | button give |
| bouncy | spring 0.40 / 0.60 | confirmations |
| reduced | ease 0.15 s | everything, when Reduce Motion is on |
| page veil | CA fade 0.9 → 0, 0.24 s ease-out | page switch (render server, not SwiftUI) |
| entrance | spring 0.5 / 0.86, rise 18 pt, scale 0.985 | content appearing |

Rule everywhere: animate opacity / transform only; no live shadow or blur on anything that moves; decorative motion pauses under Reduce Motion, Low Power, a hot Mac, or an occluded window.

---

## 3. Window frame

### Window backdrop (`WindowBackdrop`)
Linear gradient canvas-lift → canvas, top to 70% down. Over it, four radial glows drifting on Core Animation paths in a fixed 1000 × 700 space scaled to the window:

| Glow | Colour | Alpha | Diameter | Drift ellipse (centre / radii) | Period |
|---|---|---|---|---|---|
| Wide blue, top | rgb(.18,.42,1.0) | 0.13 | 900 | (360,120) / 220×70 | 46 s clockwise |
| Cyan, lower right | rgb(.10,.72,.95) | 0.10 | 760 | (760,420) / 180×120 | 58 s counter |
| Indigo, lower left | rgb(.42,.34,1.0) | 0.11 | 820 | (220,560) / 160×90 | 52 s clockwise |
| Lens | rgb(.45,.70,1.0) | 0.09 | 680 | (640,170) / 260×60 | 28 s counter |

Glow height is 72% of its diameter; bell falloff 1 / .82 / .55 / .28 / .09 / 0; each also "breathes" opacity 0.75 ↔ 1 over a quarter of its period. Frozen when paused.

### Floating navigation (`FloatingNav`) — total height 100 pt
Layout, top to bottom: 4 pt top pad · **row 1 (42)** · 8 gap · **row 2 (34)** · 12 gap below. Side padding = page margin.

| Element | Size | Detail |
|---|---|---|
| "All Set" wordmark | 15 bold, tracking −0.2 | leading edge of row 1 |
| Section capsule (row 1, centred) | height 42 = 4 pad + 34 buttons + 4 pad; radius 22 | Liquid-Glass (macOS 26) tint white 5%, lit rim 1.0 |
| Section button | height 34, horizontal pad 14, 13 semibold, icon 12 semibold + 6 gap | icon drops first when narrow; gap between buttons 2; ⌘1–⌘5 |
| Selected section | glass "lens" capsule, tint white 24%, interactive | slides via matched geometry |
| Desktop switches (row 1, trailing) | capsule radius 21, two 34 × 34 circle buttons, gap 2 | eye (show/hide widgets), hand (arrange); "on" = white 92% fill, black glyph |
| Page capsule (row 2, centred) | height 34 = 3 pad + 28 pill + 3 pad; radius 18; rim 0.65 | scrolls horizontally if the pills don't fit |
| Page pill | height 28, horizontal pad 12, 12 medium, icon 11 semibold + 6 gap | selected = glass lens |
| Count badge | 10 bold monospaced digits, min 16 × 16, pad 5 | white 20% (selected) / hover fill |
| Scrim behind nav | solid canvas-lift to row 2's lower edge, then fades to clear over the 12 pt gap | removed (opacity 0) when a page puts media under the nav |

Sections and their pages:

| Section | Pages (pill order) | Opens on |
|---|---|---|
| Island | Dynamic Island, Live Activities | Dynamic Island |
| Desktop | Themes, Widgets, Favorites, Wallpaper, Look & Layout, Wallpaper Options, On Your Desktop (count) | Themes |
| Workspace | Window Snapping, Workspaces | Window Snapping |
| Tools | Clipboard (count), Shelf (count), Sound Mixer, TapTap, AI Screenshot, Notes (open count) | Clipboard |
| System | Monitor, Lid Plane, General, About | Monitor |

Each section remembers the last page you were on. Detail pages (a theme set, a widget) keep their parent pill lit.

### Other window furniture
- Removed-widget undo bar: glass capsule radius 22, height 44, left pad 16, right pad 5, auto-hides after 8 s.
- Error banner (layout couldn't be saved): orange 22% fill, radius 10, pad 16 × 8.
- Page switch: pages swap instantly under the veil; below-the-fold content builds one frame later (`Deferred`).

---

## 4. Shared components

| Component | Spec |
|---|---|
| **GlassPanel** | Radius 20 (default) · padding 24 (default). macOS 26: Liquid Glass regular + white 5% tint; earlier: ultra-thin material + white 4% fill. Rim: 1 pt stroke gradient top-left → bottom-right white 42% @0, 10% @0.35, 4% @0.65, 18% @1, plus a top sheen white 7% → clear over the upper half. Never used on scrolling content. |
| **Pill button** (`.pill`) | Height 34, horizontal pad 16, 13 semibold, capsule. Fill hover-8% → 13% on hover → 11% pressed. Press scale 0.96. Disabled opacity 0.45. |
| **Prominent pill** | Same, fill white 92% (100% hover, 80% pressed), text black 88%. One primary action per area. |
| **Floating button** | Circle, default 34 (arrows 36, favourite 30), glyph 13 semibold; fill black 42% (60% pressed), hairline ring; press scale 0.92. |
| **Filter pill** | Height 28, horizontal pad 12, 12 medium, optional 11 icon; idle fill raised 5%, selected white 92% with black 88% text. |
| **Search field** | Height 34, horizontal pad 12, 13 regular, capsule, fill raised 5% + hairline; magnifier tertiary; clear button appears with text. |
| **Section header** | Title 20 semibold, optional meta subtitle 11 (gap 4), "See All" 11 medium secondary at trailing edge. |
| **Page header** | Optional eyebrow, title 28, body subtitle; actions on the trailing edge, bottom-aligned; gap 8 between lines. |
| **Media card** | Radius 20, hairline ring (selected: 2 pt white), hover scale 1.02, shadow elevation, optional title (headline) + meta below (gap 8, inset 4). |
| **Media rail** | Horizontal scroll, lazy, card gap 16, vertical pad 8, snaps to card edges (view-aligned). Default card width 260. |
| **Preview canvas** | Height 360 default, radius 28, raised fill + hairline. |
| **Hero section (bleed)** | Media edge to edge under the nav; top scrim black 32% → clear over 1.8 × nav height (max 50%); left scrim black 55% → clear to centre; vertical mask solid to 50%, 60% at 75%, clear at 100%; words bottom-left, max width 620, left pad = margin, bottom pad = overlap 48 + 32. Height = nav inset + visible (62% of viewport, clamped 320–560). |
| **Hero section (card)** | Height 420, radius 28, hairline, words padded 32, bottom/left scrims black 78% → 25% → clear. |
| **Empty state** | 34 light glyph (tertiary), headline, body, optional pill; max width 360; vertical pad 48. |
| **Flow layout** | Wrapping rows; spacing 12 (default), line spacing 12. |
| **Card grid metrics** | columns = floor((width + gap) / (min + gap)); card width = floor((width − gaps) / columns). |
| **Form page** | Grouped macOS form, hidden grey backdrop, header on the canvas outside the rounded boxes. |

---

## 5. Themes page (the redesigned page) — as built, 1400 × 900

Reference image: `docs/reference/concept2-reference.png` (in this package: `reference/reference-A-cinematic-carousel.png`). Review command: `./scripts/review-hero.sh` (writes `build/review/reference-vs-now.png`).

### 5.1 Vertical stack
```
  0 ─ window top
 33 ─ (title-bar strip in the render harness; the nav cluster itself is 100 pt)
133 ─ hero panel top  (= BleedLayout.topInset)
        16 pt padding
        carousel area 505 pt  (cards centred, ≈18 pt above and below the selected card)
        12 pt gap
        category rail 34 pt
        16 pt padding
716 ─ hero panel bottom   (panel height 583 = 0.76 × 767, clamp 350…640)
        content climbs 48 pt (overlap) onto the hero, then a 16 pt gap
        "Change the wallpaper too" switch row
 ~800 ─ Featured rail title
```
Viewport used: 1400 × 767 (900 − 133 inset). Panel height rule: `clamp(0.76 × viewport height, 350, 640)`; the hero takes most of the first screen and leaves the first rail's title in sight.

Panel width = viewport width − 2 × margin (32) = **1336**; measured **1319** in the render because the Themes/Wallpaper pages reserve a 17 pt scroll-bar track in the harness (macOS "show scroll bars: always"). On a Mac using overlay scrollers expect 1336. Left edge is 32 pt in both cases.

### 5.2 Hero panel
| Property | Value |
|---|---|
| Fill | white 4% (flat, no material) |
| Radius | 28 continuous |
| Border | 1 pt hairline (white 8%) |
| Inner padding | 16 top and bottom; carousel and rail 16 from the sides |
| Search field | top-right, 16 from top and right, width min(240, 25% of panel) = 240, height 34, prompt "Search themes…" |
| Indicator | top-left, 16 in: "n / 8" (meta 11) + 12 gap + 120 × 3 track (hairline) with a 15 pt thumb (120 ÷ 8) travelling the track |
| Arrows | 36 pt floating buttons, vertically centred, 16 from the carousel's left/right edges, always visible |

### 5.3 Carousel geometry (card width W = 351.6, height H = 468.8)
Cards are always 3:4. Selected card height = `min(panel − 102, 0.9 × (panel − 62))` → 90% of the room above the rail. Loops endlessly; reach 3 cards a side, 8 themes.

| Distance from centre | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Scale | 1.00 | 0.85 | 0.70 | 0.60 |
| Card size (pt) | 351.6 × 468.8 | 298.9 × 398.5 | 246.1 × 328.2 | 211.0 × 281.3 |
| Dim (black overlay) | 0 | 0.20 | 0.50 | 0.68 |
| Tilt about vertical axis | 0° | 14° | 20° | 24° (cap 26°) |
| Drop (dip) | 0 | 8 | 16 | 24 |
| Centre offset from middle | 0 | 311.8 | 563.5 | 766.5 |
| Step to next | 311.8 | 251.6 | 203.0 | — |
| Opacity | 1 | 1 | 1 | 1, fades 1 → 0 between 3 and 3.5 |

Perspective 0.5. Neighbours tuck 9 pt behind the card in front (step = half-widths − 9). Reduce Motion: no tilt, short dissolve instead of slide.

Input: arrow keys, trackpad swipe (axis-locked, vertical scroll passes to the page), wheel notch = one card, drag (4 pt minimum; lands within ±2 cards of the start), click a neighbour = go to it, click the centre = open the theme.

Timing: snap smooth 0.45 s (0.35 s Low Power); atmosphere crossfade easeInOut 0.70 s (Reduce Motion / Low Power: 0.15 s); words/badge fade 0.18 s; card edge-in third neighbour delayed 80 ms.

### 5.4 Card (`ThemePreviewCard`)
| Part | Spec |
|---|---|
| Picture | Full-bleed, pre-rendered 552 × 736 canvas: wallpaper + title word + hero widget + flanking small widgets |
| Radius | 20 (panel) |
| Bottom scrim | clear until 38%, black 50% at 70%, black 74% at 100% |
| Edge light | 1.5 pt in the theme's accent at 75% (selected); 1 pt at 30% (others) |
| Selected words (bottom-left, 16 in) | Name 32 bold, tracking −0.5, min scale 0.6 · count 12.5 medium secondary · 4 gap · actions row 8 above |
| Actions | "Apply Theme" prominent pill (34 high) + info (34 circle) + heart (34 circle), 8 gap; narrow cards drop info, then shorten to "Apply"; becomes "Turn Off" when active |
| Side words (bottom-left, 16 in) | Name 16 semibold + "n widgets" 11.5 medium |
| Compact (< 330 pt tall) | 12 in; name 24 / 14; no count, no badge |
| Badge | top-right, 12 in; "Featured" / "On your desktop", 11 semibold white, pad 10 × 5, black 42% + accent 30%, white 24% ring, capsule |
| Halo pictures | Shadow halo: spread 18, black 30% (+25% × glow), y 8. Glow halo: spread 36, accent at 55% × glow. Both pre-rendered 9-slice images, opacity only. |

### 5.5 Category rail
One horizontally scrolling capsule, height 34: 13 entries (All, Featured, Trending, New, Moodboards, Football, Music Icons, Popular, Minimal, Dark, Colorful, Developer, Favorites). Fill black 28% + hairline ring (no material). Strip padding 3; pill: horizontal 12, vertical 6, 12 medium, gap 2; selected = white 95% capsule with black 85% text, slides on a 0.15 s ease. Target (H4): separate compact pills, still one scrolling row, plain fills.

### 5.6 Atmosphere (behind the hero, fades into the window backdrop by 900 pt down)
Static layers only; the only animation is an opacity crossfade between two slots (A/B).

| Layer (bottom → top) | Spec |
|---|---|
| Base | canvas-lift → canvas @70% → clear @100% |
| Wallpaper haze | The theme's wallpaper at 384 × 240, saturation ×1.6, Gaussian blur σ = 384 ÷ 22 ≈ 17.5, bottom alpha fade, stretched to the frame; opacity 0.24 (0.09 if the wallpaper has no colour) |
| Primary pool | Elliptical gradient on the selected card's centre; stops 0.38 → 0.17 @0.38 → 0.05 @0.72 → clear, × glow intensity; size 1.3 × panel width by min(1.7 × panel height, room to the frame bottom) |
| Secondary haze | Elliptical, 0.17 × glow, 0.8 × panel width by 0.9 × panel height, offset +0.32 W, +0.30 H from the focus; white secondaries are blended 50% toward the primary |
| Vignette | 256 × 160 image, black up to 45% at the edges, fading out toward the bottom |
| Top darkening | black 30% → clear over 60% of the focus height, for the nav's text |

Focus point: x = page centre, y = inset + 16 + (panel − 16 − 62) ÷ 2 = 133 + 268.5 ≈ 401.

The atmosphere is drawn twice with the same numbers: behind the hero (scrolls) and once more cut to the nav's height and held still under it, so scrolled content never shows through the nav.

### 5.7 Theme accents (`ThemeAccent`: primary, secondary, glow 0.6–1.0)
Fallback order: curated accent → the theme's own accent → wallpaper dominant colour → warm gold (#D9B38C / #8A6A3A, glow 0.8). Colourless values are skipped (needs value > 0.3 and saturation ≥ 0.18).

| Theme | Primary | Secondary | Glow |
|---|---|---|---|
| Seven | #FF2D4A | #FFB347 | 1.0 |
| Red Seven | #FF3B30 | #FFD166 | 1.0 |
| Americana | #FF5E8A | #FF9A3C | 0.85 |
| Albiceleste | #4CC3FF | #FFFFFF | 0.9 |
| Slime Green | #7CFF3A | #1FD98A | 0.8 |
| Peach Fizz | #FF9E7A | #FFD0B0 | 0.65 |
| Matcha Morning | #A8C686 | #E8E2C8 | 0.6 |
| Leopard Noir | #D9A441 | #8A6A3A | 0.8 |
| Angelic | #CFE3FF | #FFFFFF | 0.7 |
| City Noir | #9FBBEA | #F2B66D | 0.85 |
| Hypnotic | #B9A2F5 | #FFFFFF | 0.85 |
| After Dark | #E3CF9A | #8A7A5A | 0.8 |

Look-derived accents are brightened so the brightest channel reaches 0.94.

### 5.8 Below the hero
- "Change the wallpaper too": right-aligned switch row, 12 above the first rail (section gap 40).
- Rails: Featured (the 8 carousel themes), Trending, then shelves that only show themes not already shown above; a category choice reorders the rails (chosen first); search replaces them with a grid (adaptive, min 280 wide, 16 gap, 24 row gap).
- Rail card: 300 wide, picture 1136:768 (≈ 300 × 203), radius 20 + hairline, below it name (headline 14) + "n widgets" (meta) on one line and a one-line inspiration (meta); hover scale 1.03 + shadow halo 35%; favourite heart (30 circle) appears on hover; press scale 0.98.
- Rail layout: title block (20 + 11), 12 gap, row with 16 between cards, 8 vertical pad.

### 5.9 Not yet built (targets from the Reference-Match v2 prompt)
| Phase | Still to do, with the numbers given |
|---|---|
| H3 lighting | Selected card: gradient edge, coloured + ground shadow, **neon edge strip** (2–3 pt vertical bar on the left edge, ~45% of height), **ground glow** ellipse (~60% of card width, 40 pt tall, 30–35%), **sheen** (white 10% → 0, diagonal, upper-left). Neighbours: own accent rim ~35% fading with distance, faint accent tint rising from the bottom. Glow never over text. |
| H4 glass | Fill white 4–6%, 1 pt gradient border (top-left white 18% → bottom-right 4%), inner top highlight 1 pt white 10%, radius 28–32, panel shadow black 40% blur 40 y 24; applies to hero panel, nav, rail, search, arrows. One grain tile (128 × 128) at page level, 3.5–5%. |
| H5 composition | ≥ 1200 pt wide: 1 centre + 2 neighbours a side; neighbour **gap 8–12 pt** (not tucked), overlap ≤ ~12%; neighbours dim ~0.1 / 0.3; stronger turn on the outer cards; cards cut to title + one centre widget + two small ones (hand-picked for all 8, contact sheet to approve); watermark-free wallpapers for Americana and Albiceleste. |
| H6 motion | Light follows the carousel (opacity 240–400 ms), background crossfade 600–800 ms, Instruments profile of page switch and carousel. |
| H7 | Final match at 1400 × 900, one wide, one narrow. |

---

## 6. Widget Gallery page (Desktop › Widgets)

Measured at 1400 × 900.

| Element | Spec |
|---|---|
| Header | Eyebrow "714 WIDGETS" (11 semibold, tracking 1.2) · title "Widget Gallery" 28 semibold · subtitle 13 secondary; search field top-right, width 280, 34 high |
| Category row | Filter pills (28 high, gap 8): All, From Themes, Time, Productivity, System, Developer, Lifestyle, Aesthetic, Football, Music, Mystic |
| Section | Title 20 + count meta, "See All" trailing |
| Grid | Cards min 300, gap 24 → 4 columns at 1400 (card width floor((1336 − 72) ÷ 4) = **316**) |
| Card | Fixed height **372**, radius 20, hairline + elevation; top: live widget preview on a gradient tile (fit 250 × 190 max); title row (kind icon + headline) with S / M / L size chips; one-line summary (meta); material chips row (scrolls); full-width "Add to Desktop" prominent pill (34 high) |
| Material chips | Photo, Solid, Frosted, Outline, Mesh, Apple Minimal, Liquid Glass, Dark Glass … |

Rows are built in explicit chunks so the page scrolls without per-card layout cost.

---

## 7. Wallpaper page (Desktop › Wallpaper)

| Element | Spec |
|---|---|
| Hero | Bleed hero: height = 133 + visible (62% of 767 = 475, clamp 320–560) = 608; the current wallpaper live, eyebrow "ON YOUR DESKTOP", hero title 52 bold, meta row (e.g. Abstract · Live · 1440p · 8.2 MB), actions "Turn Off" / "Options…" (pills 34 high), then source filter pills (Aerial Videos, Art, My Videos) |
| Section | "Aerial Videos" 20 + one-line description (13 secondary); quality menu (e.g. "4K, about 320 MB each") and download menu, right-aligned, 34 high |
| Category pills | All, Landscapes, Cities, Underwater, Space |
| Rails | Aerial cards 300 wide (16:9), my videos 280, art 180; "See All" |
| Grids | Adaptive: 260 min (videos, gap 16), 220 min (14 gap), 150 min (12 gap), 140 min (8 gap) |

---

## 8. Other Desktop pages

Only layout numbers that were read from the source are listed. Unmeasured items are marked.

| Page | Layout |
|---|---|
| Favorites | Adaptive grid, min 280, gap 16, row gap 24 |
| Look & Layout | Form page (grouped form on the canvas) — inner control sizes not measured |
| Wallpaper Options | Form page — inner control sizes not measured |
| On Your Desktop | Adaptive grid, min 240, gap 24; widget preview fit 200 × 140 in a 170 tall tile |
| Theme detail | Preview canvas 1136:768 (568 × 384 thumbnail), content max width 1080 |
| Widget customisation | Live preview fit 360 × 360 beside the options editor |

---

## 9. Workspace, Tools and System pages

Built from the shared components above (page margin 24/32, section gap 40; `GlassPanel` only for floating chrome). Per-page layout numbers were **not** measured for this document; the pages are:

Window Snapping · Workspaces · Clipboard (+ picker overlay) · Shelf · Sound Mixer · TapTap · AI Screenshot · Notes · Monitor · Lid Plane · General · About.

---

## 10. Dynamic Island

Always at the top of the screen under the camera notch (or a virtual one). Host window 940 × 340 (fits the largest state plus its shadow).

| State | Size |
|---|---|
| Closed | The notch's own size |
| Hover | notch + 14 wide, + 4 tall |
| Live activity (closed) | notch width + 2 × side, notch height + caption |
| Expanded · Home | 640 × 200 |
| Expanded · Tray | 700 × 210 |
| Expanded · Mixer | 700 × 240 |
| Expanded · Notes | 640 × 250 |
| Expanded · System | 860 × 300 |

Live activity side widths: now playing 42, volume 70, power / low battery 64, audio device 46 (+ 26 caption row), knock 48.

Shape radii: closed top 6, bottom 10 (16 with a caption); expanded top 14, bottom 28. Content inset: width − 44, height − notch height − 26. Tabs: Home, Tray, Mixer, Notes, System, with Core Animation open / close / tab-switch motion; Reduce Motion swaps springs for a short dissolve.

---

## 11. Desktop widgets

| Size | Dimensions (pt) | Grid |
|---|---|---|
| Small | 168 × 168 | 2 × 2 |
| Medium | 352 × 168 | 4 × 2 |
| Large | 352 × 352 | 4 × 4 |
| Extra large | 720 × 352 | 8 × 4 |

Gap between widgets 16, edge margin 8, snap grid 8. A widget can also be scaled and stretched within clamped ranges. Materials: Glass, Dark, Light, Tinted, Paper, Frosted, Clear, Outline, Art, Photo, Mesh. 15 design skins; 57 theme looks.

Categories (gallery entries): Time 9, Productivity 9, System 12, Developer 8, Lifestyle 8, Aesthetic 22, Football 11, Music 6, Mystic 6.

---

## 12. Accessibility and performance contract

- Reduce Motion: carousel flattens (no tilt), slides become 0.15 s dissolves, backdrop glows freeze, entrances become fades.
- Low Power Mode or a hot Mac: no card lift, no card glow, shorter snap, atmosphere fades 0.15 s.
- Occluded window: backdrop animation pauses.
- Text: primary 95%, secondary 62% and tertiary 40% white on near-black canvas; tertiary is for eyebrows and hints only.
- Every icon-only control has an accessibility label; selected states carry the selected trait.
- Navigation shortcuts ⌘1 – ⌘5; carousel ← →.

### Measured performance (this Mac, M4 MacBook Air, probes in `-probe`)
| Check | Result |
|---|---|
| Tests | 313 passing in 85 suites, 0 warnings |
| Carousel probe | 8 of 8 backdrops ready before the page is seen, **0 blurs while the carousel moves**, atmosphere in sync, routing / landing / looping checks pass in both motion modes |
| Themes scroll CPU | **42–43%** now vs **37–38%** on the old page (HEAD); p95 frame 19.2–19.7 ms vs 19.2–19.4 ms; 0 hitches in both |
| Themes page switch (main-thread hold, warm) | **96–137 ms** now vs **84–123 ms** old |
| Earlier phases (before the atmosphere) | scroll ≈ equal; switch ≈ 113 vs ≈ 95 ms |

Status: the atmosphere costs about 5 points of scroll CPU. A test flattening it into one layer has not been run; the temporary code for it was removed.

---

## 13. Rules any change must keep
1. Dark only; one backdrop for the whole window; pages never paint their own.
2. No brand logos, album art, trademarks or promo photos; themes are original; the user's player photos stay on their Mac and out of the repo.
3. No glow stronger than the reference, no rainbow neon, no pulsing or floating cards, no per-card grain or live blur.
4. Maximum two accent hues per theme; glow never over text.
5. Page switches must not get slower; scrolling must not drop frames.
6. Removed on purpose, do not return: Collections, Art, Home pages.
7. Navigation stays five places with pages beneath; a new page is added to both the section mapping and the pill list.
