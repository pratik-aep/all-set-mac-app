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
         r"[，,]?\s*[48]k\s*\d*\s*帧", r"\d+\s*帧", r"\s*[/／]\s*背景"]


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
    title = re.sub(r"\s{2,}", " ", title).strip(" -—_|")
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
    subprocess.run([FFMPEG, "-v", "error", "-y", "-ss", f"{at:.2f}", "-i", source, "-frames:v", "1",
                    "-vf", "scale=640:-2", "-q:v", "4", destination], capture_output=True)
    return os.path.exists(destination)


def dhash(path):
    """A 64-bit difference hash of a picture, for finding near-duplicates."""
    result = subprocess.run([FFMPEG, "-v", "error", "-i", path, "-vf", "scale=9:8,format=gray", "-f", "rawvideo", "-"],
                            capture_output=True)
    pixels = result.stdout
    if len(pixels) < 72:
        return None
    bits = 0
    for row in range(8):
        for column in range(8):
            bits = (bits << 1) | (pixels[row * 9 + column] > pixels[row * 9 + column + 1])
    return bits


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
        if workshop and not (workshop.get("type") == "video" and workshop.get("isMainFile")):
            skipped.append((record["path"], f"part of a {workshop.get('type') or 'unknown'} wallpaper, not a video wallpaper"))
            continue
        item_id = record["sha256"][:16]
        if item_id in entries:
            duplicates.append((record["path"], entries[item_id]["file"]))
            continue
        title = title_for(record, path)
        tags = [t for t in (workshop or {}).get("tags", []) if t.lower() != "unspecified"]
        category = category_for(title, tags)
        rating = (workshop or {}).get("contentRating")
        entry = {
            "id": item_id,
            "title": title,
            "category": category,
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
    size = sum(e["size"] for e in entries.values())
    transcoded = [e for e in entries.values() if e.get("playback")]
    print(f"\n== import ==\nimported {len(entries)} unique videos ({size / 1e9:.2f} GB, played from {root})")
    print(f"skipped {len(skipped)}; exact duplicates {len(duplicates)}; near-duplicates to review {len(near)}")
    print(f"transcoded {len(transcoded)} ({sum(e['playbackSize'] for e in transcoded) / 1e9:.2f} GB in the library): "
          + "; ".join(f"{e['title']} ({e['transcodedBecause']})" for e in transcoded))
    print(f"categories: { {c: sum(1 for e in entries.values() if e['category'] == c) for c in sorted({e['category'] for e in entries.values()})} }")
    print(f"status: { {s: sum(1 for e in entries.values() if e['status'] == s) for s in sorted({e['status'] for e in entries.values()})} }")


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
