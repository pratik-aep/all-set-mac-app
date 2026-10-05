# MASTER PROMPT — All Set: rebuild the Themes page to match the reference

You are the AI coding agent inside the owner's IDE, with the project open and running on their Mac. You can build, run, screenshot and read files. This prompt is your whole job. **Do the whole job. Do not stop early, do not hand work back, do not ask questions** — except at the single gate before the last phase (Phase 7).

---

## 0. Ground rules (read twice)

1. **Autonomy.** Run Phases 0 → 6 back to back with no pauses and no permission requests. Between phases, write one line to `docs/themes-redesign/PROGRESS.md` and move on. **Stop and ask only before Phase 7.**
2. **Force the match.** "Close" is a fail. The result must be visually the same page as the reference at 1400 × 900: same structure, same hierarchy, same spacing rhythm, same card treatment. If the self-check in Phase 6 does not pass, you **restart the loop** (Phase 6 → fix → Phase 6) until it does. Do not declare success from memory or from reading code; declare it only from screenshots you took and compared.
3. **You can see images.** The reference images are PNG files in the repo. Open them (read them as images) — never claim you cannot view them. Extract frames from the screen recording with `ffmpeg` if you need to.
4. **Work on the owner's local code, not GitHub's.** The running app has a carousel hero that is **not** on `origin/main`. Work on the branch the app is built from (probably `perf-audit`; run `git branch --show-current` and `git status` first). Create a working branch from it: `themes-reference-match`. **Never** reset, rebase onto main, force-push, or delete the owner's uncommitted work. If there are uncommitted changes, `git stash` is NOT allowed; commit them to a WIP commit on your new branch first.
5. **Local commits are fine** (one per phase, message `Themes: phase N — <what>`). **Do not push, open a PR, or merge** until the owner says so in Phase 7.
6. **Do not regress the app.** Keep every rule in `UI-SPEC.md` §13 and the performance contract in §12: dark only, one window backdrop, animate opacity/transform only, no live blur/shadow on anything that moves, no per-card grain, ≤ 2 accent hues per theme, glow never over text, page switch and scroll must not get slower, Reduce Motion / Low Power respected, every icon-only control has an accessibility label. No brand logos, album art, trademarks or promo photos; the owner's own photos stay local. Build with zero warnings; all existing tests stay green (313 tests / 85 suites today).
7. **Reuse before writing.** Use the design tokens (`DS.*`), `Motion.*`, `FilterPill`, `SearchField`, `FloatingButtonStyle`, `SectionHeader`, `ThemeSnapshot`, `ThemePreviews` cache, `Deferred`, etc. No magic numbers when a token exists. Match surrounding code style and comment density.
8. **Don't invent content.** Theme names, counts, sort and filter logic come from `ThemeLibrary`, `ThemeDiscovery`, `ThemeStats`. Keep favourites, apply/undo, "Change the wallpaper too", search and deep links (`allset://open/themes`) working.

---

## 1. Package contents (all in `docs/themes-redesign/`)

| File | What it is |
|---|---|
| `PROMPT.md` | This file |
| `UI-SPEC.md` | The complete UI spec with every measured number (tokens, nav, components, Themes page §5) |
| `CONTENT.md` | Inventory of everything in the app (themes list, widgets, features) |
| `APP-README.md` | The app's README (architecture, commands, debug flags like `-openPage themes`, `-renderPages`) |
| `reference/reference-B-themes-page-rows.png` | **PRIMARY TARGET.** The full Themes page: sticky filter bar, section rows, theme cards, category cards, with numbered callouts 01–06 |
| `reference/reference-A-cinematic-carousel.png` | Secondary reference: "Concept 2 — Cinematic Carousel" (also shows Concept 3). Style cues: glass nav, glow, depth, card finish |
| `reference/current-ui-screen-recording.mov` | The owner's current UI in motion (14 s) |
| `reference/current-ui-frame-t1/t5/t9/t13.png` | Frames from that recording: t1 = carousel hero + 13-pill rail at the top; t5/t9/t13 = plain 300-pt shelves (Colour & Light, Moodboards, Night) with name, count and 2-line description **under** each picture |

### What the current UI is (from the recording)
A big glass hero panel with a 3D carousel (Leopard Noir · Seven · Americana · Red Seven …), `1 / 8` indicator, search at top-right, arrows, a 13-pill category capsule underneath, then a "Change the wallpaper too" switch, then **Featured / Colour & Light / Moodboards / Night** as rails of cards with text under the picture.

### What the target is (reference B, callouts 01–06)
1. **Sticky filter bar** — stays at the top while scrolling; compact, glassy, rounded container; pills without icons (All · Featured · Trending · New · Moodboards · Football · Music Icons · Popular · Minimal · Dark · Colorful · Developer · Favorites); selected pill = white fill / black text with smooth indicator; on the right a search field ("Search themes…"), a sort dropdown ("Newest ⌄") and a square grid/layout toggle button.
2. **Section header** — rounded-square icon tile (≈40 pt) + title + short description; at the right: `‹` `›` square arrow buttons and a "See All" pill.
3. **Theme card** — the live theme preview fills the whole card (radius 20, hairline); name (bold) and "n widgets" sit bottom-left over a dark fade; heart button on the card; hover lifts the card and adds an accent glow; the selected/active card has a bright accent ring (blue in the reference); a subtle animation allowed.
4. **Section row** — horizontal row of ~5 equal cards, consistent card design, smooth scroll/drag, arrow navigation, "See All" link.
5. **Category section** (Moodboards) — large visual cards (≈ 250 × 125) with a collage/preview, title, "n themes" and a circular arrow button bottom-right; a "Most Popular" badge on one; clicking opens that category.
6. **Consistent pattern** — every section (Featured, Trending, Moodboards, Football, then the rest) uses the same layout so the page stays clean.

Reference A adds the finish: dark cinematic canvas, glass chrome, soft coloured light from the theme behind the content.

**Decision for this job:** reference B is authoritative for the Themes page. The page opens on the sticky filter bar and rows — **not** on the carousel hero. Keep the carousel source files in the repo (do not delete them); just stop showing them on the Themes page. Whether to bring the carousel back as an optional banner is a question for the owner in Phase 7.

---

## 2. A head start exists (use as reference, do not merge blindly)

A first pass was written in the cloud on branch `origin/claude/inspiring-fermat-5bibd1`, commit "Themes page: sticky filter bar, icon section rows with arrows, image-first theme tiles and category cards", file `Sources/AllSet/Studio/ThemesPage.swift`. It was **never compiled** and is based on an older tree that has no carousel. Read it with:

```
git fetch origin claude/inspiring-fermat-5bibd1
git show origin/claude/inspiring-fermat-5bibd1:Sources/AllSet/Studio/ThemesPage.swift
```

It contains good starting pieces: `ThemeSort`, the sticky `filterBar`, `ThemeSectionHeader`, `ThemeRail` (arrow scrolling), `ThemeTile`, `ThemeCategoryCard`. Port what helps into the owner's current `ThemesPage.swift`, fix whatever does not compile, and then keep going until it matches the reference. It is a starting point, not the finish line.

---

## 3. Phases — run 0 → 6 consecutively, then STOP and ask before 7

### Phase 0 — Orientation and baseline (no code changes)
- Read `UI-SPEC.md` (especially §2, §4, §5, §12, §13), `APP-README.md` (debug commands) and `Documentation/HANDOFF.md`.
- Open both reference PNGs and the four recording frames. Write a 10-line description of each in `PROGRESS.md` so you prove you saw them.
- `git branch --show-current`, `git status`; create `themes-reference-match` (rule 4).
- Locate the Themes code: `Sources/AllSet/Studio/ThemesPage.swift`, `ThemePreviews.swift`, `Design/DesignComponents.swift`, `Design/WindowBackdrop.swift` (BleedScrollPage), `Design/AppNavigation.swift`, and the carousel files (`grep -ril carousel Sources`).
- Build, run tests, record baseline numbers (build warnings, test count, and if available `-probe scroll` / `-probe pages` for the Themes page).
- Capture baseline screenshots of the Themes page at **1400 × 900** and **900 × 600** into `build/review/before-*.png` (use the app's own `-openPage themes` and `-renderPages` flags, or `screencapture -l <windowid>`; prefer the repo's `./scripts/review-hero.sh` if it exists).

### Phase 1 — Audit: current vs reference B
Write `docs/themes-redesign/AUDIT.md`: a table with one row per element in callouts 01–06 plus nav/background (columns: element · reference · current · gap · file to change). Include measured numbers (pt) from screenshots. This table becomes the Phase 6 checklist. Commit.

### Phase 2 — Page structure and sticky filter bar
- Themes page no longer starts with the carousel hero. Page content starts directly under the floating nav (nav height 100 pt, `safeAreaInsets.top`), with the filter bar pinned beneath it and the rows scrolling under/below it. Pages that still use `BleedScrollPage` (Wallpaper etc.) must be untouched.
- Make sure `ui.mediaUnderNavigation` is nil on this page so the nav scrim is on (nothing bleeds under the nav).
- Filter bar: single rounded glass container (radius ≈ 20–22, fill black ≈ 28% + hairline, plain fills — no material on scrolling content), pills without icons (28 high), search field (≈ 200 wide, 34 high), sort menu ("Newest", plus Suggested / Most Popular / A to Z), and a square 34 × 34 grid/layout toggle (rails ↔ grid) with an accessibility label. Selected indicator slides on a 0.15–0.2 s ease.
- Keep "Change the wallpaper too" and the undo banner, as a slim right-aligned row above the first section.
- Commit.

### Phase 3 — Section headers, rows and theme cards
- **Section header** per callout 02: 40 pt icon tile, title 20 semibold, one-line description (meta), `‹` `›` arrow buttons (32–36 pt) that scroll the row by ~3 cards, "See All" pill → sets the filter.
- **Rows** per callout 04: lazy horizontal rows, five cards visible at 1400 wide (card ≈ 252 pt, gap 16), view-aligned snap, smooth drag/scroll, arrows. Titles/descriptions as in the reference: Featured ("Handpicked themes you'll love. Bold, beautiful and ready to apply."), Trending ("Popular right now in the community."), Moodboards ("Theme collections for different vibes."), Football ("For the beautiful game."), then Music Icons, Colour & Light, Night, Dreamy, Minimal & Designer, Developer, More Setups. Each theme appears once across rows.
- **Theme card** per callout 03: picture fills the card (aspect 1136:768, radius 20, hairline); bottom fade (clear → black ≈ 70%); name (14 semibold) + "n widgets" (11 medium) bottom-left, never overlapped by the heart; heart button on the card (28–30 pt floating style, filled pink when favourite); hover: scale 1.02–1.03 and accent edge/glow fading in (**opacity only**, accent from the theme's own accent, glow never over text); the theme currently on the desktop gets an accent ring + "On your desktop" badge; press scale 0.98; click opens the theme detail page.
- Preview pictures must keep using the cached `ThemeSnapshot` pipeline (no live widget rendering in cards).
- Commit.

### Phase 4 — Category cards, grid/search states, remaining rails
- Moodboards section per callout 05: five wide cards (Minimal, Dark, Colorful, Aesthetic with a "Most Popular" badge, Developer), each previewing its first theme (or a collage), title, "n themes", circular arrow button; click selects that filter. They don't consume themes from later rows.
- Filter ≠ All, or any search text: show a grid (adaptive, min ≈ 240, gap 16) of the same cards under a section header showing the filter name and count; empty states for no results and no favourites; sort applies here.
- Narrow window (900 × 600): filter bar still one row (pills scroll horizontally, search shrinks), rows show fewer cards, nothing clips or overlaps.
- Commit.

### Phase 5 — Finish: atmosphere, glass, motion, accessibility
- Page finish from reference A/B: the top of the page carries a soft, static coloured glow derived from the theme on the desktop (or the first Featured theme) fading into the window backdrop by ≈ 600–900 pt; crossfade (opacity only, ≤ 0.7 s) when it changes; no blur layers that move. Use the existing `AppBackground`/`ThemeAccent` ideas; no new live effects.
- Glass details on the filter bar and arrow buttons: 1 pt gradient border (top-left white ≈ 18% → bottom-right ≈ 4%), inner top highlight 1 pt white ≈ 10%, panel shadow static only.
- Reduce Motion: no hover lift, 0.15 s ease only. Low Power / hot Mac: no card glow.
- VoiceOver labels and selected traits on pills, arrows, hearts, tiles, category cards. Keyboard: arrows scroll a focused row.
- Commit.

### Phase 6 — Verify against the reference, and LOOP until it passes
This phase is a loop. Repeat it as many times as needed (hard cap 10 iterations; if you hit the cap, stop and report exactly which checklist rows still fail and why).

1. Build with zero warnings. Run the whole test suite. If anything fails, fix it first.
2. Launch the app, open Desktop → Themes, and capture screenshots at **1400 × 900** (top of page, scrolled to Trending/Moodboards, scrolled to Football) and **900 × 600** (top). Save to `build/review/after-N-*.png`.
3. Build a side-by-side image `build/review/compare-N.png`: reference B on the left, your screenshot of the same scroll position on the right, same width. Open it and look at it.
4. Score every row of the Phase 1 audit table plus this checklist as PASS/FAIL, writing the result into `PROGRESS.md` under "Iteration N":
   - [ ] Sticky filter bar present, stays pinned while scrolling, pill/search/sort/toggle layout matches B
   - [ ] No carousel hero on the Themes page; first row is visible without scrolling at 1400 × 900
   - [ ] Every section header = icon tile + title + description + `‹ ›` + See All, identical across sections
   - [ ] Cards: picture fills, name + "n widgets" bottom-left on a dark fade, heart on the card, radius 20, hairline, equal size, 5 per row at 1400
   - [ ] Active/selected card shows an accent ring; hover lifts and glows
   - [ ] Moodboards = 5 large category cards with title, count, circular arrow, "Most Popular" badge
   - [ ] Football (and every other row) uses the identical pattern
   - [ ] Spacing: section gap ≈ 40, card gap 16, page margin 32 (24 below 1000 pt wide); nothing misaligned
   - [ ] Typography/colours use the tokens (no stray fonts or colours)
   - [ ] Overall mood matches A/B: dark cinematic canvas, soft coloured light at top, glass chrome
   - [ ] Search, filters, sort, favourites, apply/undo, "Change the wallpaper too", See All, deep link all work
   - [ ] Performance: page switch and scroll no worse than the baseline from Phase 0 (`-probe scroll`, `-probe pages` if available); no dropped frames while scrolling rows
   - [ ] 900 × 600 layout holds; Reduce Motion path works
5. **If any row fails: fix it (smallest change that fixes it), commit `Themes: match iteration N`, and run this phase again from step 1.** Do not move on, do not rationalise a difference away, do not edit the checklist to make it pass. Differences that come from data (the reference's example themes differ from the app's) are acceptable; layout, hierarchy, spacing and styling differences are not.
6. When every row passes in one full iteration, write `Result: PASS after N iteration(s)` in `PROGRESS.md`, attach the final compare image path, and continue to the gate below.

### >>> GATE — STOP HERE AND ASK THE OWNER <<<
After Phase 6 passes, **stop**. Post a short summary (what changed, the final `compare-N.png` path, test/perf numbers, any rows you could not make pass) and ask the owner to confirm before Phase 7. Do not start Phase 7 on your own.

### Phase 7 — Wrap-up (only after the owner says go)
Ask, in one message, and wait:
1. Push `themes-reference-match` to GitHub? (and open a PR into which branch?)
2. Bring the carousel back as an optional banner above the rows (reference A style), or leave it removed from the Themes page? (Code is still in the repo either way.)
3. Update `Documentation/HANDOFF.md`, `README.md` and `UI-SPEC.md` §5 to describe the new Themes page?

Then do exactly what they approve: docs update, push, PR (description = what changed + before/after screenshots + test and perf numbers).

---

## 4. Output format while you work
- One short status line when each phase starts and ends. Details go in `PROGRESS.md`, not in chat.
- Never paste whole files into chat. Never leave TODOs, stubs or commented-out code.
- If something blocks you (a missing flag, a failing probe), work around it and note it in `PROGRESS.md`; do not stop to ask. The only stop is the gate before Phase 7.

**Begin now with Phase 0.**
