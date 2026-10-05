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
