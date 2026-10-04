#!/usr/bin/env python3
"""
Run history for tools/awarescore.py: save a scored run, list runs, diff two runs.

A run file is a trimmed awarescore result plus a provenance header, so the
history says what was scored and which code produced the demos:

  scores/20260927-0200-baseline.json
  {
    "run": {"schema":1, "label":"baseline", "when":"2026-09-27T02:00:11+01:00",
            "tool":"awarescore", "map":"mp_backlot",
            "humans":["output/demos/demo0000"], "bots":["output/demos/ours_1"],
            "min_minutes":1.0, "ignore":["social.ping*"],
            "sample":{"human_sessions":24,...}, "noise_floor":0.29,
            "scored_with_git":"223d684", "scored_with_git_dirty":true, "argv":"..."},
    "overall":41.2, "auc":1.0, "flagged":{...}, "sections":{...},
    "metrics":{"move.crouch %":{"ks":..,"p":..,"h_p50":..,"b_p50":..,...}},
    "tells":[...], "sessions":[...]
  }

Raw per-session value arrays and the `tells` list are dropped: they are
projections of `metrics` (re-derivable from the demos, and ~45 KB per run), so
the tracked history stays small and has one source of truth.

Diffs are only meaningful against the SAME human baseline (KS is measured
against the humans passed on the command line), so `diff` warns loudly when the
human set, map or session filters changed. Per-metric deltas below the larger
of the two runs' KS noise floors are reported as "within noise" and excluded
from the better/worse tally.

Usage:
  tools/scorecmp.py ls [DIR]
  tools/scorecmp.py diff [A] [B] [--min-delta 0.05] [--fail-new-tells]
  tools/scorecmp.py show RUN
  (awarescore.py --save LABEL [--note TEXT] writes runs; --diff prints the delta
   vs the previous run)

The recorded commit is the tool's checkout at scoring time, NOT the build that
produced the bots in the demos -- that is what --note is for.
"""
import argparse
import bisect
import datetime
import json
import math
import os
import random
import re
import subprocess
import sys

SCHEMA = 1
DEFAULT_DIR = "scores"
# fields kept per metric when saving (everything else is re-derived from demos)
KEEP = ("label", "section", "ks", "p", "q", "ignored", "score", "in_range", "spread", "ovl",
        # per-session values: ~13 human + ~90 bot floats per metric (~30 KB a run),
        # kept so a diff can bootstrap the difference between two pools
        "human", "bots",
        "h_n", "h_p10", "h_p50", "h_p90", "b_n", "b_p10", "b_p50", "b_p90",
        "b_p50_rank", "ci_lo", "ci_hi", "hself_med", "hself_max", "hself_demos",
        "bdemo_min", "bdemo_med", "bdemo_max", "bdemo_demos")


def clean(v):
	"""JSON has no NaN/Inf; js_div-style spans also produce NaN (zero IQR)."""
	if isinstance(v, float) and (math.isnan(v) or math.isinf(v)):
		return None
	return v


def slug(s):
	s = re.sub(r"[^A-Za-z0-9_.-]+", "-", (s or "run").strip()).strip("-")
	return s or "run"


def git_stamp():
	"""State of the tool's checkout when the run was scored. This is NOT the build
	that produced the bots in the demos -- record that with awarescore --note."""
	def git(*a):
		try:
			return subprocess.run(["git", *a], capture_output=True, text=True,
								  timeout=10).stdout.strip()
		except (OSError, subprocess.SubprocessError):
			return None
	head = git("rev-parse", "--short", "HEAD")
	if not head:
		return None
	return {"scored_with_git": head,
			"scored_with_git_dirty": bool(git("status", "--porcelain"))}


def run_record(res, prov, label="run", when=None):
	"""Trim an awarescore result into a storable run file."""
	now = datetime.datetime.now().astimezone()
	when = when or now.isoformat(timespec="seconds")
	head = {"schema": SCHEMA, "tool": "awarescore", "label": slug(label), "when": when,
			"map": res.get("map"), "humans": list(prov["humans"]), "bots": list(prov["bots"]),
			"min_minutes": prov.get("min_minutes"), "settle": prov.get("settle"),
			"ignore": list(prov.get("ignore") or ()),
			"note": prov.get("note"), "sample": res.get("sample", {}),
			"noise_floor": res.get("noise_floor"), "source": res.get("source"),
			"argv": prov.get("argv")}
	head.update(git_stamp() or {})
	return {
		"run": head,
		"overall": res.get("overall"), "auc": res.get("auc"),
		"auc_cv": res.get("auc_cv"), "auc_cv_folds": res.get("auc_cv_folds"),
		"flagged": res.get("flagged", {}), "flagged_cv": res.get("flagged_cv", {}),
		"fdr": res.get("fdr", {}), "resolution": res.get("resolution", {}),
		"bootstrap_reps": res.get("bootstrap_reps"),
		"sections": res.get("sections", {}),
		"metrics": {k: {f: clean(v[f]) for f in KEEP if f in v}
					for k, v in res.get("metrics", {}).items()},
		"sessions": res.get("sessions", []),
	}


def _stamp(when):
	"""YYYYMMDDhhmmss from an ISO timestamp; sorts lexically."""
	return re.sub(r"[^0-9]", "", when)[:14]


def next_run_path(rec, scores_dir=DEFAULT_DIR):
	"""Name a run so files sort by save order, even inside the same second."""
	stamp, label = _stamp(rec["run"]["when"]), rec["run"]["label"]
	seq = 1
	if os.path.isdir(scores_dir):
		seq += sum(1 for f in os.listdir(scores_dir) if f.startswith(f"{stamp}."))
	return os.path.join(scores_dir, f"{stamp}.{seq:02d}-{label}.json")


def save_run(rec, scores_dir=DEFAULT_DIR, path=None):
	os.makedirs(scores_dir, exist_ok=True)
	path = path or next_run_path(rec, scores_dir)
	with open(path, "w") as f:
		json.dump(rec, f, indent=1)
	return path


def load_run(path):
	with open(path) as f:
		rec = json.load(f)
	if rec.get("run", {}).get("schema") != SCHEMA:
		raise SystemExit(f"{path}: unsupported run schema {rec.get('run', {}).get('schema')}")
	return rec


def list_runs(scores_dir=DEFAULT_DIR):
	"""Run files, oldest first (filenames start with a sortable timestamp)."""
	if not os.path.isdir(scores_dir):
		return []
	return [os.path.join(scores_dir, f) for f in sorted(os.listdir(scores_dir))
			if f.endswith(".json")]


def resolve(name, scores_dir=DEFAULT_DIR, latest=False):
	"""Accept a path, a filename prefix, or a run label.

	With latest=True, a label that matches several runs (the same pool re-scored
	after a scoring change) resolves to the newest one instead of erroring.
	"""
	if os.path.exists(name):
		return name
	hits = [p for p in list_runs(scores_dir) if os.path.basename(p).startswith(name)]
	if not hits:  # fall back to the label stored inside each run
		hits = [p for p in list_runs(scores_dir) if load_run(p)["run"].get("label") == name]
	if not hits:
		hits = [p for p in list_runs(scores_dir)
		        if str(load_run(p)["run"].get("label", "")).startswith(name)]
	if latest and len(hits) > 1:
		return hits[-1]
	if len(hits) == 1:
		return hits[0]
	if not hits:
		raise SystemExit(f"no run matches {name!r} in {scores_dir}/")
	raise SystemExit(f"{name!r} matches {len(hits)} runs: "
	                 + ", ".join(load_run(h)["run"].get("label", "?") for h in hits[:6]))


def pct_diff(a, b, w=8, prec=2, suffix=""):
	if a is None or b is None:
		return f"{'n/a':>7s}"
	return f"{a:{w}.{prec}f} -> {b:.{prec}f}{suffix} ({b - a:+.{prec}f})"


def _noise(rec):
	return rec["run"].get("noise_floor") or 0.0


def _sig(rec, metric):
	"""Significant after FDR control; falls back to raw p for runs without q.

	Ignored metrics (see run.ignore) are never significant: they are excluded
	from scores on purpose, so a diff must not raise them as new tells.
	"""
	m = rec["metrics"].get(metric)
	if not m or m.get("ignored"):
		return False
	q = m.get("q")
	return (q if q is not None else m.get("p") or 1.0) < .05


def common_overall(a, b):
	"""Mean score over the metrics BOTH runs scored, plus that count.

	Two runs with different metric sets (an older build without a telemetry
	column, telemetry vs demo source, a metric that lost its data) have OVERALL
	numbers that average over different populations, so their difference means
	nothing. Scoring both on the intersection is the only comparable figure.
	"""
	common = [k for k in a["metrics"]
	          if k in b["metrics"]
	          and not a["metrics"][k].get("ignored") and not b["metrics"][k].get("ignored")
	          and a["metrics"][k].get("ks") is not None
	          and b["metrics"][k].get("ks") is not None]
	if not common:
		return None, None, 0
	sa = sum(100 * (1 - a["metrics"][k]["ks"]) for k in common) / len(common)
	sb = sum(100 * (1 - b["metrics"][k]["ks"]) for k in common) / len(common)
	return sa, sb, len(common)


def _indistinct(rec):
	ps = [(m.get("q") if m.get("q") is not None else m.get("p") or 1.0)
	      for m in rec["metrics"].values()]
	return 100 * sum(p >= .05 for p in ps) / len(ps) if ps else float("nan")


def diff(a, b, min_delta=.05):
	"""Print A -> B. Bot scores rising is an improvement. Returns new-tell count."""
	ha, hb = a["run"], b["run"]
	print(f"A  {ha['label']}  {ha['when']}  scored with {ha.get('scored_with_git', '?')}"
	      f"{' (dirty tree)' if ha.get('scored_with_git_dirty') else ''}")
	print(f"B  {hb['label']}  {hb['when']}  scored with {hb.get('scored_with_git', '?')}"
	      f"{' (dirty tree)' if hb.get('scored_with_git_dirty') else ''}")
	for side in ("A", "B"):
		note = (ha if side == "A" else hb).get("note")
		if note:
			print(f"   {side} note: {note}")
	if ha.get("map") != hb.get("map"):
		print(f"!! different maps scored: {ha.get('map')} vs {hb.get('map')}")
	same_source = ha.get("source") == hb.get("source")
	if not same_source:
		# the metric sets are not the same universe (demo snapshots vs server-side
		# telemetry), so every metric delta below would be nonsense
		print(f"!! different data sources: {ha.get('source') or 'demo snapshots'} vs "
		      f"{hb.get('source') or 'demo snapshots'} -- metric deltas are not comparable")
		print("   (only the headline numbers are; rerun one side from the same source)")
	if set(ha.get("humans") or ()) != set(hb.get("humans") or ()):
		print("!! HUMAN BASELINE CHANGED: " + ", ".join(
			sorted(set(hb.get("humans") or ()) - set(ha.get("humans") or ())) or ["-"]) + " added, "
			+ ", ".join(sorted(set(ha.get("humans") or ()) - set(hb.get("humans") or ())) or ["-"])
			+ " removed -- KS is measured against these demos, so metric deltas "
			  "compare different baselines and only their direction is meaningful")
	if set(ha.get("bots") or ()) != set(hb.get("bots") or ()):
		print(f"   bot demos: {', '.join(ha.get('bots') or ()) or '-'} -> "
		      f"{', '.join(hb.get('bots') or ()) or '-'}")
	for k in ("min_minutes", "settle"):
		if ha.get(k) != hb.get(k):
			print(f"!! {k} changed: {ha.get(k)} -> {hb.get(k)}")
	if ha.get("ignore") != hb.get("ignore"):
		print(f"!! ignored metrics changed: {ha.get('ignore')} -> {hb.get('ignore')}")
	sa, sb = ha.get("sample", {}), hb.get("sample", {})
	if sa != sb:
		print(f"   sample: " + ", ".join(f"{k} {sa.get(k)} -> {sb.get(k)}"
		                                 for k in sorted(set(sa) | set(sb))))

	fa, fb = a.get("flagged", {}), b.get("flagged", {})
	print(f"\n   {'metric':24s} {'A':>14s} -> {'B':>14s}   delta")
	for label, va, vb, prec in (("overall /100", a.get("overall"), b.get("overall"), 1),
	                            ("detector AUC", a.get("auc"), b.get("auc"), 3),
	                            ("detector AUC, leave-one-match-out", a.get("auc_cv"),
	                             b.get("auc_cv"), 3),
	                            ("indistinct %", _indistinct(a), _indistinct(b), 0)):
		sa = "n/a" if va is None else f"{va:.{prec}f}"
		sb = "n/a" if vb is None else f"{vb:.{prec}f}"
		d = (vb - va) if (va is not None and vb is not None) else None
		print(f"   {label:24s} {sa:>14s} -> {sb:>14s}   {'' if d is None else f'{d:+.{prec}f}'}")
	ca, cb, ncommon = common_overall(a, b)
	only_a = len(set(a["metrics"]) - set(b["metrics"]))
	only_b = len(set(b["metrics"]) - set(a["metrics"]))
	if ca is not None and set(a["metrics"]) != set(b["metrics"]):
		print(f"   {'overall, common metrics':24s} {ca:>14.1f} -> {cb:>14.1f}   {cb - ca:+5.1f}"
		      f"   ({ncommon} metrics both scored; A-only {only_a}, B-only {only_b})")
		print("   ^ the only OVERALL pair worth comparing when the metric sets differ")
	if fa.get("caught") is not None or fb.get("caught") is not None:
		sa = f"{fa.get('caught', '?')}/{fa.get('bot_sessions', '?')}"
		sb = f"{fb.get('caught', '?')}/{fb.get('bot_sessions', '?')}"
		ca, cb = fa.get("caught"), fb.get("caught")
		print(f"   {'flagged bots @10% FA':24s} {sa:>14s} -> {sb:>14s}   "
		      f"{'' if ca is None or cb is None else f'{cb - ca:+d}'}")
	print(f"   KS noise floor: {_noise(a):.2f} -> {_noise(b):.2f}")

	if not same_source:
		print("\nSECTIONS: not comparable across data sources")
		print("METRICS MOVED: not comparable across data sources")
		return 0
	secs = sorted(set(a["sections"]) | set(b["sections"]),
	              key=lambda s: -abs((b["sections"].get(s) or 0) - (a["sections"].get(s) or 0)))
	if secs:
		print("\nSECTIONS (/100, higher = closer to humans)")
		for s in secs:
			va, vb = a["sections"].get(s), b["sections"].get(s)
			d = None if va is None or vb is None else vb - va
			print(f"  {s:10s} {'' if va is None else f'{va:5.1f}':>6s} -> "
			      f"{'' if vb is None else f'{vb:5.1f}':>6s}  {'' if d is None else f'{d:+5.1f}'}")

	names = sorted(set(a["metrics"]) | set(b["metrics"]))
	noise = max(_noise(a), _noise(b))
	rows, noise_only, one_side, rows_extra, verdict = [], [], [], {}, {}
	for name in names:
		ma, mb = a["metrics"].get(name), b["metrics"].get(name)
		if ma is None or mb is None:
			one_side.append(name)
			rows.append((float("inf"), name, ma, mb, None, "only in " + ("B" if ma is None else "A")))
			continue
		dks = (mb.get("ks") or 0) - (ma.get("ks") or 0)
		if abs(dks) < min_delta:
			continue
		new, fixed = (not _sig(a, name) and _sig(b, name), _sig(a, name) and not _sig(b, name))
		if mb.get("ignored"):
			note = "ignored metric"
		elif new:
			note = "NEW TELL"
		elif fixed:
			note = "RESOLVED"
		elif not _sig(b, name):
			note = "n.s. (improving)" if dks < 0 else "n.s. (drifting)"
		else:
			note = "BETTER" if dks < 0 else "WORSE"
		# is the difference itself real? bootstrap both pools against the shared
		# human sample instead of judging it by one run's noise floor
		if dks is not None and ma.get("bots") and mb.get("bots") and (mb.get("human") or ma.get("human")):
			ci = ks_ci_delta(ma["bots"], mb["bots"], mb.get("human") or ma["human"])
			if ci:
				lo, hi, pneg = ci
				rows_extra[name] = (lo, hi, pneg)
				if lo < 0 < hi:
					note += " (diff spans 0)"
				elif hi < 0:
					note += " [95% CI below 0: real improvement]"
				else:
					note += " [95% CI above 0: real regression]"

		verdict[name] = "NEW TELL" if new else ("RESOLVED" if fixed else note)
		if abs(dks) < noise:
			noise_only.append(name)
		rows.append((abs(dks), name, ma, mb, dks, note))

	rows.sort(key=lambda r: (r[4] is None, -r[0]))  # coverage changes last
	if rows:
		print(f"\nMETRICS MOVED (|dKS| >= {min_delta})"
		      + (f"   [{len(noise_only)} within noise floor {noise:.2f}]" if noise_only else "")
		      + (f"   [{len(one_side)} only scored in one run]" if one_side else "")
		      + "   significance = BH q<.05 (raw p<.05 on older runs)")
		print(f"  {'metric':30s} {'dKS [95% CI]':>22s}  {'q':>13s}  {'bot p50':>17s}  "
		      f"{'in human band':>13s}  {'ovl':>11s}  note")
		for _d, name, ma, mb, dks, note in rows:
			ma = ma or {}
			mb = mb or {}
			qa = ma.get("q") if ma.get("q") is not None else ma.get("p")
			qb = mb.get("q") if mb.get("q") is not None else mb.get("p")
			p = f"{_fmt(ma.get('p'))}->{_fmt(mb.get('p'))}"
			q = f"{_fmt(qa)}->{_fmt(qb)}" + (f" (p {p})" if qa != mb.get("q") and qa is not None else "")
			bot = f"{_fmt(ma.get('b_p50'))}->{_fmt(mb.get('b_p50'))}"
			inr = f"{(ma.get('in_range') or 0):.0f}%->{(mb.get('in_range') or 0):.0f}%"
			ov = f"{_fmt(ma.get('ovl'))}->{_fmt(mb.get('ovl'))}"
			dk = "  n/a" if dks is None else f"{dks:+6.2f}"
			flag = " *" if dks is not None and abs(dks) < noise else ""
			print(f"  {name:30s} {dk}  {q:>13s}  {bot:>17s}  {inr:>13s}  {ov:>11s}  {note}{flag}")
		print("  (* delta below this run's KS noise floor: not a real movement)")
	else:
		print("\nMETRICS MOVED: none")

	# verdict[] holds the base label: the note may have had the CI text appended
	new_tells = [n for _d, n, _ma, _mb, _dks2, _note in rows if verdict.get(n) == "NEW TELL"]
	resolved = [n for _d, n, _ma, _mb, _dks2, _note in rows if verdict.get(n) == "RESOLVED"]
	better = [n for _d, n, _ma, _mb, dks, note in rows if dks is not None and dks < 0
	          and abs(dks) >= noise]
	worse = [n for _d, n, _ma, _mb, dks, note in rows if dks is not None and dks > 0
	         and abs(dks) >= noise]
	print(f"\n  {len(better)} better, {len(worse)} worse ({len(new_tells)} new tells), "
	      f"{len(resolved)} resolved")
	if rows_extra:
		solid = sum(1 for lo, hi, _p in rows_extra.values() if not (lo < 0 < hi))
		print(f"  {solid}/{len(rows_extra)} of those movements have a 95% bootstrap "
		      f"interval that excludes zero -- the rest are sampling noise")
	for name in new_tells:
		print(f"  + new tell: {name}")
	for name in resolved:
		print(f"  - resolved: {name}")
	return len(new_tells)


def _fmt(v):
	return "n/a" if v is None else f"{v:.4g}"


def ks_dist(a, b):
	"""Two-sample KS statistic, no dependencies (the same definition awarescore uses)."""
	if not a or not b:
		return float("nan")
	xs, ys = sorted(a), sorted(b)
	n, m = len(xs), len(ys)
	i = j = 0
	d = 0.0
	while i < n and j < m:
		if xs[i] <= ys[j]:
			i += 1
		else:
			j += 1
		d = max(d, abs(i / n - j / m))
	return d


def ks_ci_delta(a_vals, b_vals, h_vals, reps=200, seed=7):
	"""Bootstrap CI on the KS difference between two bot pools vs one human pool.

	delta = KS(pool_B vs humans) - KS(pool_A vs humans). Each pool's sessions are
	resampled independently while the human sample is held fixed, which is the
	question actually being asked when diffing two runs: is the *difference*
	bigger than the noise of both pools together? Returns (lo, hi, P(delta < 0)).
	Deterministic, so re-running a diff gives the same interval.
	"""
	na, nb, nh = len(a_vals), len(b_vals), len(h_vals)
	if na < 3 or nb < 3 or nh < 3:
		return None
	rng = random.Random(seed)
	deltas = []
	for _ in range(reps):
		sa = [a_vals[rng.randrange(na)] for _ in range(na)]
		sb = [b_vals[rng.randrange(nb)] for _ in range(nb)]
		deltas.append(ks_dist(sb, h_vals) - ks_dist(sa, h_vals))
	deltas.sort()
	lo = deltas[int(.05 * reps)]
	hi = deltas[min(reps - 1, int(.95 * reps))]
	return lo, hi, sum(d < 0 for d in deltas) / reps


def cmd_ls(args):
	runs = list_runs(args.dir)
	if not runs:
		print(f"no runs in {args.dir}/ -- score one with: tools/awarescore.py --humans ... "
		      f"--bots ... --save LABEL")
		return 0
	print(f"  {'run':34s} {'when':19s} {'overall':>8s} {'AUC':>6s} {'sessions':>10s}  scored with")
	for p in runs:
		rec = load_run(p)
		h = rec["run"]
		s = h.get("sample", {})
		print(f"  {os.path.basename(p)[:-5]:34s} {h['when'][:19]:19s} "
		      f"{rec.get('overall') or 0:8.1f} {(rec.get('auc') or 0):6.3f} "
		      f"{s.get('bot_sessions', 0):5d} bot  {h.get('scored_with_git', '?')}"
		      f"{' (dirty)' if h.get('scored_with_git_dirty') else ''}")
	return 0


def cmd_show(args):
	rec = load_run(resolve(args.run, args.dir))
	h = rec["run"]
	print(json.dumps(h, indent=1))
	print(f"overall {rec.get('overall', 0):.1f}  AUC {rec.get('auc') or 0:.3f}  "
	      f"flagged {rec.get('flagged', {}).get('caught', '?')}"
	      f"/{rec.get('flagged', {}).get('bot_sessions', '?')} bot sessions at 10% FA")
	print("sections " + "  ".join(f"{k} {v:.1f}" for k, v in rec.get("sections", {}).items()))
	print(f"metrics: {len(rec['metrics'])}   sessions: {len(rec.get('sessions', []))}")
	top = sorted(rec["metrics"].items(), key=lambda kv: -(kv[1].get("ks") or 0))[:15]
	for name, m in top:
		print(f"  {m['ks']:.2f}{'*' if (m.get('p') or 1) < .05 else ' '} {name:28s} "
		      f"{(m.get('label') or ''):30s} bots {_fmt(m.get('b_p50'))} vs "
		      f"{_fmt(m.get('h_p50'))}")
	return 0


def cmd_diff(args):
	runs = list_runs(args.dir)
	if args.a and args.b:
		a = load_run(resolve(args.a, args.dir, args.latest))
		b = load_run(resolve(args.b, args.dir, args.latest))
	else:
		if len(runs) < 2:
			print(f"need two runs in {args.dir}/ to diff (have {len(runs)}) -- "
			      f"save more with awarescore.py --save LABEL")
			return 2
		a, b = load_run(runs[-2]), load_run(runs[-1])
		print(f"(no run named: diffing the two newest in {args.dir}/)")
	n = diff(a, b, args.min_delta)
	return 1 if (n and args.fail_new_tells) else 0


def main(argv=None):
	ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
	ap.add_argument("--dir", default=DEFAULT_DIR, help=f"run directory (default {DEFAULT_DIR}/)")
	sub = ap.add_subparsers(dest="cmd", required=True)
	sub.add_parser("ls", help="list stored runs")
	d = sub.add_parser("diff", help="diff two runs (default: the two newest)")
	d.add_argument("a", nargs="?", help="run name/path (prefix ok)")
	d.add_argument("b", nargs="?", help="run name/path (prefix ok)")
	d.add_argument("--min-delta", type=float, default=.05, help="ignore |dKS| below this")
	d.add_argument("--fail-new-tells", action="store_true", help="exit 1 if any tell became significant")
	d.add_argument("--latest", action="store_true",
				   help="when a name matches several runs, use the newest")
	s = sub.add_parser("show", help="print one run's header + worst tells")
	s.add_argument("run")
	args = ap.parse_args(argv)
	return {"ls": cmd_ls, "diff": cmd_diff, "show": cmd_show}[args.cmd](args)


if __name__ == "__main__":
	sys.exit(main())
