#!/usr/bin/env python3
"""Tests for tools/btlog.py -- the offline (no demo, no human) telemetry scorer.

The end-to-end cases test the TEST:
  null     bots whose movement is drawn from the human generator must look human
  planted  bots that snap their aim / freeze their speed must be caught, with
           that as the top tell

Plus parser coverage: mm:ss prefixes (games_mp.log), RFC3339 prefixes
(docker logs --timestamps), untimestamped console lines, the older 15-column
log format, and demo CSVs (velocity from finite differences, decimated to 5 Hz).

Run: python3 tools/test_btlog.py
"""
import contextlib
import io
import math
import os
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import awarescore as A  # noqa: E402
import btlog  # noqa: E402

HDR = "t,client,team,x,y,z,pitch,yaw,eflags,weapon,ground,evseq,ev0,ev1,ev2,ev3"


def bt_line(t, num, name, isbot, x, y, z, vx, vy, vz, pitch, yaw,
            stance="stand", ads=0, target=0, skill=0, weapon="usp_mp",
            look_src="useful", depth=200, cols=18):
    parts = [str(num), name, str(isbot), f"{x:.0f}", f"{y:.0f}", f"{z:.0f}",
             f"{vx:.0f}", f"{vy:.0f}", f"{vz:.0f}", f"{pitch:.0f}", f"{yaw:.0f}",
             stance, str(ads), str(target), str(skill), weapon, look_src, str(depth)]
    return f"{t // 60}:{t % 60:02d} BT;" + ";".join(parts[:cols]) + "\n"


def bt_iso(t, num, name, isbot, x, y, z, vx, vy, vz, pitch, yaw, **kw):
    """Same payload with an RFC3339 timestamp, so synthetic samples can be 0.2s
    apart like the real 5Hz console channel (games_mp.log only has 1s resolution)."""
    whole = int(t)
    frac = f"{t - whole:.3f}"[2:]
    stamp = f"2026-09-27T{6 + whole // 3600:02d}:{whole // 60 % 60:02d}:{whole % 60:02d}.{frac}Z"
    payload = bt_line(0, num, name, isbot, x, y, z, vx, vy, vz, pitch, yaw, **kw)
    payload = payload.split(" BT;", 1)[1]
    return f"{stamp} BT;{payload}"


def walk(rng, samples, isbot, snap=False, freeze=False, instant=False, sloppy=False,
         human_params=None, player=0, name=None, fire=False):
    """A plausible session: bounded turn rate, speed that ramps, weapon dwell."""
    hp = human_params or {}
    turn = 0.0
    last_fire = None
    x, y, z = hp.get("start", (-400.0, -2200.0, 0.0))
    yaw = hp.get("yaw", 90.0)
    pitch = hp.get("pitch", -5.0)
    speed = 0.0
    vz = 0.0
    weapon, wleft = "usp_mp", rng.uniform(1.5, 8.0)
    t = 0.0
    out = []
    for i in range(samples):
        # human-ish turn: a correlated random walk (people's view has inertia),
        # occasionally a deliberate snap to something they just heard
        if snap and rng.random() < .05:
            turn = rng.choice([-1, 1]) * rng.uniform(140, 300)
        else:
            turn = .85 * turn + rng.gauss(0, 20 if sloppy else 6)
        yaw = (yaw + turn) % 360
        pitch = max(-80, min(80, pitch + rng.gauss(0, 4)))
        want = (250 if (i % 10) < 2 else 0) if freeze else (250 if rng.random() < .6 else 0)
        ramp = 1e3 if instant else 40
        speed += max(-ramp, min(ramp, want - speed))
        vx, vy = speed * math.cos(math.radians(yaw)), speed * math.sin(math.radians(yaw))
        x += vx * btlog.DT
        y += vy * btlog.DT
        wleft -= btlog.DT
        if wleft <= 0:
            weapon = rng.choice(["usp_mp", "mp5_mp", "m16_mp", "ak74_mp"])
            wleft = rng.uniform(1.5, 8.0)
        stance = "crouch" if rng.random() < (0.15 if sloppy else 0.05) else "stand"
        depth = -1 if rng.random() < (0.3 if sloppy else 0.1) else rng.uniform(50, 900)
        line = bt_iso(t, player, name or f"P{player}", int(isbot), x, y, z, vx, vy, vz,
                      pitch, yaw, stance=stance, ads=10 if rng.random() < .1 else 0,
                      target=1 if rng.random() < .05 else 0,
                      weapon=weapon, look_src=rng.choice(["useful", "gaze", "path"]),
                      depth=int(depth))
        if fire:
            if last_fire is None or t - last_fire > 1.5:
                last_fire = t
            line = line.rstrip("\n") + f";{int((t - last_fire) * 1000)}\n"
        out.append(line)
        t += btlog.DT
    return out


def write_log(path, lines):
    with open(path, "w") as f:
        f.writelines(lines)
    return path


class Parser(unittest.TestCase):
    def test_games_mp_prefix_and_fields(self):
        p = write_log(os.path.join(tempfile.mkdtemp(), "g.log"),
                      [bt_line(0, 3, "Vlad", 1, 10, 20, 30, 1, 2, 3, -4, 5),
                       bt_line(61, 3, "Vlad", 1, 11, 20, 30, 1, 2, 3, -4, 5)])
        rows = list(btlog.parse(p))
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["t"], 0)
        self.assertEqual(rows[1]["t"], 61, "mm:ss is minutes:seconds and may exceed 59")
        self.assertEqual((rows[0]["x"], rows[0]["vy"], rows[0]["pitch"]), (10, 2, -4))
        self.assertEqual(rows[0]["ads"], 0.0)

    def test_docker_iso_prefix(self):
        rows = list(btlog.parse("-", stream=iter([
            "2026-09-27T05:12:33.120Z BT;2;mongo;1;5;6;7;0;0;0;0;90;stand;0;0;1;usp_mp;useful;100\n",
            "2026-09-27T05:12:33.320Z BT;2;mongo;1;5;6;7;0;0;0;0;90;stand;0;0;1;usp_mp;useful;100\n"])))
        self.assertEqual(len(rows), 2)
        self.assertAlmostEqual(rows[1]["t"] - rows[0]["t"], .2, places=3)
        self.assertEqual(rows[0]["name"], "mongo")

    def test_untimestamped_console_lines_fall_back_to_rate(self):
        rows = list(btlog.parse("-", stream=iter([
            "] BT;0;x;1;1;1;1;0;0;0;0;0;stand;0;0;1;usp_mp;useful;100\n"] * 5)))
        self.assertEqual(len(rows), 5)
        self.assertAlmostEqual(rows[-1]["t"], 4 * btlog.DT, places=6)

    def test_console_overstrike_and_ansi_are_stripped(self):
        # what docker logs --timestamps actually hands us
        raw = ("2026-09-27T05:30:12.007763000Z ]\x08 \x08BT;7;BenniZero;1;-587;-381;64;"
               "-105;250;10;-6;95;stand;0;0;1;m16_reflex_mp;path;697\x1b[0m\r\n")
        rows = list(btlog.parse("-", stream=iter([raw])))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["name"], "BenniZero")
        self.assertEqual(rows[0]["depth"], 697.0, "the trailing escape must not break float()")
        self.assertEqual(rows[0]["vy"], 250.0)

    def test_old_15_column_log_keeps_going(self):
        line = bt_line(0, 1, "old", 0, 1, 2, 3, 0, 0, 0, 0, 0, cols=15)
        rows = list(btlog.parse("-", stream=iter([line])))
        self.assertEqual(len(rows), 1)
        self.assertIsNone(rows[0]["depth"], "field the log does not have")
        self.assertIsNone(rows[0]["weapon"])
        v = btlog.analyse([rows[0]] * 60)
        self.assertNotIn(("look", "depth_p50"), v, "no depth column -> no depth metric")
        self.assertNotIn(("weapon", "distinct"), v)
        self.assertIn(("speed", "p50"), v, "speed is still measurable")

    def test_negative_depth_means_nothing_in_front(self):
        row = bt_line(0, 1, "n", 1, 1, 1, 1, 0, 0, 0, 0, 0, depth=-1)
        rows = list(btlog.parse("-", stream=iter([row])))
        self.assertIsNone(rows[0]["depth"])

    def test_sessions_split_on_gaps_and_filter_thin(self):
        rng = random.Random(3)
        d = tempfile.mkdtemp()
        p = write_log(os.path.join(d, "g.log"),
                      walk(rng, 700, isbot=True) +
                      [bt_line(9999, 0, "P0", 1, 0, 0, 0, 0, 0, 0, 0, 0)] * 40)
        sess = btlog.sessions(list(btlog.parse(p)), min_minutes=1.0)
        self.assertEqual(len(sess), 1, "the 40-line burst is a separate, too-short session")
        self.assertGreater(sess[0][4], 2.0, "700 samples at 5Hz is ~2.3 minutes")

    def test_thin_players_are_dropped(self):
        rng = random.Random(4)
        d = tempfile.mkdtemp()
        p = write_log(os.path.join(d, "g.log"), walk(rng, 20, isbot=True))  # 20 s
        self.assertEqual(btlog.sessions(list(btlog.parse(p)), min_minutes=1.0), [])


class Metrics(unittest.TestCase):
    def setUp(self):
        rng = random.Random(11)
        self.rows = [list(btlog.parse("-", stream=iter(walk(rng, 900, isbot=True))))[0]
                     for _ in range(1)]

    def _rows(self, lines):
        return list(btlog.parse("-", stream=iter(lines)))

    def test_speed_percentiles_and_shares(self):
        rng = random.Random(5)
        v = btlog.analyse(self._rows(walk(rng, 900, isbot=False)))
        self.assertIn(("speed", "p50"), v)
        self.assertTrue(0 <= v[("speed", "walk_pct")] <= 100)
        self.assertGreater(v[("speed", "still_pct")], 0, "a bot that stops sometimes")
        self.assertLess(v[("stance", "crouch_pct")], 30, "shares are percentages, not counts")

    def test_snapping_bots_are_caught(self):
        rng = random.Random(7)
        calm = btlog.analyse(self._rows(walk(rng, 900, isbot=False)))
        snap = btlog.analyse(self._rows(walk(rng, 900, isbot=True, snap=True)))
        self.assertGreater(snap[("turn", "snap_pct")], calm[("turn", "snap_pct")] * 2)
        self.assertLess(calm[("turn", "snap_pct")], 2.0, "the human generator does not snap")
        self.assertGreater(snap[("turn", "rate_p90")], calm[("turn", "rate_p90")])

    def test_frozen_bots_are_caught(self):
        rng = random.Random(9)
        calm = btlog.analyse(self._rows(walk(rng, 900, isbot=False)))
        frozen = btlog.analyse(self._rows(walk(rng, 900, isbot=True, freeze=True)))
        self.assertGreater(frozen[("speed", "still_pct")], calm[("speed", "still_pct")] * 2)

    def test_instant_speed_changes_are_caught(self):
        # bots that teleport between still and full speed: no human ramps like that
        rng = random.Random(13)
        calm = btlog.analyse(self._rows(walk(rng, 900, isbot=False)))
        jumpy = btlog.analyse(self._rows(walk(rng, 900, isbot=True, instant=True)))
        self.assertGreater(jumpy[("speed", "zero_jump_pct")], calm[("speed", "zero_jump_pct")])
        self.assertGreater(jumpy[("speed", "burst_stop_pct")], calm[("speed", "burst_stop_pct")])

    def test_speed_uses_positions_not_reported_velocity(self):
        """The human side can only be measured from positions, so the bots must be
        too, or the metric reports a 6x difference that is pure measurement."""
        rng = random.Random(21)
        rows = self._rows(walk(rng, 400, isbot=True))
        # same positions, but claim a perfectly smooth velocity field
        for r in rows:
            r["vx"] = r["vy"] = r["vz"] = 150.0
        v = btlog.analyse(rows)
        with_engine_velocity = v[("speed", "p50")]
        self.assertGreater(with_engine_velocity, 100,
                           "positions drive the metric, not the reported velocity")
        self.assertLess(with_engine_velocity, 400)

    def test_constant_motion_reads_as_constant_speed(self):
        rows = []
        x = 0.0
        for i in range(200):
            x += 150 * btlog.DT
            rows.append(bt_iso(i * btlog.DT, 0, "p", 1, x, 0, 0, 150, 0, 0, 0, 90))
        v = btlog.analyse(self._rows(rows))
        self.assertAlmostEqual(v[("speed", "p50")], 150, delta=2)
        self.assertLess(v[("speed", "accel_p50")], 1.0)

    def test_firing_rate_is_measured_from_own_shots(self):
        # bots: since_fire only; the humans' CSV derives the same thing from the fire bit
        rng = random.Random(31)
        rows = self._rows(walk(rng, 600, isbot=True, fire=True))
        v = btlog.analyse(rows)
        self.assertIn(("fire", "recent_1s_pct"), v, "telemetry carries the fire recency")
        self.assertTrue(0 <= v[("fire", "recent_1s_pct")] <= 100)

    def test_old_logs_without_the_fire_column_report_no_fire_metrics(self):
        rng = random.Random(32)
        rows = self._rows(walk(rng, 400, isbot=True))
        for r in rows:
            r["since_fire"] = None
        v = btlog.analyse(rows)
        self.assertNotIn(("fire", "recent_1s_pct"), v)
        self.assertIn(("speed", "p50"), v)

    def test_pitch_wraps(self):
        self.assertAlmostEqual(btlog.angle_delta(359, 1), 2)
        self.assertAlmostEqual(btlog.angle_delta(1, 359), -2)
        self.assertAlmostEqual(btlog.angle_delta(10, 350), -20)


class CsvSource(unittest.TestCase):
    def _csv(self, d, humans=1, bots=0, rows=900, rate_ms=40):
        path = os.path.join(d, "demo0000.players.csv")
        meta = {"names": {str(i): {"name": f"P{i}"} for i in range(humans + bots)},
                "maps": [], "serverCommands": [], "snapshots": {}}
        with open(path, "w") as f:
            f.write(HDR + "\n")
            t, x = 0, 0.0
            for i in range(rows):
                t += rate_ms
                x += 4.0
                for c in range(humans + bots):
                    ef = 0x40000 if i % 10 == 0 else 0  # ADS
                    f.write(f"{t},{c},{0},{x:.0f},{-2200 + c * 10:.0f},0,-5,{i * 2 % 360},"
                            f"{ef},usp_mp,1022,0,0,0,0\n")
        with open(os.path.join(d, "demo0000.meta.json"), "w") as f:
            import json
            json.dump(meta, f)
        return os.path.join(d, "demo0000")

    def test_velocity_from_finite_differences_at_telemetry_rate(self):
        d = tempfile.mkdtemp()
        base = self._csv(d, humans=1, rows=900, rate_ms=40)
        rows = btlog.csv_samples(base, "humans")
        self.assertGreater(len(rows), 150)
        spd = [(r["vx"] ** 2 + r["vy"] ** 2) ** .5 for r in rows]
        self.assertAlmostEqual(sum(spd) / len(spd), 100, delta=6)  # 4u / 40ms = 100u/s
        gaps = [b["t"] - a["t"] for a, b in zip(rows, rows[1:])]
        self.assertGreaterEqual(min(gaps), btlog.CSV_DT * .8, "decimated to 5 Hz")

    def test_resolve_csv_accepts_base_or_file(self):
        d = tempfile.mkdtemp()
        base = self._csv(d, humans=1, rows=10)
        self.assertEqual(btlog.resolve_csv(base)[0], base + ".players.csv")
        self.assertEqual(btlog.resolve_csv(base + ".players.csv")[0], base + ".players.csv")
        self.assertEqual(btlog.resolve_csv(base + ".csv")[0], base + ".csv")


class EndToEnd(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.d = tempfile.mkdtemp()
        rng = random.Random(1234)
        cls.humans = []
        for i in range(4):
            p = write_log(os.path.join(cls.d, f"h{i}.log"),
                          walk(rng, 1400, isbot=False, human_params={"yaw": 30 * i},
                               player=i, name=f"Human{i}"))
            cls.humans.append(p)

    def _bots(self, tag, rng_seed=99, **kw):
        rng = random.Random(rng_seed)
        lines = []
        for i in range(4):
            lines += walk(rng, 1400, isbot=True, player=i, name=f"Bot{i}", **kw)
        return write_log(os.path.join(self.d, f"{tag}.log"), lines)

    def _run(self, bot_log, tmp):
        buf = __import__("io").StringIO()
        import contextlib
        with contextlib.redirect_stdout(buf):
            rc = btlog.main(["--humans", *self.humans, "--bots", bot_log,
                             "--min-minutes", "1", "--sessions",
                             "--scores-dir", tmp])
        return rc, buf.getvalue()

    def test_null_bots_look_human(self):
        rc, out = self._run(self._bots("null"), os.path.join(self.d, "s1"))  # same generator
        self.assertEqual(rc, 0, out)
        self.assertIn("OVERALL", out)
        auc = [l for l in out.splitlines() if "detector   AUC" in l]
        self.assertTrue(auc, out)
        # human-like movement with a wider turn distribution: not trivially caught
        self.assertLess(_num(auc[0]), .9, out)

    def test_planted_snap_is_caught(self):
        rc, out = self._run(self._bots("snap", snap=True), os.path.join(self.d, "s2"))
        self.assertEqual(rc, 0, out)
        self.assertIn("yaw snap", out, "the planted tell is named in the report")
        self.assertGreater(_num([l for l in out.splitlines() if "detector   AUC" in l][0]), .5)

    def test_saves_and_diffs_a_run(self):
        import scorecmp
        tmp = os.path.join(self.d, "s3")
        before = len(scorecmp.list_runs(tmp))
        self._run(self._bots("d1"), tmp)
        self.assertEqual(len(scorecmp.list_runs(tmp)), 0, "no --save, no run written")
        buf = __import__("io").StringIO()
        import contextlib
        with contextlib.redirect_stdout(buf):
            btlog.main(["--humans", *self.humans, "--bots", self._bots("d2"),
                        "--min-minutes", "1", "--save", "one", "--scores-dir", tmp])
        self.assertEqual(len(scorecmp.list_runs(tmp)), before + 1)
        with contextlib.redirect_stdout(buf):
            btlog.main(["--humans", *self.humans, "--bots", self._bots("d3", snap=True),
                        "--min-minutes", "1", "--save", "two", "--diff",
                        "--scores-dir", tmp])
        rec = scorecmp.load_run(scorecmp.list_runs(tmp)[-1])
        self.assertEqual(rec["run"]["map"], "telemetry")
        self.assertEqual(rec["run"]["label"], "two")
        self.assertIn("metrics", rec)
        self.assertGreater(len(rec["metrics"]), 20)


class Guards(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        rng = random.Random(31)
        self.humans = [write_log(os.path.join(self.d, f"h{i}.log"),
                                 walk(rng, 1400, isbot=False, player=i, name=f"H{i}"))
                       for i in range(4)]
        self.bots4 = [write_log(os.path.join(self.d, f"b{i}.log"),
                                walk(rng, 1400, isbot=True, player=i, name=f"B{i}"))
                      for i in range(4)]

    def test_refuses_when_a_side_is_too_thin(self):
        rng = random.Random(32)
        one = write_log(os.path.join(self.d, "one.log"),
                        walk(rng, 1400, isbot=True, name="Solo"))
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            rc = btlog.main(["--humans", *self.humans, "--bots", one])
        self.assertEqual(rc, 2, "a 1-session side must not produce a report")
        self.assertIn("not enough sessions", buf.getvalue())

    def test_diff_picks_a_run_from_the_same_source(self):
        import scorecmp
        scores = os.path.join(self.d, "scores")
        # a demo-source run is present but must not be the diff target
        demo = {"run": {"schema": 1, "label": "demo-run", "map": "mp_backlot",
                        "source": "demo snapshots", "humans": ["x"], "bots": ["y"],
                        "min_minutes": 1.0, "ignore": [], "sample": {}, "noise_floor": .3,
                        "when": "2026-10-01T00:00:00+00:00"},
                "overall": 50, "auc": 1.0, "flagged": {}, "sections": {}, "metrics": {},
                "sessions": []}
        scorecmp.save_run(demo, scores)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            btlog.main(["--humans", *self.humans, "--bots", *self.bots4,
                        "--min-minutes", "1", "--save", "tele1", "--diff",
                        "--scores-dir", scores])
        out = buf.getvalue()
        self.assertIn("tele1", out)
        self.assertIn("no previous", out, "the demo run is a different source")
        # second telemetry run: now it has something comparable to diff against
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            btlog.main(["--humans", *self.humans, "--bots", *self.bots4,
                        "--min-minutes", "1", "--save", "tele2", "--diff",
                        "--scores-dir", scores])
        out = buf.getvalue()
        self.assertIn("A  tele1", out)
        self.assertNotIn("demo-run", out.split("METRICS")[0].split("bot demos")[0])


def _num(line):
    """First float after 'AUC' in a console line."""
    tail = line.split("AUC")[1]
    for tok in tail.replace("(", " ").replace(")", " ").split():
        try:
            return float(tok)
        except ValueError:
            continue
    raise AssertionError(f"no number in {line!r}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
