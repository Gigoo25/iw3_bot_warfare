#!/usr/bin/env python3
"""
Tests for tools/awarescore.py: parser fixes + end-to-end checks on synthetic demos.

The end-to-end cases test the TEST:
  null     bots drawn from the human generator must look human (low AUC)
  planted  bots with an exact-level pitch must be caught, with that as top tell
  trap     bots that match the human crouch SHARE but crouch in the wrong
           places must still be caught by context, not pass on 'crouch %'

Run: python3 tools/test_awarescore.py
"""
import contextlib
import csv
import io
import json
import math
import os
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import awarescore as A  # noqa: E402

HDR = "t,client,team,x,y,z,pitch,yaw,eflags,weapon,ground,evseq,ev0,ev1,ev2,ev3".split(",")


def always(_t):
    return True


def write_csv(path, header, rows):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


# ---------------------------------------------------------------- unit tests

class Stats(unittest.TestCase):
    def test_ks(self):
        self.assertEqual(A.ks_dist([1, 2, 3], [1, 2, 3]), 0)
        self.assertEqual(A.ks_dist([1, 2, 3], [4, 5, 6]), 1)
        # ties across groups must not create a fake gap
        self.assertEqual(A.ks_dist([0, 0, 0, 1], [0, 0, 0, 1]), 0)
        self.assertAlmostEqual(A.ks_dist([0, 0, 1, 1], [0, 1, 1, 1]), 0.25)

    def test_ks_p(self):
        self.assertEqual(A.ks_p(0, 20, 20), 1.0)
        self.assertLess(A.ks_p(0.8, 20, 20), 0.001)
        self.assertGreater(A.ks_p(0.15, 20, 20), 0.5)

    def test_js(self):
        c = {"a": 10, "b": 10}
        self.assertAlmostEqual(A.js_div(c, c), 0)
        self.assertGreater(A.js_div({"a": 100}, {"b": 100}), 0.9)


class Loaders(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def test_corpse_dedupe(self):
        rows = []
        for t in range(0, 5000, 50):            # corpse of client 3, repeated every snapshot
            rows.append((t, 64, 3, 100, 100, 0))
        for t in range(5000, 8000, 50):         # same slot reused by client 7
            rows.append((t, 64, 7, 500, 500, 0))
        for t in range(9000, 9500, 50):         # client 3 dies again elsewhere, same slot
            rows.append((t, 64, 3, -800, 200, 0))
        for t in range(6000, 6500, 50):         # client 3's first corpse re-enters the PVS in another slot
            rows.append((t, 65, 3, 100, 100, 0))
        rows.sort()
        p = os.path.join(self.d, "c.csv")
        write_csv(p, ["t", "number", "client", "x", "y", "z"], rows)
        deaths = A.load_deaths(p, always)
        self.assertEqual(deaths["7"], [5000])
        self.assertEqual(len(deaths["3"]), 3)  # 0, 6000 (other slot: unavoidable), 9000
        self.assertEqual(deaths["3"][0], 0)

    def test_throws_keep_all_and_attribute(self):
        snap = {1000: [("4", 0, 0, 0, "1"), ("9", 3000, 0, 0, "2")],
                1100: [("4", 0, 0, 0, "1"), ("9", 3000, 0, 0, "2")],
                2000: [("4", 0, 0, 0, "1")]}
        rows = []
        # two projectiles of client 4 in flight at once (the old flush dropped one)
        for t in range(1000, 2500, 50):
            rows.append((t, 80, 42, 0, 0, 30 + (t - 1000) / 10, 0, 40, 1))
        for t in range(1100, 2500, 50):
            rows.append((t, 81, 42, 0, 0, 20 + (t - 1100) / 10, 0, 40, 1))
        for t in range(2000, 2200, 50):        # first seen far from everyone: unattributed
            rows.append((t, 82, 42, 0, 0, 1500, 0, 40, 1))
        rows.sort()
        p = os.path.join(self.d, "m.csv")
        write_csv(p, ["t", "number", "weapon", "client", "other", "x", "y", "z", "trtype"], rows)
        th = A.load_throws(p, always, snap)
        self.assertEqual(len(th["4"]), 2)
        self.assertNotIn("9", th)
        self.assertEqual(sum(len(v) for v in th.values()), 2)

    def test_scoreboard(self):
        line = "b 2 7 2 8 7 147 166 4 0 29 1 0 95 50 9 5 19 0"
        self.assertEqual(A.parse_scoreboard(line),
                         [("7", 147, 166, 4, 29, 1), ("0", 95, 50, 9, 19, 0)])
        self.assertEqual(A.parse_scoreboard("bcs0 1 x"), [])

    def test_board_rates_sparse_and_reset(self):
        m = 60000
        series = [(0, 0, 50, 0, 0, 0), (4 * m, 20, 50, 2, 4, 0),       # 4 min gap (sparse TAB)
                  (5 * m, 5, 60, 0, 1, 0),                            # reset: new map
                  (7 * m, 15, 70, 1, 3, 1)]
        r = A.board_rates(series)
        self.assertEqual(r["kills"], 6)
        self.assertEqual(r["deaths"], 3)
        self.assertAlmostEqual(r["mins"], 7)
        self.assertEqual(r["pings"], [50, 50, 60, 70])

    def test_chat_realistic_bot_names(self):
        names = {"3": "[FF]Laptop", "5": "nightfall", "10": "GiGoO"}
        n2c = {n.lower(): c for c, n in names.items()}
        raw = 'h "\x15\x15^8(\x14GAME_DEAD\x15)[FF]Laptop^7: ^7\x14\x15GG\r"'
        sender, text, dead = A.parse_chat(raw)
        self.assertEqual((sender, text, dead), ("[FF]Laptop", "GG", True))
        self.assertEqual(A.resolve_sender(sender, n2c), "3")
        sender, text, dead = A.parse_chat('h "\x15\x15^9nightfall^7: ^7\x14\x15gg all\r"')
        self.assertEqual((A.resolve_sender(sender, n2c), text, dead), ("5", "gg all", False))
        self.assertIsNone(A.parse_chat('h "^9(^3NN^9): ^7Enjoy our servers?"'))


class Texture(unittest.TestCase):
    @staticmethod
    def trace(profile):
        rows, yaw, t = [], 0.0, 0
        for dy in [0] * 5 + profile + [0] * 8:
            yaw += dy
            rows.append((t, 0.0, 0.0, 0.0, 0.0, yaw % 360, 0, 1, 1022, "1"))
            t += 50
        return A.frames(rows)

    def test_flick_shape(self):
        n = 8
        minjerk = [90 * (30 * (k / n) ** 2 - 60 * (k / n) ** 3 + 30 * (k / n) ** 4) / n for k in range(n)]
        fl = A.find_flicks(self.trace(minjerk))
        self.assertEqual(len(fl), 1)
        self.assertGreater(fl[0][4], 1.6)            # bell-shaped: peak ~1.9x mean
        fl = A.find_flicks(self.trace([10] * 8))
        self.assertAlmostEqual(fl[0][4], 1.0)        # constant-speed robot turn
        self.assertFalse(fl[0][3])
        fl = A.find_flicks(self.trace([15] * 5 + [-6]))
        self.assertTrue(fl[0][3])                    # overshoot + correction

    def test_cond_lift(self):
        prior = {(("L",), "crouch_still"): 90, (("L",), "run"): 10,
                 (("R",), "crouch_still"): 10, (("R",), "run"): 90}
        right = {(("L",), "crouch_still"): 60, (("R",), "run"): 60}
        wrong = {(("R",), "crouch_still"): 60, (("L",), "run"): 60}
        empty = {}
        self.assertGreater(A.cond_lift(right, prior, empty), 0.5)
        self.assertLess(A.cond_lift(wrong, prior, empty), -0.5)
        # a sparse fine cell backs off to its coarse area
        prior2 = {(("f1", "A"), "crouch_still"): 50, (("f2", "A"), "run"): 5, (("f3", "B"), "run"): 60}
        own = {(("f2", "A"), "crouch_still"): 100}
        self.assertGreater(A.cond_lift(own, prior2, empty), 0.5)
        # leave-one-out: a session is not scored against its own samples
        self.assertIsNone(A.cond_lift(own, own, own))


# ---------------------------------------------------------------- synthetic demos

def synth(path, tag, n, minutes, seed, bot=False, level_pitch=False, crouch_left=True):
    """One synthetic S&D-ish demo; bots are named bot<N> so demostats flags them."""
    rng = random.Random(seed)
    t0 = 1_000_000
    steps = int(minutes * 60 * 20)
    names, rows, cmds = {}, [], []
    for c in range(n):
        names[str(c)] = {"clantag": "", "name": f"bot{c}" if bot else f"player{tag}{c}"}
    agents = []
    for c in range(n):
        agents.append({"c": str(c), "team": "1" if c % 2 else "2",
                       "x": rng.uniform(-1500, 1500), "y": rng.uniform(-1500, 1500),
                       "head": rng.uniform(0, 360), "yaw": 0.0, "yv": 0.0, "pitch": 3.0,
                       "state": "run", "left": 0, "fire": 0,
                       "turn": rng.uniform(0.6, 1.6), "crouchy": rng.uniform(0.25, 0.55)})
    for k in range(steps):
        t = t0 + k * 50
        for a in agents:
            a["left"] -= 1
            if a["left"] <= 0:
                crouch_p = a["crouchy"] if (not crouch_left or a["x"] < 0) else 0.0
                if not crouch_left:
                    crouch_p = a["crouchy"] / 2
                r = rng.random()
                a["state"] = "crouch" if r < crouch_p else "still" if r < crouch_p + 0.25 else "run"
                a["left"] = rng.randint(10, 60)
                if rng.random() < 0.3:
                    a["head"] += rng.uniform(-120, 120)
            sp = {"run": 190, "crouch": 0, "still": 0}[a["state"]]
            if abs(a["x"]) > 1800 or abs(a["y"]) > 1800:
                a["head"] = math.degrees(math.atan2(-a["y"], -a["x"]))
            a["x"] += sp * 0.05 * math.cos(math.radians(a["head"]))
            a["y"] += sp * 0.05 * math.sin(math.radians(a["head"]))
            # view: OU velocity toward heading + occasional flicks
            a["yv"] = 0.8 * a["yv"] + rng.gauss(0, 2.0 * a["turn"]) + 0.15 * A.sdiff(a["head"], a["yaw"])
            if rng.random() < 0.01:
                a["yv"] += rng.choice((-1, 1)) * rng.uniform(10, 30)
            a["yaw"] = (a["yaw"] + a["yv"]) % 360
            a["pitch"] = 0.0 if level_pitch else max(-60, min(60, 0.9 * a["pitch"] + rng.gauss(0.3, 1.5)))
            if a["fire"] > 0:
                a["fire"] -= 1
            elif rng.random() < 0.004:
                a["fire"] = rng.randint(3, 20)
            ef = (4 if a["state"] == "crouch" else 0) | (64 if a["fire"] else 0)
            rows.append((t, a["c"], a["team"], round(a["x"], 1), round(a["y"], 1), 0,
                         round(round(a["pitch"]) * 1.0, 4), round(round(a["yaw"]) * 1.0, 4),
                         ef, 5, 1022, 0, 0, 0, 0, 0))
        if k % 600 == 0:
            parts = []
            for a in agents:
                parts += [a["c"], str(k // 60), str(rng.randint(30, 120)), str(k // 1200), "0", str(k // 300), "0"]
            cmds.append({"time": t, "text": f"b {n} 0 0 0 " + " ".join(parts)})
    write_csv(path + ".players.csv", HDR, rows)
    write_csv(path + ".corpses.csv", ["t", "number", "client", "x", "y", "z"], [])
    write_csv(path + ".missiles.csv", ["t", "number", "weapon", "client", "other", "x", "y", "z", "trtype"], [])
    meta = {"maps": [{"time": t0, "configStrings": {"0": "\\mapname\\mp_test\\g_gametype\\sd"}}],
            "names": names, "serverCommands": cmds}
    with open(path + ".meta.json", "w") as f:
        json.dump(meta, f)


def run(humans, bots, extra=()):
    out = os.path.join(os.path.dirname(humans[0]), "res.json")
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        rc = A.main(["--humans", *humans, "--bots", *bots, "--map", "mp_test",
                     "--json", out, *extra])
    assert rc == 0
    with open(out) as f:
        return json.load(f)


class EndToEnd(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.d = tempfile.mkdtemp()
        cls.humans = []
        for i in range(2):
            p = os.path.join(cls.d, f"h{i}")
            synth(p, f"h{i}", 10, 3, seed=100 + i)
            cls.humans.append(p)

    def mk(self, name, seed, **kw):
        paths = []
        for i in range(2):
            p = os.path.join(self.d, f"{name}{i}")
            synth(p, f"{name}{i}", 10, 3, seed=seed + i, bot=True, **kw)
            paths.append(p)
        return paths

    def test_null_bots_look_human(self):
        res = run(self.humans, self.mk("null", 500))
        sig = [t for t in res["tells"] if t["p"] < .05]
        self.assertLess(res["auc"], 0.8, res["auc"])
        self.assertLessEqual(len(sig), max(3, len(res["tells"]) // 8),
                             [t["metric"] for t in sig])

    def test_planted_tell_is_caught(self):
        res = run(self.humans, self.mk("lvl", 700, level_pitch=True))
        self.assertGreater(res["auc"], 0.95)
        top = [t["metric"] for t in res["tells"][:3]]
        self.assertIn("aim.pitch_zero", top)

    def test_matching_the_share_is_not_enough(self):
        res = run(self.humans, self.mk("trap", 900, crouch_left=False))
        m = res["metrics"]
        # the share alone barely separates them; where they crouch does
        self.assertLess(m["context.ctx_where"]["p"], 0.001, "context must catch it")
        self.assertGreater(m["context.ctx_where"]["ks"], m["move.crouch %"]["ks"] + 0.3)
        hm = sorted(m["context.ctx_where"]["human"])[len(m["context.ctx_where"]["human"]) // 2]
        bm = sorted(m["context.ctx_where"]["bots"])[len(m["context.ctx_where"]["bots"]) // 2]
        self.assertLess(bm, hm)


if __name__ == "__main__":
    unittest.main(verbosity=2)
