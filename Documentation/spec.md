# All Set — Wallpaper Library: spec

_Living document. If anything discovered later contradicts it, it is updated in
the same checkpoint and the change is logged in `report.md`._

_Last updated: 2026-09-27 (scenes rendered with their own shaders)._

## What this covers
The Library in **Live Wallpaper → My Videos**: the user's own wallpaper
collection, imported from a Wallpaper Engine folder. It does not cover the
aerial, art, photo or My Photos tabs.

## Who it's for
One person, on their own Mac, using wallpapers they already own.

## Requirements

### R1 — Everything imported that can be
Every item in the source folder becomes a wallpaper unless it genuinely cannot
be rendered without Wallpaper Engine. Anything left out is recorded with a
reason.

### R2 — Nothing needed at run time except this Mac
After `--self-contained`, deleting or unplugging the source folder must not
affect any wallpaper in the app: it plays, previews and can be set.
**This is the headline promise. It is verified with the volume unmounted.**

### R3 — Motion where the scene really has it, and only that
A Wallpaper Engine scene is a stack of layers plus a shader program per effect.
The importer **runs the scene's own shaders** with the scene's own values, so
the motion is what the author wrote (water displacing inside its mask, an edge
swaying, a flow map shaking), not an approximation. Motion the data doesn't
describe is never added: mouse parallax has no mouse here, so it isn't faked.

### R4 — Rights are never assumed
Workshop items have no author or licence, so every item is `quarantined`:
personal use on this Mac, never bundled, never committed, never shared.

### R5 — Reuse, don't duplicate
Playback goes through the existing `WallpaperController` / `LoopingVideo` /
`SharedVideoPlayers` path and the existing pausing rules. No second engine,
player, cache or catalog model.

### R6 — Idempotent and resumable
Re-running the importer changes nothing that is already correct. Identity is
content-based (SHA-256), so renaming or moving a file keeps its wallpaper.
An interrupted run resumes; a copy already made is never undone.

### R7 — Honest about cost
A loop is compressed video that runs the decoder; a still is a sharp picture
that does not. A scene becomes a loop only when its rendered frames show real
movement somewhere (most-changed region ≥ 1.0/255, three times the measured
noise floor of a static picture); otherwise its sharp still is kept.

## Non-goals
- Re-implementing Wallpaper Engine (shaders, particles, 3D, audio response).
- Interactive or mouse-driven wallpapers.
- Sharing, publishing or syncing this library anywhere.

## Current numbers (measured 2026-09-27, after two source folders)
| | |
|---|---|
| Wallpapers | **408** — 303 live, 105 stills |
| Roots merged | "Steam Wallpapers" (181 items) + "wallpaper phase 1 data" (239 new; 12 were already-known duplicate content, correctly merged not doubled) |
| Left out (both rounds) | 26, each with a recorded reason |
| Needing a source folder | **0** — both original folders were absent (drive unplugged, dataset folder renamed away) when this was last verified, and the app rendered in full |
| On this Mac | ~35 GB in Application Support |
