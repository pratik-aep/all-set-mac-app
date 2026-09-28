# All Set — Wallpaper Library: architecture

_Living document. The moment implementation forces a deviation, this file is
updated in the same checkpoint and the deviation is logged in `report.md`.
Code and docs are never allowed to disagree._

_Last updated: 2026-09-29 (fetch from a personal server when missing locally)._

## Stack, and why
| Piece | Choice | Why |
|---|---|---|
| App | Swift 6, SwiftUI + AppKit | Matches the rest of All Set. |
| Playback | AVFoundation via the existing `LoopingVideo` | Hardware decoding and the pausing rules already exist; adding a player would be a second engine (spec R5). |
| Import | Python 3 (`/usr/bin/python3`) + ffmpeg | Offline, one-off work. Keeping it out of the app keeps the app free of new dependencies. |
| Texture decoding | Swift (`scripts/wetex.swift`), compiled once | Needs DXT/LZ4 and ImageIO; ships as source, built on demand. |
| Scene rendering | Swift + offscreen **OpenGL** (`scripts/wescene.swift`), importer only | Runs each scene's **own shipped GLSL** (3–7 differing versions per effect across the packages). Chosen by the user over hand-porting or translating to Metal (2026-09-27). OpenGL is deprecated, but it is confined to the importer: already-rendered wallpapers are plain videos. |

**Division of labour:** everything expensive and one-off happens at import;
the app only plays a file. This is why 408 wallpapers, from two separate
source folders, cost the app nothing beyond one video.

## Where things live
```
scripts/
  wallpaper_library.py   inventory + import: scenes, web, video, live loops
  wetex.swift            Wallpaper Engine .tex decoder (built to Library/bin/)
  wescene.swift          scene renderer: the scene's own shaders → still or loop
  playcheck.swift        does AVFoundation really play this file?
Sources/AllSetCore/Wallpaper/
  WallpaperLibrary.swift LibraryVideo, WallpaperLibraryCatalog, LibrarySort
  WallpaperStore.swift   owns the catalog; resolves a wallpaper to a URL
Sources/AllSet/Wallpaper/
  WallpaperController.swift  plays it (LoopingVideo / MovingStill)
  WallpaperPages.swift       LibrarySection, LibraryTile
~/Library/Application Support/AllSet/Wallpaper/Library/   (not in the repo)
  catalog.json  originals/  live/  stills/  extracted/  transcoded/
  thumbnails/   scenes.json  bin/wetex  bin/wescene  import-report.json
```

## Data model
`LibraryVideo` — one wallpaper.
- `id`: first 16 hex of the content SHA-256. Identity survives renaming (R6).
- `kind`: `.video` (plays) or `.image` (a still that drifts). Missing ⇒ video.
- `root` + `file`: **provenance only** — where it came from. After R2 this is
  history, not a dependency.
- `playback`: the file on this Mac that actually plays. **The only path that
  matters at run time.**
- `status`: `quarantined` (default) / `published` / `unsupported`. Unknown
  values decode as `quarantined` — the safest reading (R4).

Decoding is deliberately tolerant: one unreadable entry is skipped, not fatal.

### Resolution rule (the heart of R2)
`WallpaperStore.libraryURL(id)`:
1. If `playback` exists on disk → use it. **Always wins.**
2. Otherwise, only for a video, fall back to `root + file` if reachable.
3. Otherwise nothing, and the caller shows the default wallpaper.

`canPlay` mirrors this without touching the disk, so grid cards never stat files.
After `--self-contained` every item has step 1, so step 2 is dead weight kept
only for a library imported without copying.

### Fetching from a personal server (optional, off by default)
`config.libraryServerURL` is nil unless a person sets it — with no server
configured, R2 holds exactly as verified (nothing but this Mac, ever). Set
(2026-09-29, one person's own Tailscale-only home server, no dedicated
settings UI yet), it adds one more fallback *after* step 3 above:
`WallpaperView`'s `.library(id)` case runs `.task(id: id) {
fetchLibraryVideo(id) }` alongside its existing fallback to default art, so a
wallpaper missing from this Mac (deleted, or a future deliberate "free up
space" action, not yet built) is fetched once and cached at the *same*
relative path (`live/<id>.mp4`…) it lives at locally — every other
resolution method sees it exactly like a normal local copy afterward, no
second code path to keep in sync. `WallpaperStore.checkServerReachable()`
follows `StatusService`'s cached, age-gated probe shape (`Sources/AllSetCore/
Developer/StatusService.swift`) so the Library grid's "can this play"
question never costs a network call per card. Download mechanics
(`URLSessionDownloadTask`, presence-check first, progress polled into an
`@Observable` dict) follow `AerialCatalog.download` exactly.
`WallpaperStore.fetchSession` is an **instance** property, not shared/static,
specifically so tests can stub it without any risk from parallel test runs.

Two real bugs only surfaced by testing the actual running `.app`, not `swift
test` (2026-09-29) — worth recording so the next feature that talks to a
server doesn't repeat either:
1. **`library` loads asynchronously**; `WallpaperView` can render before it
   has. The first fetch attempt then fails ("no server" — really "no catalog
   yet") and, without help, never retries: `.task(id:)` only reruns when its
   id changes, and the wallpaper's id doesn't. Fixed by adding
   `hasLoadedLibrary` and folding it into the task's id
   (`"\(id)#\(hasLoadedLibrary)"`), so the flag flipping true counts as a
   new id and forces a retry with real data.
2. **A successful fetch alone doesn't make the view redraw.** It only
   touches `libraryCopies`, deliberately `@ObservationIgnored` for grid-scroll
   performance; `libraryURL(id)`'s file-exists check is a raw `FileManager`
   read Observation can't see either. Fixed by reading `fetches[id]` inside
   the view (even where its value isn't otherwise used) purely to establish
   the Observation dependency, since `fetches` is set then cleared around
   every real fetch attempt.
3. **App Transport Security blocks plain HTTP by default in a real app
   bundle** — `swift test`'s executable isn't subject to the same
   enforcement, so this looked fine right up until it ran as `.app`.
   `Resources/Info.plist` now carries one `NSExceptionDomains` entry, scoped
   to the server's exact address, not a blanket `NSAllowsArbitraryLoads`
   (that would weaken every other request the app makes).

## How a scene becomes a wallpaper
```
scene.pkg ─▶ an MP4 inside?  ─yes─▶ extract (a real video)
          ─▶ a GIF scene?    ─yes─▶ frames → loop
          ─▶ otherwise:
   SceneNormaliser  raw scene.json → normalised scene (data only)
     layers with their transform chain (origin, scale, rotation, parents),
     alignment, alpha / colour / brightness (as keyframe tracks),
     effects as passes of the package's own shaders: uniforms with the
     scene's values (defaults from the shader's own annotations), combos,
     textures (masks, flow maps, noise), render targets and bindings
   plan_loop        loop length 10–30 s that the scene's cycles fit; each
                    timed part's speed nudged ≤4% to land on whole cycles;
                    recording starts 60 s in (after one-shot intros)
   wescene          offscreen GL: per layer, effect passes in order; then
                    composite with the full hierarchy → still (3840) and,
                    if anything is timed, a loop (2560, HEVC, 30 fps)
   frame_movement   most-changed 1/144th of the frame ≥ 2.0/255?
                    yes → live/<id>.mp4   no → stills/<id>.jpg
```
- **Nothing is invented.** Values come from the scene; defaults from the
  shader the package ships. Mouse parallax and engine camera shake have no
  input here and are not simulated (user decision, 2026-09-27).
- **Seamless loops:** periodic parts are fitted to the loop; anything that
  can't be fitted is joined by a 1 s crossfade of the loop's tail into its
  head. Measured on a real loop: the seam step equals a normal frame step.
- **Unshipped engine pieces** are supplied once, in the renderer's prelude:
  the engine macros (`texSample2D`, `frac`, `mul`…), blur taps, HSV helpers,
  the perspective homography, `inverse`, HLSL type names and a few
  looser-typed overloads, the named blend modes, and two engine textures
  (`util/noise`, `util/clouds_256`, generated as tiling noise).
- **Particles** (60% of scenes use them: rain, snow, embers, dust, fog) are
  simulated from the scene's own emitters, initializers, operators and
  renderers (sprites, trails stretched along velocity). Each particle is a
  closed-form function of its age and a seed, and spawn times repeat every
  loop, so the particle field loops exactly with no crossfade. Settings are
  compiled to numbers once; only particles within one lifetime of "now" are
  evaluated, so cost follows the number alive.
- **Refracting particles** (`REFRACT`, e.g. raindrops) bend the picture
  behind them through their normal map instead of drawing their placeholder.
- **Engine particle sprites** (`particle/halo`, `particle/drop`, fog, beams…)
  ship with the engine, not the scene, and are its art: stand-ins of the same
  kind are generated by name family; unknown families are reported.
- **Single-channel (R8) textures** drawn as pictures are white with the
  channel as alpha, as in the engine; masks still read the raw value.
- **Keyframes are offsets** on the property's base value (a scale track named
  "1.02 to 1.15" runs 0 → 0.13 on a base of 1.02); alpha is clamped to 0–1.
- **Pass geometry follows each shader:** passes that apply
  `g_ModelViewProjectionMatrix` get the quad in pixel units; passes that write
  `a_Position` straight to the screen get it in screen space.
- **Debugging:** `WESCENE_DUMP_LAYER=<name>` writes each effect pass of that
  layer to `/tmp/wescene-dump`.
- **What isn't carried** is reported per scene (`sceneNotes` in the catalog,
  and `inspect-scene`): particles, text, sound, 3D models, SceneScript code,
  audio input (silent state), and effects whose GLSL relies on HLSL-only
  typing.

## Duplicates
`removed.json` in the library lists wallpapers taken out by a person, each
with the one kept instead and why. Every import skips them, so they never
come back. Candidates come from Apple Vision feature prints (content, largely
colour-blind), confirmed by a structural check (contrast-equalised greyscale
correlation) so mostly-dark pictures don't match each other; the final call
is made by looking. Applied with `wallpaper_library.py remove-duplicates`.

## Design decisions, and what was rejected
| Decision | Rejected alternative | Why |
|---|---|---|
| Fetch-and-cache only this checkpoint; no "delete local copy to free space" action yet | Build both together | Deleting locally is only safe once fetching back is proven; building it before that proof would let disk-freeing ship ahead of its own safety net. |
| `fetchSession` as an instance property | A shared `static` session (like the rest of this file's `static let` conveniences) | A test stubbing a shared static risks a concurrently-running sibling test's session changing underneath it; per-instance costs nothing since one `WallpaperStore` already exists per test and per running app. |
| Bake motion to a video at import | Animate layers live with Core Animation | 22 layers × 4K RGBA ≈ 730 MB of memory and per-frame GPU compositing; hardware HEVC decode is cheaper and needs no new app code. |
| Run the scene's own shaders | Whole-layer sine slides (the previous version); hand-port one version per effect to Metal; translate with glslang + SPIRV-Cross | Slides invented motion and ignored masks. A hand-port renders every other shader version wrong. Translation adds two dependencies. Running the shipped GLSL is faithful to every version. |
| Keep a still unless motion is measured, locally | Whole-frame average (the previous gate) | Faithful motion is often local (rain on a puddle, a swinging lamp); a whole-frame average called those still. Noise floor of a static picture: 0.33; threshold 1.0. |
| Blend modes ≥ 30 and object colour tint = multiply | Treat unknown modes as "replace" | The engine's enum isn't shipped. The tint effect's own default is 30 and the previews show it tinting; object mode 8 read as Color Dodge turned a BMW cyan against its preview. |
| Particles simulated per particle from age + seed | Step-by-step simulation with state | Stateless evaluation makes loops exact and any frame directly computable; a stateful sim can't loop without a visible reset. |
| Keep a loop only above 2.0/255 local motion | 1.0 (previous) | Loops that barely move looked like a soft still; the sharper still is the better wallpaper. |
| `copybackground` doesn't replace a layer's picture | Treating it as "show what's behind" | 377 ordinary layers carry it; only a render-target texture means "what's behind". |
| Copy originals byte-for-byte | Transcode them to save space | Copying is lossless and cannot change playback; these already decode in hardware. |
| Skip broken scenes by Workshop id, with reasons | Guess from a preview-image hash | Previews are square crops, zoomed, or start on a black frame; a hash cannot tell. Judged by eye instead. |
| Identity from content hash | Path or Workshop id | Files get renamed and moved; content does not. |
| Cross-root dedup by id, not just by root | Filter `kept` by root only | A second source folder can share content with the first (12 items did); filtering by root alone left both copies in `catalog.json` with the same id — a duplicate `Identifiable` for SwiftUI's `ForEach`. Fixed in the merge step itself, not worked around per-root. |

## Open assumptions to confirm
1. **~10 GB in Application Support is acceptable.** It is the price of R2.
2. **2560 px loops, 10–30 s** (chosen per scene so its cycles fit) are the right quality/size point.
3. **Motion threshold 1.0/255 on the most-changed region** is the right line between loop and still.
4. Whether `perf-audit` should be merged to `main` and pushed.
