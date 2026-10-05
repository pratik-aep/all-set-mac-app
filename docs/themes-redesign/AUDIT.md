# Audit — current `ThemesPage.swift` (cloud first pass) vs reference B

Measured from the reference PNG (1536 px wide render, ≈ 1400 pt window) and from the code (no screenshots possible: no Mac toolchain here). "Current" = what the first pass does when read line by line.
This table is the Phase 6 checklist.

| # | Element | Reference (pt) | Current (code) | Gap | File |
|---|---|---|---|---|---|
| 01a | Filter bar container | Rounded glass, radius ≈ 20, height ≈ 46, pinned under nav | Rounded black 28% + hairline, sits above a `ScrollView` (not under it); height implicit | No gradient rim / top highlight; content hard-clips at bar bottom instead of scrolling under | ThemesPage |
| 01b | Pills | 13, no icons, 28 high, selected = white fill + black text, sliding | `FilterPill` (raised fill on idle, no slide) | Idle pills should be flat; indicator should slide (0.15–0.2 s) | ThemesPage |
| 01c | Search | ≈ 200 × 34 | `SearchField` 200 fixed | Must shrink in narrow windows | ThemesPage |
| 01d | Sort | "Newest ⌄" dropdown | Capsule menu, default "Suggested" | OK (default kept as Suggested so filters keep their meaning) | ThemesPage |
| 01e | Layout toggle | Square 34 × 34 at far right | **Missing** | Add rails ↔ grid toggle with label | ThemesPage |
| 02a | Section header tile | ≈ 40 rounded square, icon | 40 × 40, radius 12, `hover` fill | OK; add glass rim | ThemesPage |
| 02b | `‹ ›` | Square rounded buttons ≈ 32 | Circular `FloatingButtonStyle` 32 | Square, glass | ThemesPage |
| 02c | See All | Pill at right | `.pill` | Missing on rows with no filter (Colour & Light, Night, …) | ThemesPage |
| 02d | Header on Moodboards | Same header + arrows | Header without arrows; cards in a plain `HStack` | Make it a scrolling row like the others | ThemesPage |
| 03a | Card size | ≈ 252 × 175, radius 20, hairline | 252 wide, 1136:768, radius 20 (`DS.Radius.media`), hairline | OK | ThemesPage |
| 03b | Name / count | Bottom-left over dark fade | Present (fade clear→72%) | OK | ThemesPage |
| 03c | Heart | On the card, never over text | Bottom-right, 28 floating | OK | ThemesPage |
| 03d | Hover | Lift + accent glow | Scale 1.03 + 1.5 pt accent edge | No outer glow; no Reduce Motion / Low Power gate | ThemesPage |
| 03e | Active card | Bright accent ring | 2 pt accent ring + badge | OK | ThemesPage |
| 03f | Press | Scale 0.98 | **Missing** (`.plain`) | Add press style | ThemesPage |
| 04a | Row | 5 cards at 1400, gap 16, snap, arrows | `LazyHStack` 252 / 16, `viewAligned`; arrows use a counter that ignores drag | Track real position with `scrollPosition(id:)`; keyboard arrows; shadow/ring clipped by `ScrollView` | ThemesPage |
| 05 | Category cards | ≈ 250 × 125, collage, title, "n themes", circular arrow, "Most Popular" | 124 high, flexible width, all present | At 900 pt width they shrink to ≈ 157 and clip text; fixed width needed | ThemesPage |
| 06 | Consistent pattern | Same header/row for all sections | Rows share it; Moodboards differs | Unify | ThemesPage |
| 07 | Page start | Filter bar first, rows visible without scroll | Present | OK | ThemesPage |
| 08 | Atmosphere | Soft coloured light at top (A/B) | **Missing** | Static accent glow, crossfade ≤ 0.7 s | ThemesPage |
| 09 | Grid / search states | Grid of same cards, header with name + count, empty states | Present | Needs "See All" for rows without a filter; layout toggle | ThemesPage |
| 10 | Spacing | Section 40, card 16, margin 32 / 24 | Tokens used | OK | — |
| 11 | A11y | Labels, selected traits, keyboard | Hearts/arrows labelled; no row keyboard; pill trait via `FilterPill` | Row arrow keys; richer labels | ThemesPage |
| 12 | Carousel | Not shown | Not in this tree | Nothing to remove here; owner's local tree must drop its use on this page | (owner) |
