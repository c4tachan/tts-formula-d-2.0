"""The track editor in a browser: a local server the page and Claude share.

One editing session, held here, that every browser tab and Claude's command
line (tools/editor/fdedit.py) work on together: an edit from any of them is
applied here (trackdoc.py), and every page sees it at once over an event
stream. The page also tells the server what its user has selected and is
looking at, and messages typed into its chat panel wait here for Claude to
pick up, so Claude can see what the user means and answer on the board.

It also runs the detector (tools/extract/find_*.py) on a board image -- a
mapped board, or any image dropped onto the page -- in a scratch folder
under tools/extract/out/web/, streaming each step's picture to the page as
it is drawn. A detection draft can be edited like any track, and promoted
to tracks/<id>.json when it is good enough to start from.

Run:  python tools/editor/server.py               then open http://127.0.0.1:8765
      python tools/editor/server.py FDMonaco      with Monaco open
      python tools/editor/server.py --port 9000 --no-browser
"""
import datetime
import json
import mimetypes
import os
import pathlib
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
import traceback
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "tools" / "extract"))

import checks  # noqa: E402
import render  # noqa: E402
import renumber  # noqa: E402
from trackdoc import OpError, TrackDoc  # noqa: E402

TRACKS = ROOT / "tracks"
EXTRACT = ROOT / "tools" / "extract"
SANDBOX = EXTRACT / "out" / "web"
SESSION = SANDBOX / "_session"
STATIC = HERE / "static"
MAPS = EXTRACT / "maps.json"
PORT = 8765
# How long Claude counts as listening after its last poll for messages.
LISTEN_GRACE = 40
UPLOAD_LIMIT = 60 * 1024 * 1024
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def now():
    return time.time()


def stamp():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M")


def slug(text):
    s = re.sub(r"[^A-Za-z0-9]+", "", pathlib.Path(text).stem.title())
    return ("Up" + s)[:40] or "UpBoard"


def rel(path):
    """A path as the repo names it, where it is in the repo."""
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def maps():
    try:
        return json.loads(MAPS.read_text(encoding="utf-8"))
    except OSError:
        return []


def raw_image(map_id):
    """A mapped board's image: tracks/raw/ first, then the TTS cache."""
    found = sorted((TRACKS / "raw").glob(f"{map_id}.*"))
    found = [f for f in found if f.suffix.lower() in IMAGE_EXT]
    if found:
        return found[0]
    hit = next((m for m in maps() if m["id"] == map_id), None)
    if hit and hit.get("url"):
        try:
            from tts_paths import MODS
            key = re.sub(r"[^A-Za-z0-9]", "", hit["url"].split("ugc/")[-1])
            images = MODS / "Images"
            if images.is_dir():
                for f in images.iterdir():
                    if key in f.name:
                        return f
        except Exception:
            pass
    return None


class Hub:
    """Every page's event stream."""

    def __init__(self):
        self.lock = threading.Lock()
        self.queues = []

    def add(self):
        q = queue.Queue(maxsize=500)
        with self.lock:
            self.queues.append(q)
        return q

    def remove(self, q):
        with self.lock:
            if q in self.queues:
                self.queues.remove(q)

    def send(self, event):
        data = json.dumps(event, separators=(",", ":"))
        with self.lock:
            for q in list(self.queues):
                try:
                    q.put_nowait(data)
                except queue.Full:
                    self.queues.remove(q)


class Job:
    def __init__(self, key, kind, steps, on_step=None, on_done=None):
        self.id = "%s-%d" % (kind, int(now() * 1000))
        self.key, self.kind, self.steps = key, kind, steps
        self.on_step, self.on_done = on_step, on_done
        self.status = "running"
        self.lines = []
        self.step = None
        self.started = now()
        self.proc = None

    def info(self):
        return {"id": self.id, "key": self.key, "kind": self.kind, "status": self.status,
                "step": self.step, "lines": self.lines[-400:], "started": self.started}


class Workspace:
    """The one editing session everyone shares."""

    def __init__(self, hub):
        self.hub = hub
        self.lock = threading.RLock()
        self.docs = {}          # key -> TrackDoc
        self.open = None        # key of the track everyone is on
        self.rev = 0
        self.presence = {}      # client -> {who, selection, viewport, hover, key, t}
        self.messages = []
        self.msg_cond = threading.Condition(self.lock)
        self.notes = []
        self.next_note = 1
        self.jobs = {}
        self.claude_polls = 0   # Claude's long polls in flight
        self.claude_seen = 0.0
        self.was_listening = False
        self.last = None        # the last change: author and what it did

    # Tracks ----------------------------------------------------------------

    def parse(self, key):
        if key.startswith("draft:"):
            return "draft", key[6:]
        return "real", key

    def track_path(self, key):
        kind, tid = self.parse(key)
        if kind == "draft":
            return SANDBOX / tid / f"{tid}.json"
        return TRACKS / f"{tid}.json"

    def draft_meta(self, tid):
        p = SANDBOX / tid / "meta.json"
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {"id": tid, "source": "map"}

    def image_path(self, key):
        kind, tid = self.parse(key)
        if kind == "draft":
            meta = self.draft_meta(tid)
            if meta.get("image"):
                return SANDBOX / tid / meta["image"]
        return raw_image(tid)

    def stage_dir(self, key):
        kind, tid = self.parse(key)
        return (SANDBOX / tid) if kind == "draft" else (EXTRACT / "out")

    def stages(self, key):
        kind, tid = self.parse(key)
        d = self.stage_dir(key)
        out = []
        if d.is_dir():
            for f in sorted(d.glob(f"{tid}_*.png")):
                out.append({"name": f.stem[len(tid) + 1:], "file": f.name, "mtime": f.stat().st_mtime,
                            "url": "/api/stage/%s/%s?t=%d" % (urllib.parse.quote(key), f.name,
                                                             int(f.stat().st_mtime * 1000))})
        return out

    def listing(self):
        tracks = []
        for f in sorted(TRACKS.glob("*.json")):
            if f.stem.count("."):
                continue
            try:
                t = json.loads(f.read_text(encoding="utf-8"))
            except ValueError:
                continue
            tracks.append({"key": t.get("id", f.stem), "id": t.get("id", f.stem), "name": t.get("name", f.stem),
                           "kind": "real", "edited": bool(t.get("edited")), "spaces": len(t.get("spaces", []))})
        if SANDBOX.is_dir():
            for d in sorted(SANDBOX.iterdir()):
                if d.is_dir() and d.name != "_session" and (d / f"{d.name}.json").exists():
                    meta = self.draft_meta(d.name)
                    tracks.append({"key": "draft:" + d.name, "id": d.name,
                                   "name": meta.get("name") or d.name, "kind": "draft",
                                   "source": meta.get("source", "map")})
        boards = [{"id": m["id"], "name": m["name"], "category": m.get("category"),
                   "image": raw_image(m["id"]) is not None} for m in maps()]
        unsaved = [p.stem.replace("__", ":") for p in SESSION.glob("*.json")] if SESSION.is_dir() else []
        return {"tracks": tracks, "boards": boards, "open": self.open, "unsaved": unsaved}

    def session_file(self, key):
        return SESSION / (key.replace(":", "__") + ".json")

    def load(self, key):
        """The working copy of `key`: unsaved edits from an earlier run of
        the server if there are any, else the file."""
        if key in self.docs:
            return self.docs[key]
        path = self.track_path(key)
        sess = self.session_file(key)
        restored = False
        if sess.exists():
            data = json.loads(sess.read_text(encoding="utf-8"))
            track = data["track"]
            restored = data.get("saved")
        elif path.exists():
            track = json.loads(path.read_text(encoding="utf-8"))
        else:
            raise OpError("no track %s" % key)
        doc = TrackDoc(track)
        if restored:
            doc.dirty = True
            doc.moved = data.get("moved", True)
            self.system("Restored unsaved edits to %s from %s." % (key, restored))
        elif doc.relinked:
            self.system("Opening %s relinked %d space(s) whose links the file had otherwise -- the in-game "
                        "editor does the same; saving keeps the new links." % (key, doc.relinked))
        self.docs[key] = doc
        return doc

    def keep(self, key):
        """Write the working copy aside, so a restart loses nothing."""
        doc = self.docs.get(key)
        if not doc:
            return
        SESSION.mkdir(parents=True, exist_ok=True)
        tmp = self.session_file(key).with_suffix(".tmp")
        tmp.write_text(json.dumps({"key": key, "saved": stamp(), "moved": doc.moved, "track": doc.track},
                                  separators=(",", ":")), encoding="utf-8")
        os.replace(tmp, self.session_file(key))

    def forget(self, key):
        try:
            self.session_file(key).unlink()
        except FileNotFoundError:
            pass

    def open_track(self, key, author="user"):
        with self.lock:
            self.load(key)
            self.open = key
            self.rev += 1
            self.last = {"author": author, "notes": ["opened %s" % key]}
            self.notes = []
        self.push_state()
        self.hub.send({"type": "tracks", **self.listing()})

    def reload(self, key):
        """Read `key` afresh from its file: a detection step rewrote it."""
        with self.lock:
            self.docs.pop(key, None)
            self.forget(key)
            if self.open == key:
                self.load(key)
                self.rev += 1
        if self.open == key:
            self.push_state()

    def doc(self, key=None):
        key = key or self.open
        if not key:
            raise OpError("no track is open")
        return key, self.load(key)

    def busy(self, key):
        return any(j.key == key and j.status == "running" and j.kind == "detect" for j in self.jobs.values())

    # State -----------------------------------------------------------------

    def state(self, full=True):
        with self.lock:
            out = {"type": "state", "open": self.open, "rev": self.rev, "last": self.last,
                   "presence": self.presence_info(), "notes": self.notes}
            if self.open and self.open in self.docs:
                doc = self.docs[self.open]
                out["summary"] = doc.summary()
                out["problems"] = doc.problems
                out["checks"] = self.checks(self.open)
                out["moved"] = doc.moved
                out["busy"] = self.busy(self.open)
                if full:
                    out["track"] = doc.track
                    out["image"] = "/api/image/" + urllib.parse.quote(self.open)
                    out["stages"] = self.stages(self.open)
            return out

    def checks(self, key):
        """tests/test_tracks.lua on the working copy, kept until it changes."""
        doc = self.docs[key]
        stamp_ = (key, self.rev, id(doc))
        if getattr(doc, "_checked", None) != stamp_:
            kind, tid = self.parse(key)
            adjacency = self.track_path(key).with_name(f"{tid}.adjacency.json")
            try:
                found = checks.run(doc.for_file(""), adjacency)
            except Exception as e:
                found = [{"test": "running the track tests", "text": "%s: %s" % (type(e).__name__, e)}]
            ids = {str(s["id"]) for s in doc.spaces}
            for c in found:
                c["id"] = checks.failing_space(c["text"], ids)
            if doc.moved:
                found.append({"test": "adjacency", "id": None,
                              "text": "spaces have moved since adjacency was found: saving reruns it"})
            doc.checks, doc._checked = found, stamp_
        return doc.checks

    def push_state(self):
        self.hub.send(self.state())

    def presence_info(self):
        listening = self.claude_polls > 0 or now() - self.claude_seen < LISTEN_GRACE
        return {"clients": self.presence, "claude_listening": listening}

    def set_presence(self, client, data):
        with self.lock:
            p = self.presence.setdefault(client, {})
            for k in ("who", "selection", "viewport", "hover", "key", "name"):
                if k in data:
                    p[k] = data[k]
            p["t"] = now()
            # Pages that have gone quiet drop out.
            for c in [c for c, v in self.presence.items() if now() - v.get("t", 0) > 120 and c != client]:
                del self.presence[c]
        self.hub.send({"type": "presence", **self.presence_info()})

    def user_view(self):
        """The most recently active page's view and selection."""
        pages = [v for v in self.presence.values() if v.get("who") == "user"]
        return max(pages, key=lambda v: v.get("t", 0)) if pages else {}

    def claude_view(self):
        return self.presence.get("claude", {})

    # Edits -----------------------------------------------------------------

    def apply(self, ops, author, key=None):
        with self.lock:
            key, doc = self.doc(key)
            if self.busy(key):
                raise OpError("detection is still running on %s" % key)
            notes = doc.apply(ops)
            self.rev += 1
            self.last = {"author": author, "notes": notes, "ids": touched(ops)}
            self.keep(key)
        self.push_state()
        return notes

    def undo(self, author, redo=False):
        with self.lock:
            key, doc = self.doc()
            ok = doc.redo() if redo else doc.undo()
            if ok:
                self.rev += 1
                self.last = {"author": author, "notes": ["redo" if redo else "undo"]}
                self.keep(key)
        if ok:
            self.push_state()
        return ok

    def save(self, author):
        with self.lock:
            key, doc = self.doc()
            kind, tid = self.parse(key)
            path = self.track_path(key)
            track = doc.for_file("web editor (%s)" % stamp())
            # Codes put right (tools/extract/renumber.py): a space added here
            # is named after its neighbour, often in another lane, and one
            # moved to another lane keeps its old letter.
            renamed, unnumbered = {}, None
            try:
                renamed = renumber.codes(track)
            except renumber.RenumberError as e:
                unnumbered = str(e)
            if renamed:
                renumber.rename(track, renamed)
                renumber.rename_files(renamed, tid, path.parent)
                # The working copy takes the new codes; its undo steps name
                # the old ones, and the files beside it no longer do.
                renumber.rename(doc.track, renamed)
                doc.undo_stack.clear()
                doc.redo_stack.clear()
                doc._recheck(relink=False)
            path.write_text(json.dumps(track, indent=1), encoding="utf-8")
            moved = doc.moved
            doc.dirty = False
            doc.moved = False
            self.forget(key)
            self.rev += 1
            self.last = {"author": author, "notes": ["saved %s" % rel(path)]}
        out = {"path": rel(path), "adjacency": False, "renamed": renamed, "unnumbered": unnumbered}
        if kind == "real":
            gen = subprocess.run([sys.executable, str(EXTRACT / "gen_tracks.py")], capture_output=True,
                                 text=True, cwd=ROOT)
            out["gen"] = (gen.stdout + gen.stderr).strip().splitlines()[-3:]
            if moved:
                # The spaces moved: which touch which is out of date.
                self.adjacency(key)
                out["adjacency"] = True
        if renamed:
            sample = ", ".join("%s -> %s" % kv for kv in list(renamed.items())[:4])
            self.system("Renumbered %d space(s) whose codes were out of step with their lane or place: %s%s. "
                        "Undo starts afresh from here." % (len(renamed), sample, " ..." if len(renamed) > 4 else ""))
        if unnumbered:
            self.system("Could not renumber the spaces, so some codes may not match their lanes: %s." % unnumbered)
        failing = [c for c in self.checks(key) if c["test"] != "adjacency"]
        out["failing"] = failing
        self.system("%s saved %s%s.%s" % (
            "Claude" if author == "claude" else "You", out["path"],
            "; rerunning find_adjacency.py" if out["adjacency"] else "",
            (" It fails %d of the track tests -- see Problems; the mod will still load it." % len(failing))
            if failing else " It passes the track tests."))
        self.push_state()
        self.hub.send({"type": "tracks", **self.listing()})
        return out

    def revert(self, author):
        with self.lock:
            key, _ = self.doc()
            self.docs.pop(key, None)
            self.forget(key)
            self.load(key)
            self.rev += 1
            self.last = {"author": author, "notes": ["reverted %s to its file" % key]}
        self.push_state()

    # Messages and notes ----------------------------------------------------

    def post(self, sender, text, context=None, kind="chat"):
        with self.lock:
            msg = {"id": len(self.messages) + 1, "from": sender, "text": text, "t": now(), "kind": kind,
                   "context": context or {}}
            self.messages.append(msg)
            self.msg_cond.notify_all()
        self.hub.send({"type": "message", "message": msg})
        return msg

    def system(self, text):
        return self.post("system", text, kind="system")

    def wait_messages(self, after, sender, timeout, listener=None):
        deadline = now() + timeout
        with self.lock:
            if listener == "claude":
                self.claude_polls += 1
                self.claude_seen = now()
                self.listening_changed()
            try:
                while True:
                    found = [m for m in self.messages if m["id"] > after and (not sender or m["from"] == sender)]
                    left = deadline - now()
                    if found or left <= 0:
                        return found
                    self.msg_cond.wait(min(left, 5))
            finally:
                if listener == "claude":
                    self.claude_polls -= 1
                    self.claude_seen = now()

    def listening_changed(self):
        listening = self.presence_info()["claude_listening"]
        if listening != self.was_listening:
            self.was_listening = listening
            self.hub.send({"type": "presence", **self.presence_info()})

    def add_note(self, author, text, spaces=None, pos=None):
        with self.lock:
            note = {"id": self.next_note, "author": author, "text": text, "spaces": spaces or [], "pos": pos,
                    "t": now()}
            self.next_note += 1
            self.notes.append(note)
        self.hub.send({"type": "notes", "notes": self.notes})
        return note

    def drop_notes(self, ids=None):
        with self.lock:
            self.notes = [n for n in self.notes if ids is not None and n["id"] not in ids]
        self.hub.send({"type": "notes", "notes": self.notes})

    # Jobs ------------------------------------------------------------------

    def run_job(self, job, env=None):
        self.jobs[job.id] = job
        self.hub.send({"type": "job", "job": job.info()})
        threading.Thread(target=self._job, args=(job, env), daemon=True).start()
        return job

    def _job(self, job, env):
        watch = self.stage_dir(job.key) if job.kind == "detect" else None
        stop = threading.Event()
        if watch:
            threading.Thread(target=self._watch_stages, args=(job, watch, stop), daemon=True).start()
        try:
            for label, argv in job.steps:
                job.step = label
                self._line(job, "== " + label)
                job.proc = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                            stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                                            errors="replace", bufsize=1)
                for line in job.proc.stdout:
                    self._line(job, line.rstrip())
                code = job.proc.wait()
                if code != 0:
                    job.status = "failed"
                    self._line(job, "%s stopped (exit %d)" % (label, code))
                    break
                if job.on_step:
                    job.on_step(job, label)
            else:
                job.status = "done"
        except Exception as e:
            job.status = "failed"
            self._line(job, "error: %s" % e)
        finally:
            stop.set()
            if watch:
                self._scan_stages(job, watch, {})
            job.step = None
            self.hub.send({"type": "job", "job": job.info()})
            if job.on_done:
                job.on_done(job)

    def _line(self, job, line):
        job.lines.append(line)
        self.hub.send({"type": "job-line", "job": job.id, "key": job.key, "line": line, "step": job.step})

    def _scan_stages(self, job, folder, seen):
        tid = self.parse(job.key)[1]
        for f in folder.glob(f"{tid}_*.png"):
            try:
                m = f.stat().st_mtime
            except OSError:
                continue
            if seen.get(f.name) != m and m >= job.started - 1:
                seen[f.name] = m
                self.hub.send({"type": "stage", "key": job.key, "name": f.stem[len(tid) + 1:],
                               "file": f.name, "url": "/api/stage/%s/%s?t=%d"
                               % (urllib.parse.quote(job.key), f.name, int(m * 1000))})

    def _watch_stages(self, job, folder, stop):
        seen = {}
        while not stop.wait(0.4):
            self._scan_stages(job, folder, seen)

    def detect(self, tid, options, author):
        """Run the detector on board `tid` in its scratch folder."""
        folder = SANDBOX / tid
        folder.mkdir(parents=True, exist_ok=True)
        meta = self.draft_meta(tid)
        known = any(m["id"] == tid for m in maps())
        if not known and not meta.get("image"):
            raise OpError("no board %s: upload an image for it first" % tid)
        key = "draft:" + tid
        if self.busy(key):
            raise OpError("detection is already running on %s" % tid)
        # A fresh run: the old draft and its pictures go.
        for f in folder.iterdir():
            if f.name != "meta.json" and f.name != meta.get("image"):
                if f.is_dir():
                    shutil.rmtree(f, ignore_errors=True)
                else:
                    f.unlink()
        with self.lock:
            self.docs.pop(key, None)
            self.forget(key)
        meta.update({"id": tid, "options": options, "run": stamp()})
        meta.setdefault("source", "map" if known else "upload")
        (folder / "meta.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")

        env = dict(os.environ, FD_TRACKS_DIR=str(folder), FD_OUT_DIR=str(folder), PYTHONIOENCODING="utf-8")
        if meta.get("image"):
            env["FD_BOARD_IMAGE"] = str(folder / meta["image"])
            env["FD_BOARD_CATEGORY"] = options.get("category") or meta.get("category") or "formula_d"
        py = [sys.executable, "-u"]
        grid = py + [str(EXTRACT / "find_grid.py"), tid]
        if options.get("read") == "cells":
            grid.append("--cells")
        if options.get("reverse"):
            grid.append("--reverse")
        steps = [("find_grid", grid)]
        want = options.get("steps") or ["corners", "arrows", "adjacency"]
        if "corners" in want:
            steps.append(("find_corners", py + [str(EXTRACT / "find_corners.py"), tid]))
        if "arrows" in want:
            steps.append(("find_arrows", py + [str(EXTRACT / "find_arrows.py"), tid, "--write"]))
        if "adjacency" in want:
            steps.append(("find_adjacency", py + [str(EXTRACT / "find_adjacency.py"), tid]))
        follow = options.get("follow", True)

        def on_step(job, label):
            if label == "find_adjacency":
                return
            if label == "find_grid":
                self.hub.send({"type": "tracks", **self.listing()})
                if follow:
                    self.open_track(key, author)
                    return
            self.reload(key)

        def on_done(job):
            self.system("Detection on %s %s." % (tid, "finished" if job.status == "done" else "failed"))
            self.hub.send({"type": "tracks", **self.listing()})
            if self.open == key:
                self.push_state()

        job = Job(key, "detect", steps, on_step, on_done)
        return self.run_job(job, env)

    def adjacency(self, key):
        kind, tid = self.parse(key)
        py = [sys.executable, "-u"]
        steps = [("find_adjacency", py + [str(EXTRACT / "find_adjacency.py"), tid]),
                 ("gen_tracks", py + [str(EXTRACT / "gen_tracks.py")])]
        env = dict(os.environ, PYTHONIOENCODING="utf-8")
        for k in ("FD_TRACKS_DIR", "FD_OUT_DIR", "FD_BOARD_IMAGE"):
            env.pop(k, None)

        def on_done(job):
            # The track tests read the adjacency file: what they said before
            # it was rewritten is out of date.
            with self.lock:
                doc = self.docs.get(key)
                if doc:
                    doc._checked = None
                self.rev += 1
            if self.open == key:
                self.push_state()

        return self.run_job(Job(key, "adjacency", steps, on_done=on_done), env)

    def upload(self, name, data, category):
        tid = slug(name)
        ext = pathlib.Path(name).suffix.lower()
        if ext not in IMAGE_EXT:
            raise OpError("not an image I can read: %s" % name)
        folder = SANDBOX / tid
        folder.mkdir(parents=True, exist_ok=True)
        image = "board" + ext
        (folder / image).write_bytes(data)
        meta = {"id": tid, "name": pathlib.Path(name).stem, "source": "upload", "image": image,
                "category": category or "formula_d"}
        (folder / "meta.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
        return tid

    def promote(self, key, force, author):
        kind, tid = self.parse(key)
        if kind != "draft":
            raise OpError("%s is not a detection draft" % key)
        if not any(m["id"] == tid for m in maps()):
            raise OpError("%s is not in tools/extract/maps.json: add it there first" % tid)
        target = TRACKS / f"{tid}.json"
        if target.exists() and json.loads(target.read_text(encoding="utf-8")).get("edited") and not force:
            raise OpError("tracks/%s.json has been edited by hand; promoting would replace it" % tid)
        with self.lock:
            doc = self.load(key)
            track = doc.for_file("web editor (%s), from a detection run" % stamp())
            # A draft straight from the detector can still be rerun over; one
            # that has been edited is protected like any hand-edited track.
            draft = json.loads(self.track_path(key).read_text(encoding="utf-8"))
            track["edited"] = bool(doc.dirty or draft.get("edited"))
            if not track["edited"]:
                track.pop("edited_from", None)
        target.write_text(json.dumps(track, indent=1), encoding="utf-8")
        adj = SANDBOX / tid / f"{tid}.adjacency.json"
        if adj.exists():
            shutil.copy(adj, TRACKS / adj.name)
        subprocess.run([sys.executable, str(EXTRACT / "gen_tracks.py")], cwd=ROOT, capture_output=True)
        with self.lock:
            self.docs.pop(tid, None)
            self.forget(tid)
        self.system("%s promoted the %s draft to tracks/%s.json." % ("Claude" if author == "claude" else "You",
                                                                      tid, tid))
        self.hub.send({"type": "tracks", **self.listing()})
        return rel(target)


def touched(ops):
    ids = []
    for op in ops if isinstance(ops, list) else [ops]:
        for k in ("id", "from", "to"):
            if isinstance(op, dict) and op.get(k) is not None:
                ids.append(op[k])
    return ids


HUB = Hub()
WS = Workspace(HUB)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        if "--verbose" in sys.argv:
            sys.stderr.write("%s\n" % (fmt % args))

    # Plumbing ---------------------------------------------------------------

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > UPLOAD_LIMIT:
            raise OpError("too large")
        return self.rfile.read(n) if n else b""

    def json_body(self):
        raw = self.body()
        return json.loads(raw.decode("utf-8")) if raw else {}

    def send_json(self, obj, code=200):
        data = json.dumps(obj, separators=(",", ":")).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def send_bytes(self, data, ctype, cache=False):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "max-age=3600" if cache else "no-store")
        self.end_headers()
        self.wfile.write(data)

    def send_file(self, path, cache=False):
        if not path or not path.is_file():
            return self.send_json({"error": "not found"}, 404)
        ctype = mimetypes.guess_type(str(path))[0] or "application/octet-stream"
        self.send_bytes(path.read_bytes(), ctype, cache)

    def route(self, method):
        url = urllib.parse.urlparse(self.path)
        q = {k: v[-1] for k, v in urllib.parse.parse_qs(url.query).items()}
        path = url.path
        try:
            handler = ROUTES.get((method, path))
            if handler:
                return handler(self, q)
            for (m, prefix), fn in PREFIX_ROUTES:
                if m == method and path.startswith(prefix):
                    return fn(self, q, urllib.parse.unquote(path[len(prefix):]))
            self.send_json({"error": "no such endpoint %s %s" % (method, path)}, 404)
        except OpError as e:
            self.send_json({"error": str(e)}, 400)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass
        except Exception as e:
            traceback.print_exc()
            try:
                self.send_json({"error": "%s: %s" % (type(e).__name__, e)}, 500)
            except OSError:
                pass

    def do_GET(self):
        self.route("GET")

    def do_POST(self):
        self.route("POST")


# Endpoints ---------------------------------------------------------------------

def get_index(h, q):
    h.send_file(STATIC / "index.html")


def get_static(h, q, name):
    p = (STATIC / name).resolve()
    if STATIC not in p.parents:
        return h.send_json({"error": "not found"}, 404)
    h.send_file(p)


def get_events(h, q):
    h.send_response(200)
    h.send_header("Content-Type", "text/event-stream")
    h.send_header("Cache-Control", "no-store")
    h.send_header("Connection", "keep-alive")
    h.end_headers()
    sub = HUB.add()
    try:
        first = WS.state()
        first["messages"] = WS.messages[-200:]
        first["jobs"] = [j.info() for j in WS.jobs.values()]
        h.wfile.write(("data: %s\n\n" % json.dumps(first, separators=(",", ":"))).encode("utf-8"))
        h.wfile.write(("data: %s\n\n" % json.dumps({"type": "tracks", **WS.listing()})).encode("utf-8"))
        h.wfile.flush()
        while True:
            try:
                data = sub.get(timeout=15)
                h.wfile.write(("data: %s\n\n" % data).encode("utf-8"))
            except queue.Empty:
                h.wfile.write(b": ping\n\n")
                WS.listening_changed()
            h.wfile.flush()
    except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
        pass
    finally:
        HUB.remove(sub)


def get_tracks(h, q):
    h.send_json(WS.listing())


def get_state(h, q):
    s = WS.state(full=q.get("full", "1") != "0")
    s["jobs"] = [j.info() for j in WS.jobs.values()]
    s["user"] = WS.user_view()
    h.send_json(s)


def get_image(h, q, key):
    h.send_file(WS.image_path(key), cache=True)


def get_stage(h, q, rest):
    key, _, name = rest.rpartition("/")
    folder = WS.stage_dir(key)
    p = (folder / name).resolve()
    if p.parent != folder.resolve() or p.suffix != ".png":
        return h.send_json({"error": "not found"}, 404)
    h.send_file(p)


def get_stages(h, q, key):
    h.send_json({"stages": WS.stages(key)})


def get_space(h, q, sid):
    _, doc = WS.doc(q.get("key"))
    s = doc.find(sid)
    index = doc.index()
    into = [o["id"] for o in doc.spaces if s["id"] in o.get("next", [])]
    start = doc.track.get("start") or []
    h.send_json({"space": s, "into": into, "grid": start.index(s["id"]) + 1 if s["id"] in start else None,
                 "problems": [p["text"] for p in doc.problems if p["id"] == s["id"]],
                 "next": [{"id": n, "lane": index[n]["lane"], "pos": index[n]["pos"]} for n in s.get("next", [])
                          if n in index]})


def get_snapshot(h, q):
    key, doc = WS.doc(q.get("key"))
    box = None
    around = None
    if q.get("box"):
        box = [float(v) for v in q["box"].split(",")]
    elif q.get("around"):
        around = q["around"].split(",")
    elif q.get("view") in ("user", "claude"):
        v = WS.user_view() if q["view"] == "user" else WS.claude_view()
        box = v.get("viewport")
    underlay = None
    if q.get("stage"):
        p = (WS.stage_dir(key) / q["stage"]).resolve()
        if p.parent == WS.stage_dir(key).resolve() and p.exists():
            underlay = p
    with WS.lock:
        png = render.snapshot(doc, WS.image_path(key), box=box, around=around,
                              user_sel=WS.user_view().get("selection") or [],
                              claude_sel=WS.claude_view().get("selection") or [], notes=WS.notes,
                              max_px=int(q.get("size", 1400)), labels=q.get("labels", "1") != "0",
                              underlay=underlay, style=q.get("style", "outline"),
                              links=q.get("links", "1") != "0")
    h.send_bytes(png, "image/png")


def get_messages(h, q):
    after = int(q.get("after", 0))
    wait = min(float(q.get("wait", 0)), 60)
    msgs = WS.wait_messages(after, q.get("from"), wait, q.get("listener")) if wait else \
        [m for m in WS.messages if m["id"] > after and (not q.get("from") or m["from"] == q["from"])]
    h.send_json({"messages": msgs, "last": WS.messages[-1]["id"] if WS.messages else 0})


def post_open(h, q):
    b = h.json_body()
    WS.open_track(b["key"], b.get("author", "user"))
    h.send_json({"ok": True, "open": WS.open})


def post_op(h, q):
    b = h.json_body()
    notes = WS.apply(b.get("ops") or [], b.get("author", "user"), b.get("key"))
    h.send_json({"ok": True, "rev": WS.rev, "notes": notes, "summary": WS.docs[WS.open].summary()})


def post_undo(h, q):
    h.send_json({"ok": WS.undo(h.json_body().get("author", "user")), "rev": WS.rev})


def post_redo(h, q):
    h.send_json({"ok": WS.undo(h.json_body().get("author", "user"), redo=True), "rev": WS.rev})


def post_save(h, q):
    h.send_json({"ok": True, **WS.save(h.json_body().get("author", "user"))})


def post_revert(h, q):
    WS.revert(h.json_body().get("author", "user"))
    h.send_json({"ok": True})


def post_presence(h, q):
    b = h.json_body()
    client = b.get("client") or b.get("who") or "user"
    WS.set_presence(client, b)
    h.send_json({"ok": True})


def post_message(h, q):
    b = h.json_body()
    sender = b.get("from", "user")
    context = b.get("context") or {}
    if sender == "user":
        v = WS.user_view()
        context.setdefault("selection", v.get("selection"))
        context.setdefault("viewport", v.get("viewport"))
        context.setdefault("hover", v.get("hover"))
        context.setdefault("track", WS.open)
    msg = WS.post(sender, b.get("text", ""), context)
    h.send_json({"ok": True, "message": msg})


def post_note(h, q):
    b = h.json_body()
    note = WS.add_note(b.get("author", "claude"), b.get("text", ""), b.get("spaces"), b.get("pos"))
    h.send_json({"ok": True, "note": note})


def post_notes_clear(h, q):
    b = h.json_body()
    WS.drop_notes(b.get("ids"))
    h.send_json({"ok": True})


def post_focus(h, q):
    b = h.json_body()
    HUB.send({"type": "focus", "author": b.get("author", "claude"), "ids": b.get("ids") or [],
              "box": b.get("box"), "text": b.get("text")})
    h.send_json({"ok": True})


def post_detect(h, q):
    b = h.json_body()
    job = WS.detect(b["id"], b.get("options") or {}, b.get("author", "user"))
    h.send_json({"ok": True, "job": job.info(), "key": "draft:" + b["id"]})


def post_upload(h, q):
    tid = WS.upload(q.get("name", "board.jpg"), h.body(), q.get("category"))
    HUB.send({"type": "tracks", **WS.listing()})
    h.send_json({"ok": True, "id": tid})


def post_promote(h, q):
    b = h.json_body()
    path = WS.promote(b["key"], bool(b.get("force")), b.get("author", "user"))
    h.send_json({"ok": True, "path": path})


def post_adjacency(h, q):
    key, _ = WS.doc()
    job = WS.adjacency(key)
    h.send_json({"ok": True, "job": job.info()})


def get_job(h, q, jid):
    job = WS.jobs.get(jid)
    if not job:
        return h.send_json({"error": "no job %s" % jid}, 404)
    h.send_json(job.info())


ROUTES = {
    ("GET", "/"): get_index,
    ("GET", "/api/events"): get_events,
    ("GET", "/api/tracks"): get_tracks,
    ("GET", "/api/state"): get_state,
    ("GET", "/api/snapshot"): get_snapshot,
    ("GET", "/api/messages"): get_messages,
    ("POST", "/api/open"): post_open,
    ("POST", "/api/op"): post_op,
    ("POST", "/api/undo"): post_undo,
    ("POST", "/api/redo"): post_redo,
    ("POST", "/api/save"): post_save,
    ("POST", "/api/revert"): post_revert,
    ("POST", "/api/presence"): post_presence,
    ("POST", "/api/message"): post_message,
    ("POST", "/api/note"): post_note,
    ("POST", "/api/notes/clear"): post_notes_clear,
    ("POST", "/api/focus"): post_focus,
    ("POST", "/api/detect"): post_detect,
    ("POST", "/api/upload"): post_upload,
    ("POST", "/api/promote"): post_promote,
    ("POST", "/api/adjacency"): post_adjacency,
}
PREFIX_ROUTES = [
    (("GET", "/static/"), get_static),
    (("GET", "/api/image/"), get_image),
    (("GET", "/api/stage/"), get_stage),
    (("GET", "/api/stages/"), get_stages),
    (("GET", "/api/space/"), get_space),
    (("GET", "/api/job/"), get_job),
]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    port = PORT
    if "--port" in sys.argv:
        port = int(sys.argv[sys.argv.index("--port") + 1])
        args = [a for a in args if a != str(port)]
    mimetypes.add_type("text/javascript", ".js")
    mimetypes.add_type("text/css", ".css")
    if args:
        WS.open_track(args[0])
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.daemon_threads = True
    url = "http://127.0.0.1:%d/" % port
    print("Track editor on %s  (Ctrl+C to stop)" % url, flush=True)
    if "--no-browser" not in sys.argv:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
