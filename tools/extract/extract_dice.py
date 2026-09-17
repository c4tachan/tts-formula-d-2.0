"""Find the faces of the six gear dice and draw a numbered contact sheet of each.

This is how dice_faces.json was made: the script lists every face's direction
in mesh order and crops the texture under it; a person reads the number off
each crop and writes it into dice_faces.json. Rerun it only if the dice models
change. It reads meshes and textures from the local TTS cache, so load the
Big Box mod in TTS once first.

The first gear die is a d4 read at its top vertex, so its entries are vertex
directions, and the value is the number printed next to that vertex.

Run:  python tools/extract/extract_dice.py          (pip install pillow)
Output goes to tools/extract/out/ (not committed).
"""
import json
import math
import os
import pathlib
import re
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "tools" / "extract" / "out"
MODS = pathlib.Path(os.path.expanduser("~")) / "Documents" / "My Games" / "Tabletop Simulator" / "Mods"
SAVE_ID = "2092460061"

NAMES = ["First", "Second", "Third", "Fourth", "Fifth", "Sixth"]
FACE_COUNT = [4, 6, 8, 12, 20, 30]


def mods_dir():
    # Documents is often redirected (OneDrive); honour an override.
    return pathlib.Path(os.environ.get("TTS_MODS", MODS))


def cached(folder, url):
    key = re.sub(r"[^A-Za-z0-9]", "", url.split("ugc/")[-1])
    for f in (mods_dir() / folder).iterdir():
        if key in f.name and f.suffix.lower() in (".obj", ".jpg", ".png"):
            return f
    raise FileNotFoundError(f"{url} is not in the TTS cache under {folder}")


def find_dice(save):
    found = {}

    def walk(objs):
        for o in objs:
            for i, n in enumerate(NAMES):
                if o.get("Nickname") == f"{n} Gear Dice":
                    found.setdefault(i + 1, o)
            walk(o.get("ContainedObjects") or [])

    walk(save["ObjectStates"])
    return found


def load_obj(path):
    V, VT, F = [], [], []
    for line in path.read_text().splitlines():
        p = line.split()
        if not p:
            continue
        if p[0] == "v":
            V.append(tuple(map(float, p[1:4])))
        elif p[0] == "vt":
            VT.append(tuple(map(float, p[1:3])))
        elif p[0] == "f":
            F.append([(int(q.split("/")[0]), int(q.split("/")[1])) for q in p[1:]])
    return V, VT, F


def faces(V, VT, F):
    """Group polygons into flat faces; largest first, then mesh order."""
    centre = [sum(v[i] for v in V) / len(V) for i in range(3)]
    groups = []
    for f in F:
        P = [V[i - 1] for i, _ in f]
        n = [0.0, 0.0, 0.0]  # Newell's method
        for k in range(len(P)):
            a, b = P[k], P[(k + 1) % len(P)]
            n[0] += (a[1] - b[1]) * (a[2] + b[2])
            n[1] += (a[2] - b[2]) * (a[0] + b[0])
            n[2] += (a[0] - b[0]) * (a[1] + b[1])
        length = math.sqrt(sum(x * x for x in n))
        if length < 1e-9:
            continue
        n = [x / length for x in n]
        c = [sum(p[i] for p in P) / len(P) for i in range(3)]
        if sum(n[i] * (c[i] - centre[i]) for i in range(3)) < 0:
            n = [-x for x in n]
        for g in groups:
            if sum(g["n"][i] * n[i] for i in range(3)) > 0.98:
                g["area"] += length / 2
                g["uv"] += [VT[t - 1] for _, t in f]
                break
        else:
            groups.append({"n": n, "area": length / 2, "uv": [VT[t - 1] for _, t in f]})
    groups.sort(key=lambda g: -g["area"])
    return groups


def sheet(tex, groups, path):
    W, H = tex.size
    cols = 6
    rows = (len(groups) + cols - 1) // cols
    img = Image.new("RGB", (cols * 150, rows * 170), "white")
    d = ImageDraw.Draw(img)
    for i, g in enumerate(groups):
        us = [u for u, _ in g["uv"]]
        vs = [1 - v for _, v in g["uv"]]
        box = (int(min(us) * W), int(min(vs) * H), math.ceil(max(us) * W), math.ceil(max(vs) * H))
        x, y = (i % cols) * 150, (i // cols) * 170
        img.paste(tex.crop(box).resize((140, 140)), (x + 5, y + 25))
        d.text((x + 60, y + 5), str(i), fill="red")
    img.save(path)


def main():
    save = json.loads((mods_dir() / "Workshop" / f"{SAVE_ID}.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    for gear, obj in sorted(find_dice(save).items()):
        mesh = obj["CustomMesh"]
        V, VT, F = load_obj(cached("Models", mesh["MeshURL"]))
        tex = Image.open(cached("Images", mesh["DiffuseURL"])).convert("RGB")
        print(f"gear {gear}: {NAMES[gear - 1]} Gear Dice")
        if gear == 1:
            centre = [sum(v[i] for v in V) / len(V) for i in range(3)]
            for i, v in enumerate(V):
                d = [v[k] - centre[k] for k in range(3)]
                n = math.sqrt(sum(x * x for x in d))
                print(f"  vertex {i + 1}: up [{', '.join('%.5f' % (x / n) for x in d)}]")
            tex.save(OUT / "gear1_texture.png")
            continue
        groups = faces(V, VT, F)[:FACE_COUNT[gear - 1]]
        for i, g in enumerate(groups):
            print(f"  face {i}: up [{', '.join('%.5f' % x for x in g['n'])}]")
        sheet(tex, groups, OUT / f"gear{gear}_faces.png")
    print(f"contact sheets in {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
