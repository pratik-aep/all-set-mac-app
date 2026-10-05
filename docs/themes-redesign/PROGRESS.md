# Themes redesign — progress

Environment: Linux cloud container, **no Swift toolchain**. Nothing below was built, run or screenshotted.
Branch: `claude/inspiring-fermat-5bibd1` (the owner's local carousel hero is not in this tree; not recreated).

## Phase 0 — orientation (done)

Reference images viewed:

**reference-B (primary)** — full Themes page in the window frame, with callouts 01–06 on the right.
1. Floating nav on top (Island / Desktop / Workspace / Tools / System; sub-pills Themes … On Your Desktop) over a purple mountain photo.
2. Directly under it, a rounded glass filter bar: 13 icon-less pills (All selected = white fill), search field, "Newest ⌄" dropdown, square layout toggle.
3. "Featured": ≈40 pt rounded icon tile (star), bold title, one-line description; right: `‹ ›` square buttons and a "See All" pill.
4. Five equal theme cards (≈252 × 175, radius ≈20): preview fills the card, name bold + "n widgets" bottom-left, heart top-right and bottom-right, first card has a bright blue ring.
5. Trending row, same pattern (flame tile).
6. Moodboards: five wider cards (≈250 × 125) with collage, title, "n themes", circular arrow bottom-right, "Most Popular" badge on Aesthetic.
7. Football row starts at the bottom, identical pattern.
8. Dark navy canvas, soft coloured light at top, hairline borders, ≈40 pt between sections, 16 pt between cards.

**reference-A** — "Concept 2 Cinematic Carousel": 3D carousel with tilted cards, glass nav + search, pill rail under it; "Concept 3 Immersive Preview" beneath. Used only for finish: glass chrome, coloured light behind content.

**current-ui-frame-t1** — carousel hero panel with `1 / 8`, search top-right, arrows, 13-pill capsule, "Change the wallpaper too" switch, Featured rail starting at the bottom.
**t5 / t9 / t13** — scrolled states: plain 300 pt shelves (Featured, Trending, …) with name, count and 2-line description *under* each picture; "n themes" under each section title; a small "See All" text link.

Code located: `Studio/ThemesPage.swift` (first pass present), `Studio/ThemePreviews.swift`, `Design/DesignComponents.swift`, `Design/WindowBackdrop.swift`, `Design/AppNavigation.swift`, `Components/Motion.swift`, `PerformancePolicy` (`services.ui.performance`).
No carousel files exist in this tree.

Skipped (no toolchain): build, test run, baseline probes, baseline screenshots.

## Phase 1 — audit (done)
`AUDIT.md` written (22 rows). Biggest gaps: no layout toggle, sliding indicator, scrolling-under bar, glass rims, atmosphere, row position tracking, narrow category cards, See All on every row.

## Phase 2 — page structure and filter bar (done)
Themes page now starts on the pinned filter bar (46 pt, glass finish, 13 icon-less pills with a sliding `matchedGeometryEffect` indicator on a 0.18 s ease, search 120–200 wide, sort menu, 34 pt square layout toggle rails ↔ grid). Rows scroll under it beneath a canvas fade. "Change the wallpaper too" + undo banner is the slim right-aligned row above the first section. `ui.mediaUnderNavigation` is never set by this page, so the nav scrim stays on. `BleedScrollPage` untouched.
Note: this commit already references `ThemeRow` / `ThemeCategory` / new `ThemeCategoryCard(category:)` introduced in phases 3–4; nothing compiles here anyway.

## Phase 3 — headers, rows, cards (done)
`ThemeSectionHeader` (40 pt tile, 20 semibold title, meta line, square glass `‹ ›`, See All pill). New generic `ThemeRow` (252 pt cards, gap 16, `scrollPosition(id:)` so arrows follow drags, `viewAligned` snap, ←/→ keys on a focused row, bleed so lift/ring/shadow aren't clipped); `ThemeRail` wraps it for themes. `ThemeTile`: press 0.98, hover lift 1.03 (off with Reduce Motion or saver tier), accent edge + three-stroke static glow behind the card (opacity only, off in saver tier), active ring + "On your desktop" badge, per-theme VoiceOver labels.

## Phase 4 — categories, grid/search states, remaining rows (done)
Moodboards is a `ThemeRow` of five 252 × 126 `ThemeCategoryCard`s (lead theme preview, title, "n themes", round arrow, "Most Popular" on Aesthetic), same header and arrows as every row; clicking one selects its filter; they claim no themes. "See All" on rows with no filter (Colour & Light, Night, Dreamy, Minimal & Designer, More Setups) now opens a grid of just that row via `ThemeFocus`; any pill clears it (All pill is unselected while a row is focused). Grid mode (filter ≠ All, search text, focus, or the layout toggle): adaptive min 240, gap 16, header with name and count, empty states for no results / no favourites, sort applies. Narrow windows: pills scroll horizontally, search shrinks to 120, fixed-width cards mean fewer per row.

## Phase 5 — finish (done)
`ThemeAtmosphere`: two static radial accent pools (30% / 14%) from the desktop theme's accent (or the first featured theme), reaching ≈ 720 pt down, crossfading on change (0.7 s; 0.15 s under Reduce Motion / saver tier), no blur layers. Glass: bar, sort menu, layout toggle and row arrows share one finish (plain 28% black fill, 1 pt top-left → bottom-right white 18 → 4% rim, 1 pt inner top highlight at 10%, static bar shadow). Reduce Motion: no hover lift, `withMotion` dissolves; saver/hot: no lift, no glow. VoiceOver: pills carry the selected trait, arrows say "Previous/Next <row>", hearts name the theme, tiles/categories have labels, values and hints, headers marked. Keyboard: ←/→ on a focused row.

## Phase 6 — static review (no Mac available)
Not run here, by necessity: build, tests, `-probe scroll` / `-probe pages`, screenshots, `compare-N.png`. Everything below is by code reading against `reference-B-themes-page-rows.png` and the real APIs in `Design/*`, `Components/Motion.swift`, `PerformancePolicy`.

### Iteration 1 (static)
Compile review found and fixed: unused `rowID` parameter removed; horizontal scroll bleed moved from padding to `contentMargins` (so snapping doesn't shift the first card); 40 pt gap between the controls row and the first section reduced to 12.
APIs checked present for macOS 14.2: `scrollPosition(id:)`, `scrollTargetBehavior(.viewAligned)`, `contentMargins`, `onKeyPress`, `focusEffectDisabled`, `PerformancePolicy.Tier` (Comparable), `FloatingButtonStyle`/`.pill`, `SearchField`, `EmptyState`, `Deferred`, `withMotion`, `.motion`.

| Check | Result (by reading) |
|---|---|
| Sticky bar pinned, pills / search / sort / toggle layout | PASS |
| No carousel on Themes page; first row visible at 1400 × 900 (bar ends ≈ y 162, header ≈ y 200, cards ≈ y 252–430) | PASS |
| Section header identical everywhere (tile, title, description, `‹ ›`, See All) | PASS |
| Cards: fill, name + count bottom-left on fade, heart, radius 20, hairline, 252 wide, 5 per row at 1400 (1324 ≤ 1336) | PASS |
| Active ring; hover lift + accent glow | PASS |
| Moodboards = 5 category cards, title, count, round arrow, "Most Popular" | PASS |
| Football and every other row use the same `ThemeRow` | PASS |
| Spacing: section 40, card 16, margin 32 / 24 | PASS |
| Tokens (`DS.*`, `Motion.*`); literals only for glass opacities from the prompt | PASS |
| Mood: atmosphere + glass | PASS (needs eyes on a Mac) |
| Search, filters, sort, favourites, apply/undo, wallpaper switch, See All, deep link | PASS by reading (logic reused from `ThemeDiscovery`/`ThemeStats`; deep link untouched) |
| Performance | UNVERIFIED (no probe). Risks to watch: `ThemeAtmosphere` is 2 static gradients; per-card `dsElevated` shadow in lazy rows (as before) |
| 900 × 600 layout, Reduce Motion | PASS by reading; verify visually |
Result: static PASS after 1 iteration. Not a substitute for the screenshot loop.

### Owner must run on a Mac
1. `swift build` (zero warnings) and the full test suite (313 tests / 85 suites expected).
2. `-openPage themes` at 1400 × 900 (top, scrolled to Trending/Moodboards, scrolled to Football) and 900 × 600; side-by-side against `reference-B`.
3. `-probe scroll` and `-probe pages` for Themes vs baseline.
4. Hover glow strength, atmosphere strength, selected-pill slide, arrow/keyboard scrolling, drag snapping (no first-card jump), Reduce Motion and Low Power behaviour.
5. If your local tree still shows the carousel hero on this page, remove its use from `ThemesPage` (the carousel files stay).
6. Known judgement calls: sort defaults to "Suggested" (reference shows "Newest"); Moodboards cards preview a single lead theme, not a collage.
