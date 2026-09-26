#!/usr/bin/python3
"""All Set's live-wallpaper library tool.

    /usr/bin/python3 scripts/wallpaper_library.py inventory <folder>
    /usr/bin/python3 scripts/wallpaper_library.py import <folder>

`inventory` reads a folder of videos (a Wallpaper Engine / Steam Workshop
folder, or any folder of video files) without changing anything in it, and
writes `inventory.json` next to the app's wallpaper library: per file, its
duration, size, frame rate, codec, bit rate, audio, SHA-256, and whether it
plays.

`import` (see below) turns that into the catalog the app reads.

Needs ffprobe and ffmpeg (Homebrew `ffmpeg`). Runs with macOS's own Python
3; nothing to install from pip. Safe to run again: results are keyed by
file content, so a rerun updates entries instead of adding new ones.
"""

import argparse
import collections
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys

VIDEO_EXTENSIONS = {".mp4", ".m4v", ".mov", ".webm", ".mkv", ".avi"}
DEFAULT_LIBRARY = os.path.expanduser("~/Library/Application Support/AllSet/Wallpaper/Library")


def tool(name):
    for candidate in (shutil.which(name), f"/opt/homebrew/bin/{name}", f"/usr/local/bin/{name}"):
        if candidate and os.path.exists(candidate):
            return candidate
    sys.exit(f"{name} not found: install it with `brew install ffmpeg`.")


FFPROBE = None
FFMPEG = None


def sha256(path, chunk=8 << 20):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            block = handle.read(chunk)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def probe(path):
    """ffprobe's view of a file, or an error string."""
    result = subprocess.run([FFPROBE, "-v", "error", "-print_format", "json", "-show_format", "-show_streams", path],
                            capture_output=True, text=True)
    if result.returncode != 0:
        return None, (result.stderr.strip() or "ffprobe failed")[:300]
    try:
        return json.loads(result.stdout), None
    except json.JSONDecodeError:
        return None, "ffprobe output unreadable"


def decodes(path, seconds=2):
    """Whether the first seconds decode without errors (catches truncated or corrupt files)."""
    result = subprocess.run([FFMPEG, "-v", "error", "-xerror", "-t", str(seconds), "-i", path, "-f", "null", "-"],
                            capture_output=True, text=True)
    return result.returncode == 0, result.stderr.strip()[:300]


def fraction(text):
    try:
        top, bottom = text.split("/")
        return float(top) / float(bottom) if float(bottom) else 0.0
    except (ValueError, AttributeError):
        return 0.0


def orientation(width, height):
    if not width or not height:
        return "unknown"
    ratio = width / height
    if ratio >= 2.0:
        return "ultrawide"
    if ratio > 1.05:
        return "landscape"
    if ratio < 0.95:
        return "portrait"
    return "square"


def describe(path):
    """Metadata for one video file; `valid` says whether it can be a wallpaper."""
    entry = {"size": os.path.getsize(path), "extension": os.path.splitext(path)[1].lower()}
    info, error = probe(path)
    if info is None:
        entry.update(valid=False, problem=error)
        return entry
    streams = info.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video" and not s.get("disposition", {}).get("attached_pic")), None)
    audio = [s for s in streams if s.get("codec_type") == "audio"]
    fmt = info.get("format", {})
    duration = float(fmt.get("duration") or (video or {}).get("duration") or 0)
    if video is None:
        entry.update(valid=False, problem="no video stream")
        return entry
    width, height = int(video.get("width") or 0), int(video.get("height") or 0)
    rotation = 0
    for side in video.get("side_data_list", []) or []:
        if "rotation" in side:
            rotation = int(side["rotation"])
    if abs(rotation) in (90, 270):
        width, height = height, width
    entry.update(
        duration=round(duration, 3),
        width=width,
        height=height,
        fps=round(fraction(video.get("avg_frame_rate") or video.get("r_frame_rate") or "0/1"), 3),
        codec=video.get("codec_name"),
        profile=video.get("profile"),
        pixelFormat=video.get("pix_fmt"),
        bitRate=int(fmt.get("bit_rate") or video.get("bit_rate") or 0),
        container=fmt.get("format_name"),
        hasAudio=bool(audio),
        orientation=orientation(width, height),
    )
    if duration <= 0:
        entry.update(valid=False, problem="zero duration")
        return entry
    ok, error = decodes(path)
    entry.update(valid=ok, problem=None if ok else (error or "decode failed"))
    return entry


def workshop_items(root):
    """Wallpaper Engine's project.json per top-level folder, when present."""
    items = {}
    for name in sorted(os.listdir(root)):
        project = os.path.join(root, name, "project.json")
        if os.path.isfile(project):
            try:
                with open(project, encoding="utf-8-sig") as handle:
                    items[name] = json.load(handle)
            except (OSError, json.JSONDecodeError):
                items[name] = {"_unreadable": True}
    return items


def inventory(root, library):
    root = os.path.abspath(root)
    items = workshop_items(root)
    # Files already described (same path, size and modification time) aren't
    # probed or hashed again: a rerun over a large library takes seconds.
    previous = {}
    try:
        with open(os.path.join(library, "inventory.json")) as handle:
            old = json.load(handle)
        if old.get("root") == root:
            previous = {f["path"]: f for f in old.get("files", []) if f.get("sha256") and "mtime" in f}
    except (OSError, json.JSONDecodeError):
        pass
    files = []
    for folder, _, names in os.walk(root):
        for name in sorted(names):
            if os.path.splitext(name)[1].lower() in VIDEO_EXTENSIONS and not name.startswith("._"):
                files.append(os.path.join(folder, name))
    files.sort()
    print(f"{len(files)} video files under {root}", flush=True)
    records = []
    for index, path in enumerate(files, 1):
        relative = os.path.relpath(path, root)
        top = relative.split(os.sep)[0] if os.sep in relative else None
        project = items.get(top) if top else None
        record = {"path": relative}
        try:
            stat = os.stat(path)
            known = previous.get(relative)
            if known and known.get("size") == stat.st_size and known.get("mtime") == int(stat.st_mtime):
                record.update({k: v for k, v in known.items() if k not in ("path", "workshop")})
            else:
                record.update(describe(path))
                record["sha256"] = sha256(path)
                record["mtime"] = int(stat.st_mtime)
        except OSError as error:
            record.update(valid=False, problem=f"unreadable: {error}")
        if project is not None:
            record["workshop"] = {
                "id": top,
                "type": (project.get("type") or "").lower(),
                "title": project.get("title"),
                "tags": project.get("tags") or [],
                "contentRating": project.get("contentrating"),
                "isMainFile": project.get("file") == os.path.basename(path),
                "hasLicense": any(key in project for key in ("license", "licence", "copyright")),
            }
        records.append(record)
        print(f"  [{index}/{len(files)}] {'ok ' if record.get('valid') else 'BAD'} {relative}", flush=True)
    summary = {
        "root": root,
        "scannedAt": datetime.datetime.now().isoformat(timespec="seconds"),
        "workshopItems": {kind: sum(1 for p in items.values() if (p.get("type") or "").lower() == kind)
                          for kind in sorted({(p.get("type") or "").lower() for p in items.values()})},
        "files": records,
    }
    os.makedirs(library, exist_ok=True)
    with open(os.path.join(library, "inventory.json"), "w") as handle:
        json.dump(summary, handle, indent=1, ensure_ascii=False)
    report(summary)
    return summary


def report(summary):
    files = summary["files"]
    valid = [f for f in files if f.get("valid")]
    invalid = [f for f in files if not f.get("valid")]
    by_hash = {}
    for f in files:
        if f.get("sha256"):
            by_hash.setdefault(f["sha256"], []).append(f["path"])
    duplicates = {h: p for h, p in by_hash.items() if len(p) > 1}

    def count(key, rows):
        out = {}
        for row in rows:
            out[row.get(key)] = out.get(row.get(key), 0) + 1
        return dict(sorted(out.items(), key=lambda kv: -kv[1]))

    def resolution(row):
        w, h = row.get("width") or 0, row.get("height") or 0
        long = max(w, h)
        return "8K+" if long >= 7680 else "4K" if long >= 3840 else "1440p" if long >= 2560 else "1080p" if long >= 1920 else "720p" if long >= 1280 else "SD"

    total = sum(f["size"] for f in files)
    print("\n== inventory ==")
    print(f"workshop items by type: {summary['workshopItems']}")
    print(f"video files: {len(files)} ({total / 1e9:.2f} GB); valid {len(valid)}, invalid {len(invalid)}")
    print(f"exact duplicates: {len(duplicates)} groups, {sum(len(p) - 1 for p in duplicates.values())} extra copies")
    print(f"resolution: {count('res', [dict(r, res=resolution(r)) for r in valid])}")
    print(f"fps: {count('fpsBucket', [dict(r, fpsBucket=round(r.get('fps') or 0)) for r in valid])}")
    print(f"codec: {count('codec', valid)}")
    print(f"orientation: {count('orientation', valid)}")
    print(f"container: {count('extension', valid)}; with audio: {sum(1 for r in valid if r.get('hasAudio'))}")
    print("largest:")
    for row in sorted(files, key=lambda r: -r["size"])[:5]:
        print(f"  {row['size'] / 1e6:8.1f} MB  {row.get('width')}x{row.get('height')} {row.get('fps')} fps "
              f"{(row.get('bitRate') or 0) / 1e6:.1f} Mb/s  {row['path']}")
    for row in invalid:
        print(f"invalid: {row['path']}: {row.get('problem')}")


# MARK: Wallpaper Engine scenes

HERE = os.path.dirname(os.path.abspath(__file__))


def wetex_tool(library):
    """The texture decoder (scripts/wetex.swift), compiled once into the library."""
    source = os.path.join(HERE, "wetex.swift")
    binary = os.path.join(library, "bin", "wetex")
    if not os.path.exists(binary) or os.path.getmtime(binary) < os.path.getmtime(source):
        os.makedirs(os.path.dirname(binary), exist_ok=True)
        result = subprocess.run(["xcrun", "swiftc", "-O", source, "-o", binary], capture_output=True, text=True)
        if result.returncode != 0:
            sys.exit(f"couldn't compile wetex.swift:\n{result.stderr[:500]}")
    return binary


class Package:
    """Files of a Wallpaper Engine scene: a scene.pkg archive, or loose files in the folder."""

    def __init__(self, folder, name):
        import struct
        self.folder, self.entries, self.path = folder, {}, os.path.join(folder, name)
        if os.path.isfile(self.path):
            with open(self.path, "rb") as handle:
                def text():
                    count = struct.unpack("<i", handle.read(4))[0]
                    return handle.read(count).decode("utf-8", "replace")
                text()
                count = struct.unpack("<i", handle.read(4))[0]
                raw = []
                for _ in range(count):
                    entry = text()
                    offset, length = struct.unpack("<ii", handle.read(8))
                    raw.append((entry, offset, length))
                base = handle.tell()
            self.entries = {entry: (base + offset, length) for entry, offset, length in raw}

    def has(self, name):
        return name in self.entries or os.path.isfile(os.path.join(self.folder, name))

    def read(self, name):
        if name in self.entries:
            offset, length = self.entries[name]
            with open(self.path, "rb") as handle:
                handle.seek(offset)
                return handle.read(length)
        with open(os.path.join(self.folder, name), "rb") as handle:
            return handle.read()

    def json(self, name):
        try:
            return json.loads(self.read(name).decode("utf-8-sig", "replace"))
        except (OSError, KeyError, json.JSONDecodeError, UnicodeDecodeError):
            return None


def value(field, default=None):
    """Scene values are plain, or {"user": …, "value": …} when bound to a setting."""
    if isinstance(field, dict):
        field = field.get("value", default)
    return default if field is None else field


def vector(field, default):
    field = value(field)
    if isinstance(field, str):
        try:
            parts = [float(p) for p in field.split()]
            return parts + default[len(parts):]
        except ValueError:
            return default
    if isinstance(field, (int, float)):
        return [float(field)] * len(default)
    return default


def decode_texture(package, name, work, wetex, frames=False):
    """A scene texture as a picture file (or frames, or an MP4), via wetex."""
    path = f"materials/{name}.tex"
    if not package.has(path):
        return None
    source = os.path.join(work, hashlib.sha1(path.encode()).hexdigest()[:12] + ".tex")
    with open(source, "wb") as handle:
        handle.write(package.read(path))
    command = [wetex, source, source[:-4] + ("-frames" if frames else "")] + (["--frames"] if frames else [])
    result = subprocess.run(command, capture_output=True, text=True)
    try:
        info = json.loads(result.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError):
        return None
    return None if "error" in info else info


def scene_layers(package, scene, work, wetex):
    """The picture layers of a scene, bottom first, in scene coordinates (y up)."""
    objects = scene.get("objects") or []
    by_id = {o.get("id"): o for o in objects if isinstance(o, dict)}
    layers, skipped = [], collections.Counter()

    def transform(obj, depth=0):
        origin = vector(obj.get("origin"), [0.0, 0.0, 0.0])
        scale = vector(obj.get("scale"), [1.0, 1.0, 1.0])
        parent = by_id.get(obj.get("parent"))
        if parent is not None and depth < 8:
            (px, py), (sx, sy) = transform(parent, depth + 1)
            return (px + origin[0] * sx, py + origin[1] * sy), (scale[0] * sx, scale[1] * sy)
        return (origin[0], origin[1]), (scale[0], scale[1])

    for obj in objects:
        if not isinstance(obj, dict):
            continue
        kind = next((k for k in ("image", "particle", "text", "sound", "light", "model") if k in obj), "other")
        if kind != "image" or not isinstance(obj.get("image"), str):
            skipped[kind] += 1
            continue
        if not value(obj.get("visible"), True) or float(value(obj.get("alpha"), 1.0) or 0) <= 0.01:
            skipped["hidden"] += 1
            continue
        model = package.json(obj["image"]) or {}
        # A solid colour layer under every picture is the background the artwork
        # sits on. Anywhere else, or carrying effects, it's a mask or a tint
        # that only makes sense with the effects drawn, so it's left out.
        if obj["image"].endswith("util/solidlayer.json"):
            size = vector(obj.get("size"), [0.0, 0.0])
            (x, y), (sx, sy) = transform(obj)
            if not layers and not obj.get("effects") and size[0] * abs(sx) >= 1 and size[1] * abs(sy) >= 1:
                rgb = vector(obj.get("color"), [1.0, 1.0, 1.0])
                layers.append({"color": "".join(f"{max(0, min(255, int(c * 255))):02x}" for c in rgb[:3]),
                               "x": x, "y": y, "width": size[0] * abs(sx), "height": size[1] * abs(sy),
                               "flipX": False, "flipY": False, "angle": vector(obj.get("angles"), [0.0, 0.0, 0.0])[2],
                               "alpha": float(value(obj.get("alpha"), 1.0) or 1.0), "animated": False, "pixels": 0})
            continue
        if model.get("fullscreen") or "util/" in obj["image"]:
            skipped["effect layer"] += 1
            continue
        material = package.json(model.get("material", "")) or {}
        passes = material.get("passes") or [{}]
        textures = passes[0].get("textures") or []
        texture = textures[0] if textures else None
        if not isinstance(texture, str) or texture.startswith("_rt_") or texture.startswith("util/"):
            skipped["no picture"] += 1
            continue
        info = decode_texture(package, texture, work, wetex)
        if not info or info.get("kind") != "image":
            skipped["undecodable"] += 1
            continue
        size = vector(obj.get("size"), [float(model.get("width") or info["width"]), float(model.get("height") or info["height"])])
        (x, y), (sx, sy) = transform(obj)
        if size[0] * abs(sx) < 1 or size[1] * abs(sy) < 1:
            skipped["zero size"] += 1
            continue
        layers.append({"file": info["file"], "x": x, "y": y, "width": size[0] * abs(sx), "height": size[1] * abs(sy),
                       "flipX": sx < 0, "flipY": sy < 0, "angle": vector(obj.get("angles"), [0.0, 0.0, 0.0])[2],
                       "alpha": float(value(obj.get("alpha"), 1.0) or 1.0), "animated": info.get("animated", False),
                       "pixels": info["width"] * info["height"]})
    return layers, skipped


def compose(layers, canvas, clear, output, long_side=3840):
    """Draws the layers onto the canvas with ffmpeg, scaled to at most `long_side`."""
    width, height = canvas
    factor = min(1.0, long_side / max(width, height))
    W, H = max(2, int(width * factor) // 2 * 2), max(2, int(height * factor) // 2 * 2)
    inputs = ["-f", "lavfi", "-i", f"color=c=0x{clear}:s={W}x{H}:d=1"]
    chains, last = [], "0:v"
    for index, layer in enumerate(layers, 1):
        w, h = max(2, int(layer["width"] * factor)), max(2, int(layer["height"] * factor))
        filters = [f"scale={w}:{h}", "format=rgba"]
        if layer["flipX"]:
            filters.append("hflip")
        if layer["flipY"]:
            filters.append("vflip")
        if abs(layer["angle"]) > 0.01:
            filters.append(f"rotate={-layer['angle']}:c=none:ow=rotw({-layer['angle']}):oh=roth({-layer['angle']})")
        if layer["alpha"] < 0.999:
            filters.append(f"colorchannelmixer=aa={layer['alpha']:.3f}")
        if "color" in layer:
            inputs += ["-f", "lavfi", "-i", f"color=c=0x{layer['color']}:s={w}x{h}:d=1"]
        else:
            inputs += ["-i", layer["file"]]
        chains.append(f"[{index}:v]{','.join(filters)}[l{index}]")
        # Scene y points up from the bottom; images are placed by their centre.
        x = f"{layer['x'] * factor:.1f}-overlay_w/2"
        y = f"{H - layer['y'] * factor:.1f}-overlay_h/2"
        chains.append(f"[{last}][l{index}]overlay=x={x}:y={y}:format=auto[b{index}]")
        last = f"b{index}"
    graph = ";".join(chains) if chains else "[0:v]null[b0]"
    command = [FFMPEG, "-v", "error", "-y"] + inputs + ["-filter_complex", graph, "-map", f"[{last if chains else 'b0'}]",
                                                         "-frames:v", "1", "-q:v", "2", output]
    result = subprocess.run(command, capture_output=True, text=True)
    return None if result.returncode == 0 and os.path.exists(output) else (result.stderr.strip()[-300:] or "ffmpeg failed")


def preview_hash(folder, project):
    """The Workshop preview's difference hash, to check a composed still against."""
    preview = os.path.join(folder, project.get("preview") or "preview.jpg")
    for candidate in (preview, os.path.join(folder, "preview.jpg"), os.path.join(folder, "preview.gif")):
        if os.path.isfile(candidate):
            return dhash(candidate)
    return None


def gif_video(package, texture, work, wetex, output):
    """A GIF scene's frames as a looping H.264 video, pixels kept sharp when scaled up."""
    info = decode_texture(package, texture, work, wetex, frames=True)
    if not info or info.get("kind") != "frames" or not info.get("count"):
        return "no frames"
    listing = os.path.join(info["dir"], "frames.txt")
    with open(listing, "w") as handle:
        for index, duration in enumerate(info["times"], 1):
            handle.write(f"file 'frame-{index:04d}.png'\nduration {max(duration, 0.02):.3f}\n")
        handle.write(f"file 'frame-{len(info['times']):04d}.png'\n")
    first = os.path.join(info["dir"], "frame-0001.png")
    result = subprocess.run([FFPROBE, "-v", "error", "-select_streams", "v", "-show_entries", "stream=width,height", "-of", "csv=p=0", first],
                            capture_output=True, text=True)
    try:
        w, h = [int(v) for v in result.stdout.strip().split(",")[:2]]
    except ValueError:
        return "unreadable frames"
    factor = max(1, int(2160 / h))
    result = subprocess.run([FFMPEG, "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing,
                             "-vf", f"scale={w * factor}:{h * factor}:flags=neighbor,format=yuv420p,fps=30",
                             "-c:v", "h264_videotoolbox", "-b:v", "12M", "-movflags", "+faststart", output],
                            capture_output=True, text=True)
    return None if result.returncode == 0 else result.stderr.strip()[-300:]


def import_scene(folder, project, library, wetex, item_id):
    """A still (or, for GIF scenes and video textures, a video) for one scene.
    Returns (entry fields, problem)."""
    import tempfile
    file_name = project.get("file") or "scene.json"
    package = Package(folder, os.path.splitext(file_name)[0] + ".pkg")
    scene = package.json(file_name)
    if scene is None:
        return None, "no scene description"
    general = scene.get("general") or {}
    projection = general.get("orthogonalprojection") or {}
    canvas = (int(projection.get("width") or 0), int(projection.get("height") or 0))
    clear_rgb = vector(general.get("clearcolor"), [0.0, 0.0, 0.0])
    clear = "".join(f"{max(0, min(255, int(c * 255))):02x}" for c in clear_rgb[:3])
    with tempfile.TemporaryDirectory() as work:
        # A video texture inside: that's the wallpaper. The biggest one, since
        # smaller ones are masks and overlays for it.
        videos = []
        for name in [n for n in package.entries if n.endswith(".tex")]:
            info = decode_texture(package, name[len("materials/"):-4], work, wetex) if name.startswith("materials/") else None
            if info and info.get("kind") == "mp4":
                videos.append((os.path.getsize(info["file"]), info["file"]))
        if videos:
            output = os.path.join(library, "extracted", f"{item_id}.mp4")
            os.makedirs(os.path.dirname(output), exist_ok=True)
            shutil.copyfile(max(videos)[1], output)
            return {"kind": "video", "playback": f"extracted/{item_id}.mp4", "source": "video texture"}, None
        layers, skipped = scene_layers(package, scene, work, wetex)
        pictures = [layer for layer in layers if "file" in layer]
        if file_name.startswith("gifscene") or (len(pictures) == 1 and pictures[0]["animated"]):
            obj = next((o for o in scene.get("objects", []) if isinstance(o, dict) and isinstance(o.get("image"), str)
                        and "util/" not in o["image"]), None)
            model = package.json(obj["image"]) if obj else {}
            material = package.json((model or {}).get("material", "")) or {}
            texture = ((material.get("passes") or [{}])[0].get("textures") or [None])[0]
            output = os.path.join(library, "extracted", f"{item_id}.mp4")
            os.makedirs(os.path.dirname(output), exist_ok=True)
            problem = gif_video(package, texture, work, wetex, output) if texture else "no texture"
            if problem:
                return None, f"GIF scene: {problem}"
            return {"kind": "video", "playback": f"extracted/{item_id}.mp4", "source": "gif frames"}, None
        # Sprite sheets drawn whole would show every frame at once.
        layers = [layer for layer in layers if not layer["animated"]]
        if not any("file" in layer for layer in layers):
            return None, "nothing drawable (" + ", ".join(f"{k} {v}" for k, v in skipped.items()) + ")"
        if canvas[0] < 2 or canvas[1] < 2:
            biggest = max(layers, key=lambda l: l["width"] * l["height"])
            canvas = (max(2, int(biggest["width"])), max(2, int(biggest["height"])))
        output = os.path.join(library, "stills", f"{item_id}.jpg")
        os.makedirs(os.path.dirname(output), exist_ok=True)
        problem = compose(layers, canvas, clear, output)
        if problem:
            return None, f"couldn't compose: {problem}"
        reference = preview_hash(folder, project)
        composed = dhash(output, square=True)
        distance = bin(reference ^ composed).count("1") if reference is not None and composed is not None else None
        factor = min(1.0, 3840 / max(canvas))
        return {"kind": "image", "playback": f"stills/{item_id}.jpg", "source": "composed layers",
                "layers": len(layers), "previewDistance": distance,
                "width": int(canvas[0] * factor) // 2 * 2, "height": int(canvas[1] * factor) // 2 * 2}, None


# MARK: Import

# The app's wallpaper categories (Aerial.Category in AllSetCore), in the
# order a title keyword is tried. Two were added for this library: games and abstract.
KEYWORDS = [
    ("cities", ["city", "cities", "street", "alley", "neon", "cyberpunk", "tokyo", "downtown", "skyline", "城", "街"]),
    # Single CJK characters like 海 (sea: also in 云海 "sea of clouds" and 海报
    # "poster") or 星 (star) are too ambiguous to decide a category alone.
    ("underwater", ["underwater", "ocean", "sea", "reef", "dive", "diving", "fish", "潜水", "海底", "深海"]),
    ("space", ["space", "earth", "planet", "meteor", "galaxy", "nebula", "moon", "宇宙", "星空"]),
    ("landscapes", ["landscape", "nature", "sky", "lake", "forest", "mountain", "cloud", "river", "field", "sunset",
                    "湖", "云", "风", "山", "树", "林", "花"]),
]
TAG_CATEGORIES = {"game": "games", "landscape": "landscapes", "nature": "landscapes", "relaxing": "landscapes",
                  "animal": "landscapes", "cyberpunk": "cities", "abstract": "abstract", "pixel art": "abstract",
                  "cgi": "abstract", "anime": "abstract", "sports": "games"}

# Wallpaper-site decorations in titles: "【动态壁纸/4K/纯风景】", " - 4K", "(With BGM)", "by b站@…"
NOISE = [r"【[^】]*(壁纸|4K|4k|风景|动态)[^】]*】", r"\((with )?bgm\)", r"\b(4k|8k|2k|qhd|uhd|hd|1080p|1440p|2160p)\b",
         r"\b\d{2,3}\s?fps\b", r"\b(animated|loop(ed)?|wallpaper engine|official)\b", r"\bby\s+\S*b站\S*", r"[-—_]+\s*b站.*$",
         r"b站@\S+", r"_?简单循环.*$", r"_v\d+(\.\d+)*$", r"-?moewalls-com", r"\bedit(ed)? by .*$", r"动态壁纸", r"官网",
         r"[，,]?\s*[48]k\s*\d*\s*帧", r"\d+\s*帧", r"\s*[/／]\s*背景", r"\s[-—|]\s*by[:\s]+\S+.*$",
         r"\(?\b\d{3,4}\s*[x×]\s*\d{3,4}\b\)?", r"\[[^\]]*\bmusic\s*\]", r"\s*[-|]*\s*\|\s*random soundtracks.*$", r"\s*\|\s*full\s*$"]


def clean_title(text):
    import re
    title = text or ""
    for pattern in NOISE:
        title = re.sub(pattern, " ", title, flags=re.IGNORECASE)
    title = title.strip()
    # "horizon-sky-wanderer" → "Horizon Sky Wanderer"
    if title and not re.search(r"\s", title) and re.search(r"[-_]", title) and title.isascii():
        title = re.sub(r"[-_]+", " ", title).title()
    title = re.sub(r"\s*[-—|:：]\s*$", "", title.strip())
    title = re.sub(r"^\s*[-—|:：]\s*", "", title)
    # Brackets emptied by the cleaning above: "[ ]", "[ , music]" → "", "[music]".
    for _ in range(2):
        title = re.sub(r"[\[(（【]\s*[,+&|/]*\s*[\])）】]", " ", title)
        title = re.sub(r"([\[(（【])\s*[,+&|/]\s*", r"\1", title)
        title = re.sub(r"\s*[,+&|/]\s*([\])）】])", r"\1", title)
    title = re.sub(r"([\[(（【])\s+", r"\1", title)
    title = re.sub(r"\s+([\])）】])", r"\1", title)
    title = re.sub(r"\s{2,}", " ", title).strip(" -—_|")
    # "[Island sunset]" → "Island sunset": a name that is all bracket.
    whole = re.fullmatch(r"[\[【]([^\]】]+)[\]】]", title)
    if whole:
        title = whole.group(1).strip()
    # "arthas", "hunt showdown" → "Arthas", "Hunt Showdown"
    if title.isascii() and title == title.lower() and any(c.isalpha() for c in title):
        title = title.title()
    return title


def title_for(record, path):
    """A readable name: the Workshop title, else the file name, never a raw camera or download name."""
    import re
    workshop = record.get("workshop") or {}
    for candidate in (workshop.get("title"), os.path.splitext(os.path.basename(path))[0], os.path.basename(os.path.dirname(path))):
        title = clean_title(candidate)
        # Names made by cameras, downloaders or hashes aren't titles.
        if title and not re.fullmatch(r"(img|vid|dsc|mov|video|ssstik\.io|tikvid\.io|ytdown\.com)?[\W_\d]*[a-f0-9]{12,}?[\W_\d]*",
                                      title, flags=re.IGNORECASE) and not re.match(r"(ssstik|tikvid|ytdown)", title, re.IGNORECASE):
            return title[:80]
    return "Untitled video"


def category_for(title, tags):
    words = title.lower()
    lowered = [t.lower() for t in tags]
    if "game" in lowered:
        return "games"
    for category, keys in KEYWORDS[:3]:
        if any(key in words for key in keys):
            return category
    for tag in lowered:
        if tag in TAG_CATEGORIES:
            return TAG_CATEGORIES[tag]
    if any(key in words for key in KEYWORDS[3][1]):
        return "landscapes"
    return "abstract"


def resolution_tag(width, height):
    long = max(width or 0, height or 0)
    return "8k" if long >= 7680 else "4k" if long >= 3840 else "1440p" if long >= 2560 else "1080p" if long >= 1920 else "hd"


def needs_transcode(record):
    """Why a file can't be played as it is, or None. Measured (docs/wallpaper-import.md):
    larger than the hardware decoder's 4096×2304 falls back to software (75 % of a core);
    more than 60 frames a second doubles decoding for frames a 60 Hz screen never shows."""
    reasons = []
    if (record.get("codec") or "") not in ("h264", "hevc"):
        reasons.append(f"codec {record.get('codec')}")
    if record.get("extension") not in (".mp4", ".mov", ".m4v"):
        reasons.append(f"container {record.get('extension')}")
    if (record.get("width") or 0) > 4096 or (record.get("height") or 0) > 2304:
        reasons.append(f"{record.get('width')}×{record.get('height')} is beyond hardware decoding")
    if (record.get("fps") or 0) > 61:
        reasons.append(f"{record.get('fps'):g} fps")
    return ", ".join(reasons) or None


def transcode(source, destination, record):
    """HEVC in hardware, at most 3840×2160 and 60 fps, no audio (wallpapers play muted)."""
    fps = min(record.get("fps") or 60, 60)
    bitrate = max(8, min(int((record.get("bitRate") or 20_000_000) / 1e6), 30))
    temporary = destination + ".part.mp4"
    command = [FFMPEG, "-v", "error", "-y", "-i", source, "-an",
               "-vf", f"scale='min(3840,iw)':'min(2160,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2,fps={fps:g}",
               "-c:v", "hevc_videotoolbox", "-b:v", f"{bitrate}M", "-tag:v", "hvc1", "-movflags", "+faststart", temporary]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(temporary):
        return result.stderr.strip()[:300] or "ffmpeg failed"
    os.replace(temporary, destination)
    return None


def thumbnail(source, destination, duration):
    at = max(0.0, min(2.0, duration * 0.3))
    # Seeking in a single picture skips its only frame: stills aren't seeked.
    seek = ["-ss", f"{at:.2f}"] if duration > 0 else []
    subprocess.run([FFMPEG, "-v", "error", "-y"] + seek + ["-i", source, "-frames:v", "1",
                    "-vf", "scale=640:-2", "-q:v", "4", destination], capture_output=True)
    return os.path.exists(destination)


def dhash(path, square=False):
    """A 64-bit difference hash of a picture (of its centre square, to compare
    with Workshop previews, which are square crops), for finding near-duplicates."""
    crop = "crop='min(iw,ih)':'min(iw,ih)'," if square else ""
    result = subprocess.run([FFMPEG, "-v", "error", "-i", path, "-frames:v", "1", "-vf", f"{crop}scale=9:8,format=gray",
                             "-f", "rawvideo", "-"], capture_output=True)
    pixels = result.stdout
    if len(pixels) < 72:
        return None
    bits = 0
    for row in range(8):
        for column in range(8):
            bits = (bits << 1) | (pixels[row * 9 + column] > pixels[row * 9 + column + 1])
    return bits


def loops_in_page(root, relative):
    """Whether a web wallpaper's page plays this video on a loop (a background),
    rather than as a one-off clip of an interaction."""
    import re
    folder = os.path.join(root, relative.split(os.sep)[0])
    name = os.path.basename(relative)
    text = ""
    for base, _, names in os.walk(folder):
        for page in names:
            if page.endswith((".html", ".js")) and os.path.getsize(os.path.join(base, page)) < 2_000_000:
                with open(os.path.join(base, page), encoding="utf-8", errors="replace") as handle:
                    text += handle.read() + "\n"
    tags = re.findall(r"<video\b[^>]*>", text, flags=re.IGNORECASE)
    # 1. A <video> tag naming the file: it loops if that tag says so.
    for tag in tags:
        if name in tag:
            return re.search(r"\bloop\b", tag, flags=re.IGNORECASE) is not None
    # 2. Tags without sources, filled in by script: they loop if all of them do.
    if tags and name in text:
        return all(re.search(r"\bloop\b", tag, flags=re.IGNORECASE) for tag in tags)
    # 3. Videos made in script: `.loop = true` (or loop: true) close to the name.
    for match in re.finditer(re.escape(name), text):
        around = text[max(0, match.start() - 200):match.start()] + text[match.end():match.end() + 200]
        if re.search(r"loop\s*[:=]\s*true", around, flags=re.IGNORECASE):
            return True
    return False


# Scenes left out after checking every one by eye against its Workshop preview
# (2026-09-27): pictures that come out wrong without Wallpaper Engine's
# effects, and a second upload of the same artwork.
SCENE_REVIEWED_SKIP = {
    "3577452645": "the towers are drawn by effects: only the sky comes out",
    "3572340969": "only the sky strip comes out, not the characters",
    "3684060242": "the city photos sit under an effect: only the menu ring comes out",
    "3299228616": "a black audio-visualizer layer covers the picture",
    "3448877775": "the video inside is a chroma mask, not the picture",
    "3645009840": "the statue comes out cut into bars (glitch effect layers)",
    "3682811008": "the same picture as 3624164256 (Resident Evil 9 - Requiem), at 1080p instead of 4K",
}


# Bumped whenever scenes would come out differently: cached results from an
# older renderer are redone.
SCENE_RENDERER = 3


def import_scenes(root, library, summary, entries, existing, skipped, now, root_id):
    """Every Wallpaper Engine scene item in the folder, as catalog entries."""
    items = workshop_items(root)
    wetex = wetex_tool(library)
    cache_path = os.path.join(library, "scenes.json")
    try:
        with open(cache_path) as handle:
            cache = json.load(handle)
    except (OSError, json.JSONDecodeError):
        cache = {}
    imported = []
    for workshop_id, project in items.items():
        if (project.get("type") or "").lower() != "scene":
            continue
        if workshop_id in SCENE_REVIEWED_SKIP:
            skipped.append((workshop_id, f"{project.get('title')}: {SCENE_REVIEWED_SKIP[workshop_id]}"))
            continue
        folder = os.path.join(root, workshop_id)
        package_name = os.path.splitext(project.get("file") or "scene.json")[0] + ".pkg"
        package_path = os.path.join(folder, package_name)
        if not os.path.isfile(package_path):
            skipped.append((workshop_id, "scene without a package"))
            continue
        stat = os.stat(package_path)
        known = cache.get(workshop_id, {})
        if known.get("size") == stat.st_size and known.get("mtime") == int(stat.st_mtime):
            digest = known["sha256"]
        else:
            digest = sha256(package_path)
            known = {"size": stat.st_size, "mtime": int(stat.st_mtime), "sha256": digest}
        item_id = digest[:16]
        result = known.get("result") if known.get("result") and known.get("sha256") == digest else None
        current = known.get("renderer") == SCENE_RENDERER
        output_ok = result and current and os.path.exists(os.path.join(library, result.get("playback", "")))
        if not output_ok:
            if not current:
                for stale in ("stills/{}.jpg", "extracted/{}.mp4", "transcoded/{}.mp4"):
                    path = os.path.join(library, stale.format(item_id))
                    if os.path.exists(path):
                        os.remove(path)
            known["renderer"] = SCENE_RENDERER
            try:
                result, problem = import_scene(folder, project, library, wetex, item_id)
            except Exception as error:  # one broken scene must not stop the batch
                result, problem = None, f"failed: {type(error).__name__}: {error}"
            if problem:
                skipped.append((workshop_id, f"{project.get('title')}: {problem}"))
                known.pop("result", None)
                cache[workshop_id] = known
                continue
            if result["kind"] == "video":
                media = os.path.join(library, result["playback"])
                described = describe(media)
                result.update({k: described.get(k) for k in ("duration", "width", "height", "fps", "codec", "bitRate")})
                reason = needs_transcode(dict(described, extension=".mp4"))
                if reason:
                    output = os.path.join(library, "transcoded", f"{item_id}.mp4")
                    error = None if os.path.exists(output) else transcode(media, output, described)
                    if error:
                        skipped.append((workshop_id, f"video texture can't play: {error}"))
                        continue
                    os.remove(media)
                    result.update(playback=f"transcoded/{item_id}.mp4", transcodedBecause=reason)
            known["result"] = result
            cache[workshop_id] = known
            # Saved as it goes: an interrupted run resumes where it stopped.
            with open(cache_path, "w") as handle:
                json.dump(cache, handle, indent=1, ensure_ascii=False)
        media = os.path.join(library, result["playback"])
        title = title_for({"workshop": {"title": project.get("title")}}, package_path)
        tags = [t for t in project.get("tags") or [] if t.lower() != "unspecified"]
        category = category_for(title, tags)
        rating = project.get("contentrating")
        entry = {
            "id": item_id, "title": title, "category": category, "kind": result["kind"],
            "tags": sorted({t.lower() for t in tags} | {category, resolution_tag(result.get("width"), result.get("height")),
                                                        "still" if result["kind"] == "image" else "live"}),
            "root": root_id, "file": os.path.relpath(package_path, root), "playback": result["playback"],
            "thumbnail": f"thumbnails/{item_id}.jpg", "duration": result.get("duration"),
            "width": result.get("width"), "height": result.get("height"), "fps": result.get("fps"),
            "size": os.path.getsize(media), "sha256": digest, "contentRating": rating,
            "status": "quarantined",
            "statusReason": "license and author unknown" + ("" if rating == "Everyone" else "; no content rating")
                            + ("; the scene's animation and effects aren't included" if result["kind"] == "image" else ""),
            "provenance": {"source": "steam-workshop-scene", "workshopId": workshop_id, "originalTitle": project.get("title"),
                           "author": None, "license": None, "extractedFrom": result.get("source"),
                           "previewDistance": result.get("previewDistance")},
            "addedAt": existing.get(item_id, {}).get("addedAt", now),
        }
        if "transcodedBecause" in result:
            entry["transcodedBecause"] = result["transcodedBecause"]
        thumb = os.path.join(library, entry["thumbnail"])
        # Redrawn with its picture: a thumbnail older than it shows the old one.
        fresh = os.path.exists(thumb) and os.path.getmtime(thumb) >= os.path.getmtime(media)
        if not fresh and not thumbnail(media, thumb, result.get("duration") or 0):
            entry["thumbnail"] = None
        if item_id in entries:
            continue
        entries[item_id] = entry
        imported.append(item_id)
        print(f"  {entry['kind']:>5} {entry['category']:>10}  {entry['title']}", flush=True)
    with open(cache_path, "w") as handle:
        json.dump(cache, handle, indent=1, ensure_ascii=False)
    return imported


def import_library(root, library):
    """Turns a folder into catalog entries: one per unique video, keyed by content.
    Rerunning updates entries (and adds new files) instead of duplicating them."""
    summary = inventory(root, library)
    root = summary["root"]
    root_id = hashlib.sha1(root.encode()).hexdigest()[:8]
    os.makedirs(os.path.join(library, "thumbnails"), exist_ok=True)
    os.makedirs(os.path.join(library, "transcoded"), exist_ok=True)
    catalog_path = os.path.join(library, "catalog.json")
    try:
        with open(catalog_path) as handle:
            catalog = json.load(handle)
    except (OSError, json.JSONDecodeError):
        catalog = {"version": 1, "roots": [], "items": []}
    existing = {item["id"]: item for item in catalog.get("items", [])}
    now = datetime.datetime.now().isoformat(timespec="seconds")

    skipped, duplicates, entries = [], [], {}
    for record in summary["files"]:
        workshop = record.get("workshop")
        path = os.path.join(root, record["path"])
        if not record.get("valid"):
            skipped.append((record["path"], f"invalid: {record.get('problem')}"))
            continue
        looped = workshop and workshop.get("type") == "web" and loops_in_page(root, record["path"])
        if workshop and not (workshop.get("type") == "video" and workshop.get("isMainFile")) and not looped:
            skipped.append((record["path"], f"part of a {workshop.get('type') or 'unknown'} wallpaper, not a video wallpaper"))
            continue
        item_id = record["sha256"][:16]
        if item_id in entries:
            duplicates.append((record["path"], entries[item_id]["file"]))
            continue
        title = title_for(record, path)
        if looped:
            stem = os.path.splitext(os.path.basename(path))[0]
            clip = clean_title(stem.split("-")[-1].replace("_", " ")) or clean_title(stem.replace("-", " ").replace("_", " "))
            # Numbered clip names ("anim1 belt idle") read better without the number.
            import re
            clip = re.sub(r"^anim\d+\s*", "", clip, flags=re.IGNORECASE).strip() or clip
            title = f"{title} - {clip.title() if clip.islower() else clip}"[:80]
        tags = [t for t in (workshop or {}).get("tags", []) if t.lower() != "unspecified"]
        category = category_for(title, tags)
        rating = (workshop or {}).get("contentRating")
        entry = {
            "id": item_id,
            "title": title,
            "category": category,
            "kind": "video",
            "tags": sorted({t.lower() for t in tags} | {category, resolution_tag(record.get("width"), record.get("height"))}
                           | ({record["orientation"]} if record.get("orientation") in ("portrait", "ultrawide") else set())
                           | ({"60fps"} if (record.get("fps") or 0) >= 59 else set())),
            "root": root_id,
            "file": record["path"],
            "thumbnail": f"thumbnails/{item_id}.jpg",
            "duration": record.get("duration"),
            "width": record.get("width"),
            "height": record.get("height"),
            "fps": record.get("fps"),
            "codec": record.get("codec"),
            "bitRate": record.get("bitRate"),
            "size": record.get("size"),
            "orientation": record.get("orientation"),
            "sha256": record["sha256"],
            "contentRating": rating,
            # Nothing says who made these or whether they may be shared: they
            # play from your own drive and are never published or bundled.
            "status": "quarantined",
            "statusReason": "license and author unknown" + ("" if rating == "Everyone" else "; no content rating"),
            "provenance": {"source": "steam-workshop" if workshop else "local-folder",
                           "workshopId": (workshop or {}).get("id"), "originalTitle": (workshop or {}).get("title"),
                           "author": None, "license": None},
            "addedAt": existing.get(item_id, {}).get("addedAt", now),
        }
        thumb = os.path.join(library, entry["thumbnail"])
        if not os.path.exists(thumb) and not thumbnail(path, thumb, record.get("duration") or 0):
            entry["thumbnail"] = None
        reason = needs_transcode(record)
        if reason:
            output = os.path.join(library, "transcoded", f"{item_id}.mp4")
            error = None if os.path.exists(output) else transcode(path, output, record)
            if error:
                entry.update(status="unsupported", statusReason=f"{reason}; transcoding failed: {error}")
            else:
                entry.update(playback=f"transcoded/{item_id}.mp4", transcodedBecause=reason,
                             playbackSize=os.path.getsize(output))
        entries[item_id] = entry
        print(f"  {entry['category']:>10}  {entry['title']}", flush=True)

    # Wallpaper Engine scenes: their artwork as a sharp still, or, when the
    # scene is really a video (a video texture, a GIF), that video.
    scene_ids = import_scenes(root, library, summary, entries, existing, skipped, now, root_id)
    print(f"scenes: {len(scene_ids)} imported", flush=True)

    # Other folders' entries stay; this folder's are replaced by this scan.
    kept = [item for item in catalog.get("items", []) if item.get("root") != root_id]
    catalog["items"] = kept + sorted(entries.values(), key=lambda e: e["title"].lower())
    roots = [r for r in catalog.get("roots", []) if r.get("id") != root_id]
    catalog["roots"] = roots + [{"id": root_id, "path": root, "label": os.path.basename(root)}]
    catalog["version"] = 1
    catalog["updatedAt"] = now
    with open(catalog_path + ".tmp", "w") as handle:
        json.dump(catalog, handle, indent=1, ensure_ascii=False)
    os.replace(catalog_path + ".tmp", catalog_path)

    # Pictures and copies this importer made that no entry uses any more
    # (a scene left out, a video gone from the folder): only its own folders.
    used = {item.get(key) for item in catalog["items"] for key in ("playback", "thumbnail") if item.get(key)}
    for folder in ("stills", "extracted", "transcoded", "thumbnails"):
        directory = os.path.join(library, folder)
        for name in os.listdir(directory) if os.path.isdir(directory) else []:
            if f"{folder}/{name}" not in used and os.path.isfile(os.path.join(directory, name)):
                os.remove(os.path.join(directory, name))

    # Near-duplicates for a person to review (never removed automatically).
    hashes = {e["id"]: dhash(os.path.join(library, e["thumbnail"])) for e in entries.values() if e.get("thumbnail")}
    near = []
    items = [e for e in entries.values() if hashes.get(e["id"]) is not None]
    for i, a in enumerate(items):
        for b in items[i + 1:]:
            distance = bin(hashes[a["id"]] ^ hashes[b["id"]]).count("1")
            if distance <= 8 and abs((a.get("duration") or 0) - (b.get("duration") or 0)) < 1.0:
                near.append({"a": a["title"], "b": b["title"], "distance": distance})
    with open(os.path.join(library, "import-report.json"), "w") as handle:
        json.dump({"root": root, "importedAt": now, "imported": len(entries), "skipped": skipped,
                   "duplicates": duplicates, "nearDuplicates": near}, handle, indent=1, ensure_ascii=False)
    size = sum(e["size"] or 0 for e in entries.values() if e.get("kind") == "video" and not e.get("playback"))
    transcoded = [e for e in entries.values() if e.get("transcodedBecause")]
    extracted = [e for e in entries.values() if (e.get("playback") or "").startswith(("stills/", "extracted/"))]

    def on_disk(entries):
        return sum(os.path.getsize(os.path.join(library, e["playback"])) for e in entries
                   if os.path.exists(os.path.join(library, e["playback"]))) / 1e9

    kinds = {k: sum(1 for e in entries.values() if e.get("kind") == k) for k in ("video", "image")}
    print(f"\n== import ==\nimported {len(entries)} wallpapers: {kinds['video']} live, {kinds['image']} stills")
    print(f"played from {root}: {size / 1e9:.2f} GB (not copied)")
    print(f"skipped {len(skipped)}; exact duplicates {len(duplicates)}; near-duplicates to review {len(near)}")
    print(f"transcoded {len(transcoded)} ({on_disk(transcoded):.2f} GB): " + "; ".join(f"{e['title']} ({e['transcodedBecause']})" for e in transcoded))
    print(f"extracted from scenes {len(extracted)} ({on_disk(extracted):.2f} GB)")
    print(f"categories: { {c: sum(1 for e in entries.values() if e['category'] == c) for c in sorted({e['category'] for e in entries.values()})} }")
    print(f"status: { {s: sum(1 for e in entries.values() if e['status'] == s) for s in sorted({e['status'] for e in entries.values()})} }")
    for path, reason in skipped:
        print(f"  skipped {path}: {reason}")


def main():
    global FFPROBE, FFMPEG
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["inventory", "import"])
    parser.add_argument("folder")
    parser.add_argument("--library", default=DEFAULT_LIBRARY, help="where the app's library lives")
    args = parser.parse_args()
    FFPROBE, FFMPEG = tool("ffprobe"), tool("ffmpeg")
    if args.command == "inventory":
        inventory(args.folder, args.library)
    else:
        import_library(args.folder, args.library)


if __name__ == "__main__":
    main()
