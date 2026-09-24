"""Download every non-track asset the mod's objects reference, into assets/raw/.

Track board images are handled separately by download_maps.py, which reads
their URLs from maps.json -- this script skips anything that appears there,
plus the (much larger) set of every map thumbnail TTS ever cached for the
mod, tracked in tools/extract/all_map_thumbs.json (see below).

The mod's own objects -- meshes, textures, colliders, the table, the sky,
custom decks, the dashboard UI thumbnail -- aren't listed anywhere in this
repo; TTS only knows them as fields buried in a save file. So this reads
them out of the most recently saved copy of the mod in the local TTS Saves
folder (SaveName/GameMode "Formula D Big Box Mod"), the same way
detect_track.py reads board art out of the TTS image cache.

Run:  python tools/extract/download_assets.py
"""
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

from tts_paths import TTS_DIR

ROOT = pathlib.Path(__file__).resolve().parents[2]
MAPS = ROOT / "tools" / "extract" / "maps.json"
ORIGINAL_XML = ROOT / "reference" / "original-2020" / "Custom Board.9e2fe8.xml"
OUT = ROOT / "assets" / "raw"

# Object fields that hold a downloadable asset; CustomUIAssets entries (a
# {Name, URL} list rather than one of these keys) are handled separately.
ASSET_KEYS = [
    "MeshURL", "DiffuseURL", "NormalURL", "ColliderURL",
    "AssetbundleURL", "AssetbundleSecondaryURL",
    "ImageURL", "ImageSecondaryURL",
    "FaceURL", "BackURL", "PDFUrl",
]

EXT = {"image/jpeg": ".jpg", "image/png": ".png", "image/gif": ".gif", "image/webp": ".webp",
       "application/pdf": ".pdf", "application/octet-stream": ".obj",
       "text/plain": ".obj", "model/obj": ".obj"}
SNIFF = [(b"\xff\xd8\xff", ".jpg"), (b"\x89PNG", ".png"), (b"GIF8", ".gif"),
         (b"RIFF", ".webp"), (b"%PDF", ".pdf")]
RETRIES = 3


def find_save():
    """Most recently modified Saves/*.json for this mod."""
    hits = []
    for f in (TTS_DIR / "Saves").glob("*.json"):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(data, dict) and data.get("GameMode", "").strip() == "Formula D Big Box Mod":
            hits.append((f.stat().st_mtime, f, data))
    if not hits:
        sys.exit('no save with GameMode "Formula D Big Box Mod" found under '
                  f"{TTS_DIR / 'Saves'} -- open the mod in TTS and save once")
    hits.sort(key=lambda h: h[0])
    _, path, data = hits[-1]
    return path, data


def track_thumb_names():
    """Every map thumbnail name the 2020 mod ever used (not just the ones we
    kept in maps.json) -- these are board art, so download_maps.py's job."""
    xml = ORIGINAL_XML.read_text(encoding="utf-8", errors="replace")
    names = set()
    for attrs, inner in re.findall(r'<Button\b([^>]*)>(.*?)</Button>', xml, re.S):
        if 'class="mapButton"' not in attrs:
            continue
        m = re.search(r'<Image\b[^>]*?\bimage\s*=\s*"([^"]+)"', inner)
        if m:
            names.add(m.group(1))
    return names


def collect(data):
    """(label, url) pairs, deduped by url, in first-seen order."""
    track_urls = {m["url"] for m in json.loads(MAPS.read_text(encoding="utf-8"))}
    skip_names = track_thumb_names()

    seen = {}  # url -> label
    order = []

    def label_of(url, label):
        if url in seen or url in track_urls or not url.startswith("http"):
            return
        seen[url] = label
        order.append(url)

    def walk(node, context):
        if isinstance(node, dict):
            if "GUID" in node:
                context = node.get("Nickname") or node.get("Name") or context
            for key in ASSET_KEYS:
                v = node.get(key)
                if isinstance(v, str) and v:
                    label_of(v, f"{context}_{key}")
            for k, v in node.items():
                if k not in ASSET_KEYS:
                    walk(v, context)
        elif isinstance(node, list):
            for item in node:
                walk(item, context)

    walk(data.get("ObjectStates", []), "object")
    for key in ("TableURL", "SkyURL"):
        v = data.get(key)
        if isinstance(v, str) and v:
            label_of(v, key.replace("URL", ""))
    for asset in data.get("CustomUIAssets", []):
        name, url = asset.get("Name"), asset.get("URL")
        if name in skip_names or not isinstance(url, str) or not url:
            continue
        label_of(url, f"ui_{name}")

    return [(seen[u], u) for u in order]


def slug(label):
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", label).strip("_") or "asset"


def unique_base(label, used):
    base = slug(label)
    n = 2
    while base in used:
        base = f"{slug(label)}_{n}"
        n += 1
    used.add(base)
    return base


def existing(base):
    return next(iter(OUT.glob(f"{base}.*")), None) if OUT.exists() else None


def extension(content_type, data):
    # Sniff first: Steam serves plain-text OBJ meshes under the same generic
    # content types (text/plain, application/octet-stream) as some images.
    for magic, e in SNIFF:
        if data.startswith(magic):
            return e
    ext = EXT.get((content_type or "").split(";")[0].strip().lower())
    if ext:
        return ext
    return ".bin"


def fetch(label, url, base):
    have = existing(base)
    if have:
        return base, "skip", have.name
    last = ""
    for attempt in range(RETRIES):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
                ext = extension(r.headers.get("Content-Type"), data)
            path = OUT / (base + ext)
            tmp = path.with_suffix(ext + ".part")
            tmp.write_bytes(data)
            tmp.replace(path)
            return base, "ok", f"{path.name} ({len(data) // 1024} KB)"
        except urllib.error.HTTPError as e:
            last = f"HTTP {e.code}"
            if e.code in (403, 404):
                break
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            last = str(e)
        time.sleep(1 + attempt)
    return base, "fail", last


def main():
    save_path, data = find_save()
    print(f"reading {save_path}")
    pairs = collect(data)
    print(f"{len(pairs)} unique non-track assets referenced")

    OUT.mkdir(parents=True, exist_ok=True)
    used = set()
    jobs = [(label, url, unique_base(label, used)) for label, url in pairs]

    counts = {"ok": 0, "skip": 0, "fail": 0}
    failures = []
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(fetch, label, url, base) for label, url, base in jobs]
        for n, fut in enumerate(as_completed(futures), 1):
            base, status, detail = fut.result()
            counts[status] += 1
            if status == "fail":
                failures.append((base, detail))
            if status != "skip":
                print(f"[{n}/{len(jobs)}] {status:4} {base}: {detail}", flush=True)

    print(f"\n{counts['ok']} downloaded, {counts['skip']} already present, "
          f"{counts['fail']} failed -> {OUT.relative_to(ROOT)}")
    for base, detail in sorted(failures):
        print(f"  ! {base}: {detail}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
