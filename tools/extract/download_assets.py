"""Store every non-track asset the mod uses in assets/raw/, with a manifest.

Track board images are handled separately by download_maps.py, which reads
their URLs from maps.json -- this script skips anything that appears there.

The mod's own objects -- meshes, textures, colliders, the table, the sky,
custom decks, the UI images -- aren't listed anywhere in this repo; TTS only
knows them as fields buried in a save file. So this reads them out of the
most recently saved copy of the mod in the local TTS Saves folder
(SaveName/GameMode "Formula D Big Box Mod").

UI images are the CustomUIAssets that something in src/ names (`image="..."`,
or a Lua string). The save registers ~300 more, thumbnails for boards the mod
no longer offers; those are left out. A name the save doesn't register is
looked up in the 2020 workshop copy of the mod, which registered some on the
board object itself.

Each file is copied from the TTS cache when it is there, and downloaded
otherwise. assets/raw/manifest.json records which URL each file came from and
what uses it, so the mod can be rebuilt from the repo if the uploads go.

Run:  python tools/extract/download_assets.py
"""
import json
import pathlib
import re
import shutil
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

from tts_paths import MODS, TTS_DIR

ROOT = pathlib.Path(__file__).resolve().parents[2]
MAPS = ROOT / "tools" / "extract" / "maps.json"
SRC = ROOT / "src"
WORKSHOP = MODS / "Workshop" / "2092460061.json"
OUT = ROOT / "assets" / "raw"
MANIFEST = OUT / "manifest.json"

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
CACHE_DIRS = ["Images", "Models", "PDF", "Assetbundles", "Audio"]
REPO_COPY = "https://raw.githubusercontent.com/"
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


def ui_assets(data):
    """name -> url for every CustomUIAssets entry, global or on an object."""
    found = {}

    def walk(node):
        if isinstance(node, dict):
            for a in node.get("CustomUIAssets") or []:
                if isinstance(a, dict) and a.get("Name") and a.get("URL"):
                    found.setdefault(a["Name"], a["URL"])
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(data)
    return found


def names_in_src(names):
    """The asset names that some file under src/ mentions as a quoted string."""
    text = "".join(p.read_text(encoding="utf-8", errors="replace")
                   for p in SRC.rglob("*") if p.is_file())
    quoted = set(re.findall(r'"([^"\n]+)"', text)) | set(re.findall(r"'([^'\n]+)'", text))
    return quoted & set(names)


def referenced_images():
    """Every `image="..."` name in src/ XML, which must resolve to a UI asset."""
    names = set()
    for p in SRC.rglob("*.xml"):
        names |= set(re.findall(r'\bimage\s*=\s*"([^"]+)"', p.read_text(encoding="utf-8")))
    return {n for n in names if not n.startswith("http")}


def akamai(url):
    # cloud-3.steamusercontent.com answers 403 now; same file, other host.
    return re.sub(r"^https?://cloud-3\.steamusercontent\.com/ugc/",
                  "https://steamusercontent-a.akamaihd.net/ugc/", url)


def collect(data):
    """(label, uses, url) triples, deduped by url, in first-seen order; uses
    lists everything that refers to the url. Exits if src/ names a UI image
    that no save registers."""
    track_urls = {akamai(m["url"]) for m in json.loads(MAPS.read_text(encoding="utf-8"))}

    seen = {}  # url -> uses
    out = []

    def add(url, label, use):
        url = akamai(url)
        # The repo's own copies (tools/pin_assets.py) are stored already.
        if url in track_urls or not url.startswith("http") or url.startswith(REPO_COPY):
            return
        if url in seen:
            if use not in seen[url]:
                seen[url].append(use)
            return
        seen[url] = [use]
        out.append((label, seen[url], url))

    def walk(node, context):
        if isinstance(node, dict):
            if "GUID" in node:
                context = node.get("Nickname") or node.get("Name") or context
            for key in ASSET_KEYS:
                v = node.get(key)
                if isinstance(v, str) and v:
                    add(v, f"{context}_{key}", f"{context}.{key}")
            for k, v in node.items():
                if k not in ASSET_KEYS and k != "CustomUIAssets":
                    walk(v, context)
        elif isinstance(node, list):
            for item in node:
                walk(item, context)

    walk(data.get("ObjectStates", []), "object")
    for key in ("TableURL", "SkyURL"):
        v = data.get(key)
        if isinstance(v, str) and v:
            add(v, key.replace("URL", ""), key)

    ui = ui_assets(data)
    if WORKSHOP.exists():
        for name, url in ui_assets(json.loads(WORKSHOP.read_text(encoding="utf-8"))).items():
            ui.setdefault(name, url)
    unknown = sorted(referenced_images() - set(ui))
    if unknown:
        sys.exit("src/ names UI images that no save registers: " + ", ".join(unknown))
    for name in sorted(names_in_src(ui)):
        add(ui[name], f"ui_{name}", f"ui:{name}")

    return out


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
    return next((p for p in OUT.glob(f"{base}.*") if p.suffix != ".part"), None) if OUT.exists() else None


def cached(url):
    """The TTS cache's copy of url, if it has one. Its file names are the URL
    with punctuation stripped, under whichever host it was fetched from."""
    key = re.sub(r"[^A-Za-z0-9]", "", url.split("ugc/")[-1])
    for sub in CACHE_DIRS:
        d = MODS / sub
        if d.is_dir():
            for f in d.glob(f"*{key}.*"):
                return f
    return None


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


def save(base, data, ext):
    path = OUT / (base + ext)
    tmp = path.with_suffix(ext + ".part")
    tmp.write_bytes(data)
    tmp.replace(path)
    return path


def fetch(url, base):
    """Returns (base, status, detail, path) where status is 'skip', 'cache',
    'ok' or 'fail'."""
    have = existing(base)
    if have:
        return base, "skip", have.name, have
    hit = cached(url)
    if hit:
        data = hit.read_bytes()
        ext = next((e for magic, e in SNIFF if data.startswith(magic)), hit.suffix.lower())
        path = save(base, data, ext)
        return base, "cache", f"{path.name} ({len(data) // 1024} KB)", path
    last = ""
    for attempt in range(RETRIES):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
                ext = extension(r.headers.get("Content-Type"), data)
            path = save(base, data, ext)
            return base, "ok", f"{path.name} ({len(data) // 1024} KB)", path
        except urllib.error.HTTPError as e:
            last = f"HTTP {e.code}"
            if e.code in (403, 404):
                break
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            last = str(e)
        time.sleep(1 + attempt)
    return base, "fail", last, None


def main():
    save_path, data = find_save()
    print(f"reading {save_path}")
    triples = collect(data)
    print(f"{len(triples)} unique non-track assets in use")

    OUT.mkdir(parents=True, exist_ok=True)
    used = set()
    jobs = [(uses, url, unique_base(label, used)) for label, uses, url in triples]

    counts = {"ok": 0, "cache": 0, "skip": 0, "fail": 0}
    failures = []
    files = {}
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(fetch, url, base): base for _, url, base in jobs}
        for n, fut in enumerate(as_completed(futures), 1):
            base, status, detail, path = fut.result()
            counts[status] += 1
            files[base] = path
            if status == "fail":
                failures.append((base, detail))
            if status != "skip":
                print(f"[{n}/{len(jobs)}] {status:5} {base}: {detail}", flush=True)

    # Merged into what is there: once a save points at the repo's copies, the
    # Steam URLs are only on record here, and tools/pin_assets.py needs them.
    manifest = {m["url"]: m for m in json.loads(MANIFEST.read_text(encoding="utf-8"))} \
        if MANIFEST.exists() else {}
    for uses, url, base in jobs:
        manifest[url] = {"file": files[base].name if files[base] else None, "url": url, "use": uses}
    MANIFEST.write_text(json.dumps(sorted(manifest.values(), key=lambda m: m["use"][0]), indent=1) + "\n",
                        encoding="utf-8", newline="\n")

    print(f"\n{counts['ok']} downloaded, {counts['cache']} copied from the TTS cache, "
          f"{counts['skip']} already present, {counts['fail']} failed -> {OUT.relative_to(ROOT)}")
    for base, detail in sorted(failures):
        print(f"  ! {base}: {detail}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
