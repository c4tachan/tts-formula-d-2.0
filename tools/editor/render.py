"""Pictures of a track being edited, for Claude to look at.

The browser draws the board itself; this draws the same things -- spaces as
cars coloured by lane, links, problems, the grid, both selections, notes --
onto a crop of the board image with OpenCV, so `fdedit.py snapshot` can show
Claude what the person at the browser sees.
"""
import math

import cv2
import numpy as np

# BGR. Lanes as the browser colours them: inside orange, middle green,
# outside blue; the pit lane grey.
LANE = {0: (160, 160, 160), 1: (0, 140, 255), 2: (60, 190, 40), 3: (230, 120, 20)}
LINK = (235, 235, 235)
FIXED = (0, 215, 255)
PROBLEM = (40, 40, 230)
USER_SEL = (255, 255, 0)
CLAUDE_SEL = (230, 80, 200)
NOTE = (230, 80, 200)
_cache = {}


def board(path, width, height):
    """The board image at the track's pixel size, cached."""
    key = (str(path), width, height)
    if key not in _cache:
        im = cv2.imread(str(path)) if path else None
        if im is None:
            im = np.full((height, width, 3), 70, np.uint8)
        if im.shape[1] != width or im.shape[0] != height:
            im = cv2.resize(im, (width, height), interpolation=cv2.INTER_CUBIC)
        _cache.clear()
        _cache[key] = im
    return _cache[key]


def _box_around(spaces, ids, pad):
    pts = [s["pos"] for s in spaces if s["id"] in ids or str(s["id"]) in ids]
    if not pts:
        return None
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return [min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad]


def snapshot(doc, image_path, box=None, around=None, user_sel=(), claude_sel=(), notes=(), max_px=1400,
             labels=True, underlay=None, style="outline", links=True):
    """A PNG (bytes) of `box` [x0, y0, x1, y1] in image pixels -- or of the
    spaces `around`, or the whole board -- with the track drawn over it.
    `style` draws the spaces as the page can: outline, dot or solid."""
    track = doc.track
    w, h = track["image"]["width"], track["image"]["height"]
    cell = doc.cell or 40
    spaces = doc.spaces
    if around:
        box = _box_around(spaces, set(map(str, around)) | set(around), 3 * cell)
    if not box:
        box = [0, 0, w, h]
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(w, max(x1, x0 + 10)), min(h, max(y1, y0 + 10))
    base = board(underlay or image_path, w, h)[y0:y1, x0:x1]
    k = min(max_px / max(1, x1 - x0), max_px / max(1, y1 - y0), 4.0)
    im = cv2.resize(base, None, fx=k, fy=k, interpolation=cv2.INTER_CUBIC if k > 1 else cv2.INTER_AREA)
    if style == "solid":
        im = cv2.addWeighted(im, 0.55, np.full_like(im, 255), 0.45, 0)

    def px(p):
        return int(round((p[0] - x0) * k)), int(round((p[1] - y0) * k))

    index = doc.index()
    flagged = {p["id"] for p in doc.problems}
    grid = {g: i + 1 for i, g in enumerate(track.get("start") or [])}
    users = set(map(str, user_sel))
    claudes = set(map(str, claude_sel))
    margin = 2 * cell
    visible = [s for s in spaces if x0 - margin <= s["pos"][0] <= x1 + margin
               and y0 - margin <= s["pos"][1] <= y1 + margin]
    lw = max(1, int(round(k * cell / 30)))
    for s in visible:
        c = np.array(s["pos"], float)
        r = math.radians(s.get("rot", 0))
        f = np.array([math.cos(r), math.sin(r)])
        side = np.array([-f[1], f[0]])
        L, W = 0.36 * cell, 0.17 * cell
        corners = [c + f * L + side * W, c + f * L - side * W, c - f * L - side * W, c - f * L + side * W]
        poly = np.array([px(p) for p in corners], np.int32)
        lane = 0 if s.get("pit") else s.get("lane", 1)
        colour = (200, 200, 200) if s.get("box") else LANE.get(lane, (128, 128, 128))
        if style == "solid":
            cv2.fillPoly(im, [poly], colour)
            nose = np.array([px(c + f * 0.95 * L), px(c + f * 0.45 * L + side * 0.6 * W),
                             px(c + f * 0.45 * L - side * 0.6 * W)], np.int32)
            cv2.fillPoly(im, [nose], (255, 255, 255))
            cv2.polylines(im, [poly], True, (30, 30, 30), 1, cv2.LINE_AA)
        elif style == "dot":
            cv2.line(im, px(c), px(c + f * 0.9 * L), colour, max(1, lw), cv2.LINE_AA)
            cv2.circle(im, px(c), max(2, int(0.09 * cell * k)), colour, -1, cv2.LINE_AA)
        else:
            # An outline and a small nose: what is printed in the cell -- its
            # arrow above all -- stays in view.
            cv2.polylines(im, [poly], True, colour, max(1, lw), cv2.LINE_AA)
            nose = np.array([px(c + f * L), px(c + f * 0.72 * L + side * 0.45 * W),
                             px(c + f * 0.72 * L - side * 0.45 * W)], np.int32)
            cv2.fillPoly(im, [nose], colour)
        p = px(c)
        rad = int(round(0.55 * cell * k))
        if s["id"] in flagged:
            cv2.circle(im, p, rad, PROBLEM, max(2, lw + 1), cv2.LINE_AA)
        if str(s["id"]) in users:
            cv2.circle(im, p, rad + 3 * lw, USER_SEL, max(2, lw + 1), cv2.LINE_AA)
        if str(s["id"]) in claudes:
            cv2.circle(im, p, rad + 6 * lw, CLAUDE_SEL, max(2, lw + 1), cv2.LINE_AA)
        if s["id"] in grid:
            cv2.putText(im, "G%d" % grid[s["id"]], (p[0] - rad, p[1] - rad), cv2.FONT_HERSHEY_SIMPLEX,
                        0.5, (0, 0, 0), 2, cv2.LINE_AA)
    # Links over the cars, from just ahead of a car's middle to just short
    # of the next one's, so the arrowheads stay clear of the cars.
    for s in (visible if links else []):
        for n in s.get("next", []):
            o = index.get(n)
            if not o:
                continue
            a, b = np.array(s["pos"], float), np.array(o["pos"], float)
            d = np.linalg.norm(b - a) or 1.0
            u = (b - a) / d
            p0, p1 = px(a + u * min(0.2 * cell, 0.3 * d)), px(b - u * min(0.38 * cell, 0.45 * d))
            col = FIXED if s.get("fixed") else LINK
            tip = min(0.5, 12 / max(1.0, d * k))
            cv2.arrowedLine(im, p0, p1, (30, 30, 30), lw + 2, cv2.LINE_AA, tipLength=tip)
            cv2.arrowedLine(im, p0, p1, col, lw, cv2.LINE_AA, tipLength=tip)
    if labels and k * cell >= 28:
        scale = min(0.6, max(0.3, k * cell / 140))
        for s in visible:
            p = px(s["pos"])
            text = str(s["id"])
            (tw, th), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, scale, 1)
            org = (p[0] - tw // 2, p[1] + th // 2)
            cv2.putText(im, text, org, cv2.FONT_HERSHEY_SIMPLEX, scale, (255, 255, 255), 3, cv2.LINE_AA)
            cv2.putText(im, text, org, cv2.FONT_HERSHEY_SIMPLEX, scale, (20, 20, 20), 1, cv2.LINE_AA)
    for n in notes:
        pts = [index[i]["pos"] for i in n.get("spaces", []) if i in index]
        if n.get("pos"):
            pts.append(n["pos"])
        for q in pts:
            cv2.circle(im, px(q), int(0.8 * cell * k), NOTE, 2, cv2.LINE_AA)
        if pts and n.get("text"):
            cv2.putText(im, n["text"][:40], px(pts[0]), cv2.FONT_HERSHEY_SIMPLEX, 0.5, NOTE, 2, cv2.LINE_AA)
    for key, col in (("dice", (40, 40, 40)), ):
        if track.get(key):
            p = px(track[key])
            cv2.rectangle(im, (p[0] - 8, p[1] - 8), (p[0] + 8, p[1] + 8), col, 2)
    # A scale bar of one cell, and where the crop is on the board.
    cv2.putText(im, "x %d-%d  y %d-%d  (1 cell = %d px)" % (x0, x1, y0, y1, cell), (8, im.shape[0] - 10),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 2, cv2.LINE_AA)
    ok, png = cv2.imencode(".png", im)
    return png.tobytes()
