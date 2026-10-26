"""Tests for the browser track editor: the edits, and the server round trip.

Edits are made to copies of tracks/FDMonaco.json; nothing under tracks/ is
written. The server runs on a free port with its scratch folders in a
temporary directory.

Run:  python tools/editor/test_editor.py
"""
import copy
import json
import pathlib
import sys
import tempfile
import threading
import unittest
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))

from trackdoc import OpError, TrackDoc  # noqa: E402

MONACO = json.loads((ROOT / "tracks" / "FDMonaco.json").read_text(encoding="utf-8"))


def doc():
    return TrackDoc(copy.deepcopy(MONACO))


class Edits(unittest.TestCase):
    def test_opening_monaco_finds_nothing_wrong(self):
        d = doc()
        self.assertEqual(d.problems, [])
        self.assertGreater(d.cell, 30)
        self.assertFalse(d.dirty)

    def test_turning_a_space_round_is_a_problem_and_undo_puts_it_back(self):
        d = doc()
        before = copy.deepcopy(d.find("m.c1.3"))
        d.apply([{"op": "turn", "id": "m.c1.3", "by": 180}])
        self.assertIn("m.c1.3", {p["id"] for p in d.problems})
        self.assertTrue(d.dirty)
        self.assertTrue(d.undo())
        self.assertEqual(d.find("m.c1.3"), before)
        self.assertEqual(d.problems, [])
        self.assertTrue(d.redo())
        self.assertAlmostEqual(d.find("m.c1.3")["rot"], (before["rot"] + 180) % 360, places=1)

    def test_a_link_set_by_hand_is_fixed_and_toggles(self):
        d = doc()
        d.apply([{"op": "unfix", "id": "o.s2.1"}])
        had = list(d.find("o.s2.1")["next"])
        d.apply([{"op": "link", "from": "o.s2.1", "to": "i.s2.3"}])
        s = d.find("o.s2.1")
        self.assertTrue(s["fixed"])
        self.assertIn("i.s2.3", s["next"])
        # Moving another space relinks the track, but leaves this one alone.
        d.apply([{"op": "move", "id": "m.s2.4", "pos": d.find("m.s2.4")["pos"]}])
        self.assertIn("i.s2.3", d.find("o.s2.1")["next"])
        d.apply([{"op": "link", "from": "o.s2.1", "to": "i.s2.3"}])
        self.assertEqual(sorted(d.find("o.s2.1")["next"]), sorted(had))
        # Back to automatic: relinked from where the spaces are.
        d.apply([{"op": "unfix", "id": "o.s2.1"}])
        self.assertNotIn("fixed", d.find("o.s2.1"))

    def test_a_failed_batch_changes_nothing(self):
        d = doc()
        before = json.dumps(d.track, sort_keys=True)
        with self.assertRaises(OpError):
            d.apply([{"op": "move", "id": "m.c1.3", "pos": [1, 2]}, {"op": "lane", "id": "nope", "lane": 2}])
        with self.assertRaises(OpError):
            d.apply([{"op": "set", "id": "m.c1.3", "fields": {"next": []}}])
        with self.assertRaises(OpError):
            d.apply([{"op": "move", "id": "m.c1.3"}])
        self.assertEqual(json.dumps(d.track, sort_keys=True), before)
        self.assertFalse(d.dirty)
        self.assertFalse(d.undo_stack)

    def test_added_spaces_are_named_after_their_neighbour(self):
        d = doc()
        x, y = d.find("m.c1.3")["pos"]
        d.apply([{"op": "add", "pos": [x + 3, y + 3]}, {"op": "add", "pos": [x + 4, y + 4]}])
        ids = [s["id"] for s in d.spaces[-2:]]
        self.assertEqual(ids, ["m.c1.3+1", "m.c1.3+2"])
        self.assertEqual(d.find("m.c1.3+1")["sector"], "c1")
        self.assertTrue(d.moved)

    def test_deleting_a_space_takes_it_off_the_grid_and_out_of_every_link(self):
        d = doc()
        pole = d.track["start"][0]
        d.apply([{"op": "delete", "id": pole}])
        self.assertNotIn(pole, d.track["start"])
        self.assertFalse(any(pole in s["next"] for s in d.spaces))

    def test_the_grid_and_layout(self):
        d = doc()
        d.apply([{"op": "grid_set", "ids": []}, {"op": "grid", "id": "m.s1.0"}, {"op": "grid", "id": "i.s1.0"}])
        self.assertEqual(d.track["start"], ["m.s1.0", "i.s1.0"])
        d.apply([{"op": "grid", "id": "m.s1.0"}])
        self.assertEqual(d.track["start"], ["i.s1.0"])
        d.apply([{"op": "dice", "pos": [100.4, 200.6]}, {"op": "dice_side", "side": "left"},
                 {"op": "panel", "pos": [500, 600], "width": 99999}])
        self.assertEqual(d.track["dice"], [100, 201])
        self.assertEqual(d.track["dice_side"], "left")
        self.assertEqual(d.track["panel"], {"pos": [500, 600], "width": 1600})
        with self.assertRaises(OpError):
            d.apply([{"op": "dice_side", "side": "sideways"}])

    def test_a_space_leaves_the_pit_lane_with_its_lane(self):
        d = doc()
        first = d.track["pit"]["spaces"][0]
        x, y = d.find(first)["pos"]
        d.apply([{"op": "add", "pos": [x + 2, y + 2]}])
        added = d.spaces[-1]
        self.assertTrue(added["pit"], "added beside the pit lane, it starts in it")
        d.apply([{"op": "lane", "id": added["id"], "lane": 1}])
        self.assertNotIn("pit", d.find(added["id"]))
        d.apply([{"op": "lane", "id": added["id"], "lane": 0}])
        self.assertTrue(d.find(added["id"])["pit"])

    def test_the_pit_lanes_ways_in_and_out_follow_its_links(self):
        d = doc()
        pit = MONACO["pit"]
        out = d.for_file("x")["pit"]
        self.assertEqual(out["entry"], pit["entry"])
        self.assertEqual(out["exit"], pit["exit"])
        self.assertEqual(out["spaces"], pit["spaces"])
        # A way in taken away is gone from the list.
        way = pit["entry"][0]
        d.apply([{"op": "link", "from": way, "to": pit["spaces"][0]}])
        self.assertNotIn(way, d.for_file("x")["pit"]["entry"])

    def test_a_space_added_to_the_pit_lane_falls_into_its_order(self):
        d = doc()
        lane = MONACO["pit"]["spaces"]
        a, b = d.find(lane[3]), d.find(lane[4])
        mid = [(a["pos"][0] + b["pos"][0]) / 2, (a["pos"][1] + b["pos"][1]) / 2]
        d.apply([{"op": "add", "pos": mid, "like": lane[3], "new_id": "p.new"}])
        d.apply([{"op": "link", "from": lane[3], "to": lane[4]}, {"op": "link", "from": lane[3], "to": "p.new"},
                 {"op": "link", "from": "p.new", "to": lane[4]}])
        track = d.for_file("x")
        out = track["pit"]["spaces"]
        self.assertEqual(out, lane[:4] + ["p.new"] + lane[4:])
        # Renumbered, the pit lane's list is its new codes, each once, in order.
        import renumber
        mapping = renumber.codes(track)
        self.assertEqual(mapping["p.new"], lane[4])
        renumber.rename(track, mapping)
        self.assertEqual(track["pit"]["spaces"], [mapping.get(i, i) for i in out])
        self.assertEqual(track["pit"]["spaces"], renumber.pit_order(track))

    def test_codes_follow_lanes_and_places(self):
        import renumber
        self.assertEqual(renumber.codes(copy.deepcopy(MONACO)), {}, "Monaco's codes are right as they are")
        d = doc()
        # A space added in the inside lane beside a middle-lane one.
        a, b = d.find("i.c1.1"), d.find("i.c1.2")
        mid = [(a["pos"][0] + b["pos"][0]) / 2, (a["pos"][1] + b["pos"][1]) / 2]
        d.apply([{"op": "add", "pos": mid, "like": "m.c1.2"}, {"op": "lane", "id": "m.c1.2+1", "lane": 1},
                 {"op": "rotate", "id": "m.c1.2+1", "rot": a["rot"]}])
        # i.c1.1's links are set by hand: it is linked on to the new space.
        if "i.c1.2" in d.find("i.c1.1")["next"]:
            d.apply([{"op": "link", "from": "i.c1.1", "to": "i.c1.2"}])
        if "m.c1.2+1" not in d.find("i.c1.1")["next"]:
            d.apply([{"op": "link", "from": "i.c1.1", "to": "m.c1.2+1"}])
        if "i.c1.2" not in d.find("m.c1.2+1")["next"]:
            d.apply([{"op": "link", "from": "m.c1.2+1", "to": "i.c1.2"}])
        track = d.for_file("x")
        mapping = renumber.codes(track)
        self.assertEqual(mapping["m.c1.2+1"], "i.c1.2")
        self.assertEqual(mapping["i.c1.2"], "i.c1.3")
        renumber.rename(track, mapping)
        ids = {s["id"] for s in track["spaces"]}
        self.assertFalse(any("+" in i for i in ids))
        self.assertTrue(all(n in ids for s in track["spaces"] for n in s["next"]))
        self.assertTrue(all(g in ids for g in track["start"]))
        self.assertEqual(sorted(track["finish"]["line"]), sorted(MONACO["finish"]["line"]))

    def test_the_track_tests_run_on_the_working_copy(self):
        import checks
        d = doc()
        self.assertEqual(checks.run(d.for_file("x"), ROOT / "tracks" / "FDMonaco.adjacency.json"), [])
        # Monaco's first pit space turned into a track space: the tests see it.
        first = d.track["pit"]["spaces"][0]
        d.apply([{"op": "lane", "id": first, "lane": 1}])
        failed = checks.run(d.for_file("x"), ROOT / "tracks" / "FDMonaco.adjacency.json")
        self.assertTrue(failed and all(first in f["text"] for f in failed), failed)

    def test_the_file_written_is_shaped_like_an_import_from_the_game(self):
        d = doc()
        d.apply([{"op": "turn", "id": "m.c1.3", "by": 5}])
        out = d.for_file("web editor (test)")
        self.assertTrue(out["edited"])
        self.assertEqual(out["edited_from"], "web editor (test)")
        self.assertEqual([s["id"] for s in out["spaces"]], sorted((s["id"] for s in out["spaces"]), key=str))
        for k in ("corners", "finish", "pit", "detect", "image", "name"):
            self.assertEqual(out[k], MONACO[k], k)
        old = {s["id"]: s for s in MONACO["spaces"]}
        for s in out["spaces"]:
            self.assertEqual(set(s), set(old[s["id"]]), s["id"])


class Server(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import server
        cls.tmp = tempfile.TemporaryDirectory()
        tmp = pathlib.Path(cls.tmp.name)
        server.SANDBOX = tmp / "web"
        server.SESSION = tmp / "web" / "_session"
        # A draft, so saving writes only into the scratch folder.
        (server.SANDBOX / "Test").mkdir(parents=True)
        track = copy.deepcopy(MONACO)
        track["id"] = "Test"
        (server.SANDBOX / "Test" / "Test.json").write_text(json.dumps(track), encoding="utf-8")
        cls.server = server
        cls.http = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        cls.http.daemon_threads = True
        cls.url = "http://127.0.0.1:%d" % cls.http.server_address[1]
        threading.Thread(target=cls.http.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown()
        cls.tmp.cleanup()

    def call(self, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.url + path, data=data, method="POST" if body is not None else "GET")
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status, (json.loads(r.read()) if "json" in r.headers["Content-Type"] else r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_edit_save_and_talk(self):
        code, r = self.call("/api/open", {"key": "draft:Test"})
        self.assertEqual(code, 200)
        code, r = self.call("/api/op", {"author": "claude", "ops": [{"op": "turn", "id": "m.c1.3", "by": 180}]})
        self.assertEqual(code, 200)
        self.assertGreater(r["summary"]["problems"], 0)
        code, st = self.call("/api/state")
        self.assertEqual(st["last"]["author"], "claude")
        self.assertTrue(st["summary"]["dirty"])
        # Unsaved edits are kept aside against a restart.
        self.assertTrue((self.server.SESSION / "draft__Test.json").exists())
        code, r = self.call("/api/op", {"ops": [{"op": "lane", "id": "nope", "lane": 1}]})
        self.assertEqual(code, 400)
        self.assertIn("nope", r["error"])
        self.call("/api/undo", {"author": "user"})
        code, r = self.call("/api/save", {"author": "user"})
        self.assertEqual(code, 200)
        saved = json.loads((self.server.SANDBOX / "Test" / "Test.json").read_text(encoding="utf-8"))
        self.assertTrue(saved["edited"])
        self.assertFalse((self.server.SESSION / "draft__Test.json").exists())
        # The user's message reaches Claude with what they had selected.
        self.call("/api/presence", {"client": "p1", "who": "user", "selection": ["m.c1.3"],
                                    "viewport": [0, 0, 100, 100]})
        self.call("/api/message", {"from": "user", "text": "this one?"})
        code, r = self.call("/api/messages?after=0&from=user&wait=1&listener=claude")
        msg = r["messages"][-1]
        self.assertEqual(msg["text"], "this one?")
        self.assertEqual(msg["context"]["selection"], ["m.c1.3"])
        code, png = self.call("/api/snapshot?around=m.c1.3&size=300")
        self.assertEqual(png[:4], b"\x89PNG")


if __name__ == "__main__":
    unittest.main(verbosity=2)
