# Wallpaper dataset inventory — "wallpaper phase 1 data"

Programmatic discovery only (Phase 2). Structure and counts, no raw content.
Dataset: `wallpaper phase 1 data/`, 29 GB, 252 Steam Workshop-ID folders —
**same shape as yesterday's source** (`/Volumes/KALI LINUX/Steam Wallpapers`).

## Shape
| | |
|---|---|
| Total folders | 252 |
| Missing `project.json` | 0 |
| Malformed `project.json` | 0 |
| `type: scene`, with its `.pkg` present | 172 / 172 |
| `type: video` | 74 |
| `type: web` | 6 |
| Other/unknown type | 0 |

No new top-level type, no loose `scene.json` without a package, no nested or
multi-`project.json` folders. Every scene uses the plain `scene.json`/`scene.pkg`
naming (no `gifscene.pkg` variant in this batch, though the importer already
handles that name too).

## Video items (74)
- File extension actually referenced by `project.json`: `.mp4` in all 74.
- Raw bytes: 26.10 GB.
- No unsupported container/codec discovered yet — codec/fps checks happen
  per-file at import time via the existing `describe()`/`needs_transcode()`,
  same as yesterday.

## Web items (6)
Same category as yesterday's 10; existing `loops_in_page()` heuristic applies
unchanged (only a genuinely looping clip becomes a wallpaper, one-shot
interaction clips are skipped).

## Cross-root overlap with yesterday's catalog — **found, and it matters**
252 Workshop-ID folders were checked against the 181 already-catalogued
items (matched by `provenance.workshopId`). **12 overlap**, and all 12 are
**byte-identical** to what's already imported (verified by content SHA-256,
not just Workshop ID):

| Workshop ID | Type | Content ID (first 16 hex of SHA-256) |
|---|---|---|
| 1364934389, 1396967200, 1815285371, 2230953376, 2928758667, 3151551777, 3174556087, 3244466773, 3563983879 | scene | matches an existing catalog item exactly |
| 2879959473, 2992510790, 917043694 | video | matches an existing catalog item exactly |

This is expected — the two datasets share some Workshop items — but it
exposes a real gap explained in the pipeline report below (see "Risk found").

## Disk budget
| | |
|---|---|
| Free space now | 58 GB |
| New raw video bytes (would be copied if `--self-contained`) | 26.10 GB |
| Scene-derived output, projected from yesterday's per-scene average (~13 MB × ~160 new scenes after overlap removed) | ~2 GB |
| **Projected addition** | **~28 GB** |
| **Projected free space after** | **~30 GB** |

Tight but sufficient. Flagged for confirmation, not assumed.
