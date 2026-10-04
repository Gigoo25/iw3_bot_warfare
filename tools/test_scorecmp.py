#!/usr/bin/env python3
"""Tests for tools/scorecmp.py (run history, trimming, diff reporting)."""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import scorecmp  # noqa: E402


def metric(ks, p, b_p50=0.0, in_range=50.0, name="move.crouch %", label="label"):
    return {"label": label, "section": name.split(".")[0], "ks": ks, "p": p,
            "score": 100 * (1 - ks), "in_range": in_range, "spread": 1.0,
            "h_n": 10, "h_p10": 0.0, "h_p50": 1.0, "h_p90": 2.0,
            "b_n": 10, "b_p10": 0.0, "b_p50": b_p50, "b_p90": 2.0}


def record(label, metrics, humans=("h0",), bots=("b0",), when="2026-09-27T02:00:00+01:00",
           noise=.30, overall=50.0, auc=1.0, source=None, **head):
    h = {"schema": 1, "tool": "awarescore", "label": label, "when": when, "map": "mp_test",
         "humans": list(humans), "bots": list(bots), "min_minutes": 1.0, "ignore": [],
         "sample": {"human_sessions": 10, "bot_sessions": 10}, "noise_floor": noise,
         "scored_with_git": "abc1234", "scored_with_git_dirty": False,
         "argv": "awarescore.py", "note": None, "source": source}
    h.update(head)
    return {"run": h, "overall": overall, "auc": auc, "flagged": {"caught": 5, "bot_sessions": 10},
            "sections": {"move": 60.0, "aim": 40.0}, "metrics": metrics,
            "sessions": []}


def capture(fn, *a, **kw):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = fn(*a, **kw)
    return rc, buf.getvalue()


class Trim(unittest.TestCase):
    def test_raw_values_dropped_percentiles_kept(self):
        res = {"map": "mp_backlot", "overall": 42.0, "auc": .9, "noise_floor": .29,
               "sample": {"bot_sessions": 4}, "flagged": {"caught": 2},
               "sections": {"aim": 30.0}, "tells": [{"metric": "aim.x"}], "sessions": [],
               "metrics": {"aim.x": dict(metric(.4, .01, b_p50=3.0),
                                        human=[1.0, 2.0], bots=[3.0, 4.0])}}
        rec = scorecmp.run_record(res, {"humans": ["h"], "bots": ["b"], "min_minutes": 1.0,
                                        "ignore": [], "argv": "x"}, label="run 1/2")
        m = rec["metrics"]["aim.x"]
        # per-session arrays are kept now (a diff bootstraps the difference between
        # two pools), but the untrimmed copies are not: only one copy of each
        self.assertEqual(m["human"], [1.0, 2.0])
        self.assertEqual(m["bots"], [3.0, 4.0])
        self.assertNotIn("human_raw", m)
        self.assertEqual(m["b_p50"], 3.0)
        self.assertEqual(rec["run"]["label"], "run-1-2", "labels must be filename-safe")
        self.assertEqual(rec["run"]["humans"], ["h"])
        self.assertEqual(rec["run"]["map"], "mp_backlot")
        self.assertEqual(rec["run"]["sample"], {"bot_sessions": 4})

    def test_nan_becomes_null(self):
        res = {"map": "m", "metrics": {"aim.x": dict(metric(.4, .01), spread=float("nan"))}}
        rec = scorecmp.run_record(res, {"humans": ["h"], "bots": ["b"]})
        self.assertIsNone(rec["metrics"]["aim.x"]["spread"])
        json.dumps(rec)  # strict JSON: no NaN


class Store(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def test_save_order_within_same_second(self):
        same = "2026-09-27T02:00:00+01:00"
        a = record("zebra", {"aim.x": metric(.2, .2)}, when=same)
        b = record("alpha", {"aim.x": metric(.3, .3)}, when=same)
        pa = scorecmp.save_run(a, self.d)
        pb = scorecmp.save_run(b, self.d)
        self.assertNotEqual(pa, pb)
        self.assertEqual(scorecmp.list_runs(self.d), [pa, pb], "listing is oldest first")

    def test_later_timestamp_sorts_last(self):
        pa = scorecmp.save_run(record("a", {"aim.x": metric(.2, .2)},
                                      when="2026-09-27T02:00:00+01:00"), self.d)
        pb = scorecmp.save_run(record("b", {"aim.x": metric(.2, .2)},
                                      when="2026-09-28T09:15:00+01:00"), self.d)
        self.assertEqual(scorecmp.list_runs(self.d), [pa, pb])

    def test_roundtrip_and_schema_guard(self):
        rec = record("x", {"aim.x": metric(.2, .2)})
        p = scorecmp.save_run(rec, self.d)
        self.assertEqual(scorecmp.load_run(p)["run"]["label"], "x")
        bad = os.path.join(self.d, "bad.json")
        with open(bad, "w") as f:
            json.dump({"run": {"schema": 99}}, f)
        with self.assertRaises(SystemExit):
            scorecmp.load_run(bad)

    def test_resolve_prefix_unique(self):
        p = scorecmp.save_run(record("baseline", {"aim.x": metric(.2, .2)},
                                     when="2026-09-27T02:00:00+01:00"), self.d)
        stamp = os.path.basename(p).split(".")[0]
        self.assertEqual(scorecmp.resolve(stamp, self.d), p)
        self.assertEqual(scorecmp.resolve(p, self.d), p)
        self.assertEqual(scorecmp.resolve("baseline", self.d), p, "labels resolve too")
        with self.assertRaises(SystemExit):
            scorecmp.resolve("nope", self.d)

    def test_resolve_ambiguous_label_lists_options(self):
        scorecmp.save_run(record("dup", {"aim.x": metric(.2, .2)},
                                 when="2026-09-27T02:00:00+01:00"), self.d)
        scorecmp.save_run(record("dup", {"aim.x": metric(.3, .3)},
                                 when="2026-09-28T02:00:00+01:00"), self.d)
        with self.assertRaises(SystemExit) as cm:
            scorecmp.resolve("dup", self.d)
        self.assertIn("matches 2 runs", str(cm.exception))


class CommonOverall(unittest.TestCase):
    """OVERALL is only comparable across runs over the metrics both scored."""

    def test_intersection_average(self):
        a = record("a", {"m1": metric(.2, .3), "m2": metric(.4, .3), "only_a": metric(.1, .3)})
        b = record("b", {"m1": metric(.6, .3), "m2": metric(.6, .3), "only_b": metric(.1, .3)})
        sa, sb, n = scorecmp.common_overall(a, b)
        self.assertEqual(n, 2)
        self.assertAlmostEqual(sa, 70.0)   # 80 and 60
        self.assertAlmostEqual(sb, 40.0)   # 40 and 40
        self.assertLess(sb, sa)

    def test_disjoint_metric_sets_give_nothing(self):
        a = record("a", {"telemetry.speed": metric(.2, .3)})
        b = record("b", {"move.speed_p50": metric(.2, .3)})
        self.assertEqual(scorecmp.common_overall(a, b), (None, None, 0))

    def test_ignored_metrics_excluded(self):
        a = record("a", {"m1": metric(.2, .3)})
        b = record("b", {"m1": metric(.6, .3)})
        b["metrics"]["m1"]["ignored"] = True
        self.assertEqual(scorecmp.common_overall(a, b), (None, None, 0))

    def test_row_is_printed_only_when_sets_differ(self):
        same = {"m1": metric(.2, .3)}
        a = record("a", dict(same))
        b = record("b", dict(same))
        _, out = capture(scorecmp.diff, a, b, 9.0)
        self.assertNotIn("common metrics", out)
        a2 = record("a", {"m1": metric(.2, .3), "extra": metric(.2, .3)})
        _, out = capture(scorecmp.diff, a2, b, 9.0)
        self.assertIn("common metrics", out)
        self.assertIn("A-only 1", out)


class Diff(unittest.TestCase):
    def test_resolved_tell_counted_once(self):
        a = record("planted", {"aim.pitch_zero": metric(.90, .001)})
        b = record("fixed", {"aim.pitch_zero": metric(.30, .600)})
        nnew, out = capture(scorecmp.diff, a, b)
        self.assertEqual(nnew, 0)
        self.assertIn("RESOLVED", out)
        self.assertIn("resolved: aim.pitch_zero", out)
        self.assertIn("0 worse", out)
        self.assertIn("1 resolved", out)

    def test_new_tell_returns_count(self):
        a = record("before", {"move.crouch %": metric(.20, .400)})
        b = record("after", {"move.crouch %": metric(.70, .001)})
        nnew, out = capture(scorecmp.diff, a, b)
        self.assertEqual(nnew, 1)
        self.assertIn("NEW TELL", out)
        self.assertIn("new tell: move.crouch %", out)

    def test_worse_while_significant(self):
        a = record("a", {"aim.jitter": metric(.50, .001, b_p50=1.0)})
        b = record("b", {"aim.jitter": metric(.80, .001, b_p50=2.0)})
        nnew, out = capture(scorecmp.diff, a, b)
        self.assertEqual(nnew, 0)
        self.assertIn("WORSE", out)
        self.assertIn("0 better, 1 worse", out)

    def test_small_delta_is_noise_not_worse(self):
        # |dKS| = 0.04 but the runs' KS noise floor is 0.30: not a real movement
        a = record("a", {"aim.jitter": metric(.50, .001)}, noise=.30)
        b = record("b", {"aim.jitter": metric(.54, .001)}, noise=.30)
        nnew, out = capture(scorecmp.diff, a, b, .05)
        self.assertIn("0 better, 0 worse", out)
        self.assertNotIn("WORSE", out)

    def test_min_delta_filters(self):
        a = record("a", {"aim.jitter": metric(.50, .400)})
        b = record("b", {"aim.jitter": metric(.54, .400)})
        _, out = capture(scorecmp.diff, a, b, .05)
        self.assertIn("METRICS MOVED: none", out)

    def test_human_baseline_change_warns(self):
        a = record("a", {"aim.jitter": metric(.5, .001)}, humans=("h0",))
        b = record("b", {"aim.jitter": metric(.5, .001)}, humans=("h0", "h1"))
        _, out = capture(scorecmp.diff, a, b)
        self.assertIn("HUMAN BASELINE CHANGED", out)
        self.assertIn("h1 added", out)

    def test_filter_change_warns(self):
        a = record("a", {"aim.jitter": metric(.5, .001)}, min_minutes=1.0)
        b = record("b", {"aim.jitter": metric(.5, .001)}, min_minutes=2.0)
        _, out = capture(scorecmp.diff, a, b)
        self.assertIn("min_minutes changed", out)

    def test_metric_only_in_one_run(self):
        a = record("a", {"aim.jitter": metric(.5, .001), "life.kd": metric(.4, .2)})
        b = record("b", {"aim.jitter": metric(.5, .001)})
        _, out = capture(scorecmp.diff, a, b)
        self.assertIn("only in A", out)

    def test_headline_deltas(self):
        a = record("a", {"aim.jitter": metric(.5, .001)}, overall=40.0, auc=.95)
        b = record("b", {"aim.jitter": metric(.5, .001)}, overall=55.0, auc=.90)
        _, out = capture(scorecmp.diff, a, b, 9.0)  # headline only
        self.assertIn("overall /100", out)
        self.assertIn("+15.0", out)
        self.assertIn("-0.050", out.replace("AUC", "AUC"))
        self.assertIn("SECTIONS", out)
        self.assertIn("KS noise floor", out)

    def test_cli_diff_needs_two_runs(self):
        d = tempfile.mkdtemp()
        rc, out = capture(scorecmp.main, ["--dir", d, "diff"])
        self.assertEqual(rc, 2)
        self.assertIn("need two runs", out)

    def test_cli_diff_defaults_to_newest_two(self):
        d = tempfile.mkdtemp()
        scorecmp.save_run(record("one", {"aim.x": metric(.9, .001)}, when="2026-09-27T02:00:00+01:00"), d)
        scorecmp.save_run(record("two", {"aim.x": metric(.2, .500)}, when="2026-09-28T02:00:00+01:00"), d)
        rc, out = capture(scorecmp.main, ["--dir", d, "diff"])
        self.assertEqual(rc, 0)
        self.assertIn("two newest", out)
        self.assertIn("resolved: aim.x", out)

    def test_cli_fail_new_tells(self):
        d = tempfile.mkdtemp()
        scorecmp.save_run(record("one", {"aim.x": metric(.2, .500)}, when="2026-09-27T02:00:00+01:00"), d)
        scorecmp.save_run(record("two", {"aim.x": metric(.9, .001)}, when="2026-09-28T02:00:00+01:00"), d)
        rc, _ = capture(scorecmp.main, ["--dir", d, "diff", "--fail-new-tells"])
        self.assertEqual(rc, 1)

    def test_note_is_printed_and_kept(self):
        a = record("a", {"aim.x": metric(.5, .001)}, note="demos from build A")
        b = record("b", {"aim.x": metric(.5, .001)}, note="demos from build B")
        self.assertEqual(a["run"]["note"], "demos from build A")
        _, out = capture(scorecmp.diff, a, b, 9.0)
        self.assertIn("A note: demos from build A", out)
        self.assertIn("B note: demos from build B", out)

    def test_cross_source_diff_refuses_metric_deltas(self):
        a = record("a", {"aim.x": metric(.5, .001)})
        b = record("b", {"aim.x": metric(.9, .001)}, source="telemetry")
        n, out = capture(scorecmp.diff, a, b, 9.0)
        self.assertIn("different data sources", out)
        self.assertIn("METRICS MOVED: not comparable", out)
        self.assertNotIn("WORSE", out)

    def test_difference_is_bootstrapped(self):
        """A diff must say whether the difference itself is real, not only whether
        it is bigger than one run's noise floor."""
        import random as _r
        rng = _r.Random(3)
        h = [rng.gauss(0, 1) for _ in range(40)]
        close = [rng.gauss(0.05, 1) for _ in range(60)]
        far = [rng.gauss(1.2, 1) for _ in range(60)]
        def rec_with(vals, label):
            r = record(label, {})
            r["metrics"] = {"aim.x": dict(metric(0.5, 0.2), human=h, bots=vals)}
            return r
        lo, hi, pneg = scorecmp.ks_ci_delta(far, close, h, reps=200)
        self.assertLess(hi, 0, "a real improvement must exclude zero")
        self.assertGreater(pneg, .95)
        lo2, hi2, pneg2 = scorecmp.ks_ci_delta(close, list(close), h, reps=200)
        self.assertTrue(lo2 < 0 < hi2, "identical pools must span zero")

    def test_same_source_diffs_normally(self):
        a = record("a", {"aim.x": metric(.5, .001)}, source="telemetry")
        b = record("b", {"aim.x": metric(.9, .001)}, source="telemetry")
        _, out = capture(scorecmp.diff, a, b)
        self.assertNotIn("different data sources", out)
        self.assertIn("WORSE", out)

    def test_bot_demo_change_is_shown(self):
        a = record("a", {"aim.x": metric(.5, .001)}, bots=("b0",))
        b = record("b", {"aim.x": metric(.5, .001)}, bots=("b0", "b1"))
        _, out = capture(scorecmp.diff, a, b, 9.0)
        self.assertIn("bot demos: b0 -> b0, b1", out)

    def test_cli_ls_and_show(self):
        d = tempfile.mkdtemp()
        rec = record("listed", {"aim.x": metric(.9, .001, name="aim.x", label="pitch zero")})
        p = scorecmp.save_run(rec, d)
        rc, out = capture(scorecmp.main, ["--dir", d, "ls"])
        self.assertEqual(rc, 0)
        self.assertIn("listed", out)
        rc, out = capture(scorecmp.main, ["--dir", d, "show", p])
        self.assertEqual(rc, 0)
        self.assertIn("abc1234", out)
        self.assertIn("aim.x", out)
        self.assertIn("pitch zero", out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
