"""Claude's side of the browser track editor: the same session, from a shell.

Talks to tools/editor/server.py, so every edit here shows up on the user's
page as it is made, marked as Claude's, and goes on the same undo stack.

Seeing what the user sees:
  status                         the open track, its problems, who is here
  view                           the user's selection, view box and hover
  snapshot OUT.png [--view user|claude] [--around ID,..] [--box x0,y0,x1,y1]
                   [--stage FILE] [--size PX] [--no-labels] [--no-links]
                   [--style outline|dot|solid]
                                 a picture of the board as edited; outline
                                 (the default) or dot keeps the printed
                                 arrows in view, --no-labels --no-links more so
  space ID                       one space: links in and out, problems
  spaces [--box x0,y0,x1,y1] [--lane N] [--sector S]
  problems [--around ID,..]

Talking:
  listen [--after N]             one line per message the user sends Claude,
                                 forever: run it under Monitor
  inbox [--after N]              the messages so far
  say TEXT                       a message on the user's chat panel
  select ID ...                  Claude's selection, ringed on the board
  focus ID ... [--text T]        point the user's view at spaces
  note TEXT (--spaces ID,.. | --at X,Y)    a note pinned on the board
  notes-clear [ID ...]

Editing (positions in image pixels, angles in degrees, 0 = right, clockwise):
  move ID X Y [ROT]    rotate ID DEG    turn ID BY    lane ID N
  add X Y [--like ID]  delete ID ...    link FROM TO (toggles)
  unfix ID ...         grid ID ...      grid-set ID ...
  set ID key=value ...                  corner, sector, lane, rot, pit, box
  ops JSON | -                          a batch of ops (trackdoc.py), one undo step
  undo  redo  save  revert  open KEY  tracks

Detection:
  detect ID [--cells] [--reverse] [--category formula_d|formula_de]
            [--steps corners,arrows,adjacency] [--no-follow]
  upload IMAGE [--category C]     then detect the id it prints
  jobs   job ID   promote KEY [--force]   adjacency

The server's address is http://127.0.0.1:8765 unless FD_EDITOR_URL says.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

URL = os.environ.get("FD_EDITOR_URL", "http://127.0.0.1:8765").rstrip("/")
AUTHOR = "claude"


def call(method, path, body=None, raw=None, timeout=30, ctype="application/json"):
    data = raw if raw is not None else (json.dumps(body).encode("utf-8") if body is not None else None)
    req = urllib.request.Request(URL + path, data=data, method=method)
    if data is not None:
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            payload = r.read()
            if r.headers.get("Content-Type", "").startswith("application/json"):
                return json.loads(payload)
            return payload
    except urllib.error.HTTPError as e:
        try:
            err = json.loads(e.read()).get("error")
        except ValueError:
            err = str(e)
        sys.exit("error: %s" % err)
    except urllib.error.URLError as e:
        sys.exit("error: no editor at %s (%s) -- start it: python tools/editor/server.py" % (URL, e.reason))


def get(path, **q):
    q = {k: v for k, v in q.items() if v is not None}
    return call("GET", path + ("?" + urllib.parse.urlencode(q) if q else ""))


def post(path, body=None):
    body = dict(body or {})
    body.setdefault("author", AUTHOR)
    return call("POST", path, body)


def flag(args, name, default=None):
    if name in args:
        i = args.index(name)
        v = args[i + 1] if i + 1 < len(args) else None
        del args[i:i + 2]
        return v
    return default


def switch(args, name):
    if name in args:
        args.remove(name)
        return True
    return False


def num(v):
    return float(v)


def ident(v):
    return v


def context_line(c):
    parts = []
    if c.get("track"):
        parts.append("track " + str(c["track"]))
    if c.get("selection"):
        parts.append("selected " + ",".join(map(str, c["selection"][:30]))
                     + (" (+%d)" % (len(c["selection"]) - 30) if len(c["selection"]) > 30 else ""))
    if c.get("hover"):
        parts.append("pointing at " + str(c["hover"]))
    if c.get("viewport"):
        v = [int(x) for x in c["viewport"]]
        parts.append("view %d,%d-%d,%d" % tuple(v))
    return "; ".join(parts)


def show_msg(m):
    ctx = context_line(m.get("context") or {})
    text = m["text"].replace("\n", " / ")
    return "[%d] %s: %s%s" % (m["id"], m["from"], text, ("   {" + ctx + "}") if ctx else "")


def ops(batch):
    r = post("/api/op", {"ops": batch})
    for n in r["notes"]:
        print(n)
    s = r["summary"]
    print("-> %d spaces, %d problems%s" % (s["spaces"], s["problems"], ", unsaved" if s["dirty"] else ""))


def cmd_status(args):
    s = get("/api/state", full="0")
    if not s.get("open"):
        print("no track open")
    else:
        m = s["summary"]
        print("%s: %d spaces %s, grid %d, cell %.0f px, %d problems, %s%s"
              % (s["open"], m["spaces"], m["by_lane"], m["grid"], m["cell"], m["problems"],
                 "unsaved edits" if m["dirty"] else "saved", " (spaces moved: adjacency stale)" if s.get("moved")
                 else ""))
        if s.get("busy"):
            print("detection is running on it")
    p = s["presence"]
    pages = [v for v in p["clients"].values() if v.get("who") == "user"]
    print("%d page(s) open; Claude %s" % (len(pages), "listening" if p["claude_listening"] else "not listening"))
    if s.get("last"):
        print("last change by %s: %s" % (s["last"]["author"], "; ".join(s["last"].get("notes") or [])))
    for j in s.get("jobs", []):
        if j["status"] == "running":
            print("job %s running: %s" % (j["id"], j["step"]))
    u = s.get("user") or {}
    if u:
        print("user: " + context_line(u))


def cmd_view(args):
    s = get("/api/state", full="0")
    print(json.dumps(s.get("user") or {}, indent=1))


def cmd_snapshot(args):
    out = args.pop(0) if args and not args[0].startswith("--") else "snapshot.png"
    q = {"view": flag(args, "--view"), "around": flag(args, "--around"), "box": flag(args, "--box"),
         "stage": flag(args, "--stage"), "size": flag(args, "--size"),
         "labels": "0" if switch(args, "--no-labels") else None,
         "links": "0" if switch(args, "--no-links") else None, "style": flag(args, "--style")}
    if not any(q[k] for k in ("view", "around", "box")):
        q["view"] = "user"
    png = get("/api/snapshot", **q)
    with open(out, "wb") as f:
        f.write(png)
    print(os.path.abspath(out))


def cmd_space(args):
    print(json.dumps(get("/api/space/" + urllib.parse.quote(args[0])), indent=1))


def cmd_spaces(args):
    s = get("/api/state")
    box = flag(args, "--box")
    lane = flag(args, "--lane")
    sector = flag(args, "--sector")
    box = [float(v) for v in box.split(",")] if box else None
    for sp in s["track"]["spaces"]:
        x, y = sp["pos"]
        if box and not (box[0] <= x <= box[2] and box[1] <= y <= box[3]):
            continue
        if lane and str(sp.get("lane")) != lane:
            continue
        if sector and str(sp.get("sector")) != sector:
            continue
        print("%-12s lane %s  pos %7.1f,%7.1f  rot %5.1f  -> %s%s%s" % (
            sp["id"], sp.get("lane"), x, y, sp.get("rot", 0), ",".join(map(str, sp.get("next", []))),
            "  fixed" if sp.get("fixed") else "", "  pit" if sp.get("pit") else ""))


def cmd_problems(args):
    s = get("/api/state", full="0")
    around = flag(args, "--around")
    want = set(around.split(",")) if around else None
    for p in s.get("problems", []):
        if want is None or str(p["id"]) in want:
            print("%-12s %s" % (p["id"], p["text"]))
    print("%d problem(s)" % len(s.get("problems", [])))
    for c in s.get("checks", []):
        if want is None or str(c.get("id")) in want:
            print("test: %s -- %s" % (c["test"], c["text"]))
    print("%d track test(s) failing" % len(s.get("checks", [])))


def cmd_listen(args):
    after = flag(args, "--after")
    if after is None:
        after = get("/api/messages")["last"]
    after = int(after)
    print("listening for messages after #%d" % after, flush=True)
    while True:
        try:
            r = call("GET", "/api/messages?" + urllib.parse.urlencode(
                {"after": after, "wait": 25, "from": "user", "listener": "claude"}), timeout=40)
        except SystemExit as e:
            print("editor unreachable, retrying: %s" % e, flush=True)
            time.sleep(5)
            continue
        except Exception:
            time.sleep(2)
            continue
        for m in r["messages"]:
            print(show_msg(m), flush=True)
            after = max(after, m["id"])


def cmd_inbox(args):
    after = int(flag(args, "--after", 0))
    for m in get("/api/messages", after=after)["messages"]:
        print(show_msg(m))


def cmd_say(args):
    post("/api/message", {"from": "claude", "text": " ".join(args)})


def cmd_select(args):
    post("/api/presence", {"client": "claude", "who": "claude", "selection": args})
    print("selected %d" % len(args))


def cmd_focus(args):
    text = flag(args, "--text")
    post("/api/focus", {"ids": args, "text": text})
    post("/api/presence", {"client": "claude", "who": "claude", "selection": args})


def cmd_note(args):
    spaces = flag(args, "--spaces")
    at = flag(args, "--at")
    post("/api/note", {"text": " ".join(args), "spaces": spaces.split(",") if spaces else [],
                       "pos": [float(v) for v in at.split(",")] if at else None})


def cmd_notes_clear(args):
    post("/api/notes/clear", {"ids": [int(a) for a in args] if args else None})


def cmd_move(args):
    op = {"op": "move", "id": args[0], "pos": [num(args[1]), num(args[2])]}
    if len(args) > 3:
        op["rot"] = num(args[3])
    ops([op])


def cmd_rotate(args):
    ops([{"op": "rotate", "id": args[0], "rot": num(args[1])}])


def cmd_turn(args):
    ops([{"op": "turn", "id": args[0], "by": num(args[1])}])


def cmd_lane(args):
    ops([{"op": "lane", "id": args[0], "lane": int(args[1])}])


def cmd_add(args):
    like = flag(args, "--like")
    op = {"op": "add", "pos": [num(args[0]), num(args[1])]}
    if like:
        op["like"] = like
    ops([op])


def cmd_delete(args):
    ops([{"op": "delete", "id": a} for a in args])


def cmd_link(args):
    ops([{"op": "link", "from": args[0], "to": args[1]}])


def cmd_unfix(args):
    ops([{"op": "unfix", "id": a} for a in args])


def cmd_grid(args):
    ops([{"op": "grid", "id": a} for a in args])


def cmd_grid_set(args):
    ops([{"op": "grid_set", "ids": args}])


def cmd_set(args):
    fields = {}
    for kv in args[1:]:
        k, _, v = kv.partition("=")
        try:
            fields[k] = json.loads(v)
        except ValueError:
            fields[k] = v
    ops([{"op": "set", "id": args[0], "fields": fields}])


def cmd_ops(args):
    text = sys.stdin.read() if not args or args[0] == "-" else " ".join(args)
    batch = json.loads(text)
    ops(batch if isinstance(batch, list) else [batch])


def cmd_undo(args):
    print("undone" if post("/api/undo")["ok"] else "nothing to undo")


def cmd_redo(args):
    print("redone" if post("/api/redo")["ok"] else "nothing to redo")


def cmd_save(args):
    r = post("/api/save")
    print("saved", r["path"] + ("; adjacency rerunning" if r.get("adjacency") else ""))
    for line in r.get("gen", []):
        print("  " + line)


def cmd_revert(args):
    post("/api/revert")
    print("reverted to the file")


def cmd_open(args):
    print("open:", post("/api/open", {"key": args[0]})["open"])


def cmd_tracks(args):
    r = get("/api/tracks")
    for t in r["tracks"]:
        print("%-22s %-8s %s%s" % (t["key"], t["kind"], t["name"], "  (edited)" if t.get("edited") else ""))
    print("open:", r.get("open"))


def cmd_detect(args):
    tid = args.pop(0)
    options = {"read": "cells" if switch(args, "--cells") else "rungs", "reverse": switch(args, "--reverse"),
               "category": flag(args, "--category"), "follow": not switch(args, "--no-follow")}
    steps = flag(args, "--steps")
    if steps is not None:
        options["steps"] = [s for s in steps.split(",") if s]
    r = post("/api/detect", {"id": tid, "options": options})
    print("job", r["job"]["id"], "->", r["key"])


def cmd_upload(args):
    path = args.pop(0)
    cat = flag(args, "--category")
    with open(path, "rb") as f:
        data = f.read()
    q = urllib.parse.urlencode({"name": os.path.basename(path), **({"category": cat} if cat else {})})
    r = call("POST", "/api/upload?" + q, raw=data, ctype="application/octet-stream", timeout=120)
    print(r["id"])


def cmd_jobs(args):
    for j in get("/api/state", full="0").get("jobs", []):
        print("%s  %s  %s  %s" % (j["id"], j["key"], j["status"], j["step"] or ""))


def cmd_job(args):
    j = get("/api/job/" + args[0])
    print("%s %s %s" % (j["id"], j["status"], j["step"] or ""))
    print("\n".join(j["lines"][-60:]))


def cmd_promote(args):
    print(post("/api/promote", {"key": args[0], "force": "--force" in args})["path"])


def cmd_adjacency(args):
    print("job", post("/api/adjacency")["job"]["id"])


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    name = "cmd_" + args[0].replace("-", "_")
    fn = globals().get(name)
    if not fn:
        sys.exit("unknown command %s (try --help)" % args[0])
    try:
        fn(args[1:])
    except (IndexError, ValueError) as e:
        sys.exit("error: %s -- see fdedit.py --help" % e)
    return 0


if __name__ == "__main__":
    sys.exit(main())
