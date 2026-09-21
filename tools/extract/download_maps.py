"""Download every board image listed in maps.json into tracks/raw/.

Files are named <id>.<ext> (extension taken from the response's content type).
tracks/raw/ is gitignored, so the ~340 MB of images stay out of the repo. Files
that already exist are skipped, so the script can be rerun to fill in gaps.

Run:  python tools/extract/download_maps.py            # everything
      python tools/extract/download_maps.py FDMonaco   # just these ids
      python tools/extract/download_maps.py --category formula_d
"""
import argparse
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = pathlib.Path(__file__).resolve().parents[2]
MAPS = ROOT / "tools" / "extract" / "maps.json"
OUT = ROOT / "tracks" / "raw"

EXT = {"image/jpeg": ".jpg", "image/png": ".png", "image/gif": ".gif", "image/webp": ".webp"}
SNIFF = [(b"\xff\xd8\xff", ".jpg"), (b"\x89PNG", ".png"), (b"GIF8", ".gif"), (b"RIFF", ".webp")]
RETRIES = 3


def existing(map_id):
    return next(iter(OUT.glob(f"{map_id}.*")), None)


def extension(content_type, data):
    ext = EXT.get((content_type or "").split(";")[0].strip().lower())
    if ext:
        return ext
    for magic, e in SNIFF:
        if data.startswith(magic):
            return e
    return None


def fetch(m):
    """Returns (id, status, detail) where status is 'ok', 'skip' or 'fail'."""
    have = existing(m["id"])
    if have:
        return m["id"], "skip", have.name
    last = ""
    for attempt in range(RETRIES):
        try:
            req = urllib.request.Request(m["url"], headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
                ext = extension(r.headers.get("Content-Type"), data)
            if not ext:
                return m["id"], "fail", "response is not an image"
            path = OUT / (m["id"] + ext)
            tmp = path.with_suffix(ext + ".part")
            tmp.write_bytes(data)
            tmp.replace(path)
            return m["id"], "ok", f"{path.name} ({len(data) // 1024} KB)"
        except urllib.error.HTTPError as e:
            last = f"HTTP {e.code}"
            if e.code in (403, 404):        # won't fix itself on retry
                break
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            last = str(e)
        time.sleep(1 + attempt)
    return m["id"], "fail", last


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("ids", nargs="*", help="map ids to fetch (default: all)")
    ap.add_argument("--category", choices=["formula_d", "formula_de", "custom"])
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    maps = json.loads(MAPS.read_text(encoding="utf-8"))
    if args.ids:
        known = {m["id"] for m in maps}
        unknown = [i for i in args.ids if i not in known]
        if unknown:
            sys.exit("unknown map id(s): " + ", ".join(unknown))
        maps = [m for m in maps if m["id"] in args.ids]
    if args.category:
        maps = [m for m in maps if m["category"] == args.category]

    OUT.mkdir(parents=True, exist_ok=True)
    counts = {"ok": 0, "skip": 0, "fail": 0}
    failures = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(fetch, m) for m in maps]
        for n, fut in enumerate(as_completed(futures), 1):
            map_id, status, detail = fut.result()
            counts[status] += 1
            if status == "fail":
                failures.append((map_id, detail))
            if status != "skip":
                print(f"[{n}/{len(maps)}] {status:4} {map_id}: {detail}", flush=True)

    print(f"\n{counts['ok']} downloaded, {counts['skip']} already present, "
          f"{counts['fail']} failed -> {OUT.relative_to(ROOT)}")
    for map_id, detail in sorted(failures):
        print(f"  ! {map_id}: {detail}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
