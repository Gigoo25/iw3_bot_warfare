#!/usr/bin/env python3
"""
Learns the human movement state machine from demo exports and writes it as GSC
data for the bots (maps/mp/bots/_bot_motor_data.gsc).

States (20Hz demo samples, speed smoothed over 150ms, runs < 150ms merged):
  sprint, run, ads_walk, crouch_walk, still_stand, still_crouch, prone
For each state: dwell-time deciles (seconds) and next-state transition weights.

Context lifts (S&D): how much more/less often humans are in each state in a
512u area of a map, and at a time into the round, relative to their overall
share (x100, clamped 25..400). motorNext multiplies the transition weights by
them, so bots crouch/hold/sprint where and when people do, not just as often.

Profiles:
  sd      -> S&D demos (one-life)
  respawn -> TDM/DM/DOM demos (bots excluded by 0-ping/[BOT] detection)

Usage: tools/gen_motor_model.py --sd output/demos/demo0000 output/demos/demo0001 \
                                --respawn output/demos/demo0002
"""
import argparse
import collections
import csv
import json
import math
import os
import re
import statistics
import sys

sys.path.insert(0, os.path.dirname(__file__))
import demostats  # noqa: E402

AREA = 512
PHASES = (5, 15, 30, 60, 120, 1e9)  # seconds into the round (upper edges)
MIN_AREA = 600  # 20Hz samples (30s) before an area gets its own lifts
STATES = ["sprint", "run", "ads_walk", "crouch_walk", "still_stand", "still_crouch", "prone"]
OUT = "maps/mp/bots/_bot_motor_data.gsc"


def state(r, sp):
	ef = int(r["eflags"])
	if ef >> 3 & 1:
		return "prone"
	if sp < 25:
		return "still_crouch" if ef >> 2 & 1 else "still_stand"
	if ef >> 2 & 1:
		return "crouch_walk"
	if ef >> 18 & 1:
		return "ads_walk"
	return "sprint" if sp > 230 else "run"


def learn(bases):
	dwell = collections.defaultdict(list)
	trans = collections.defaultdict(collections.Counter)
	occ = collections.Counter()
	for base in bases:
		rows = list(csv.DictReader(open(base + ".players.csv")))
		meta = json.load(open(base + ".meta.json"))
		names = {k: re.sub(r"\^.", "", v["name"]) for k, v in meta["names"].items()}
		bots = demostats.bot_clients(meta, names)
		by = collections.defaultdict(list)
		for r in rows:
			by[r["client"]].append(r)
		for client, rs in by.items():
			if client in bots:
				continue
			rs.sort(key=lambda r: int(r["t"]))
			for seg in demostats.segments(rs):
				if len(seg) < 100:
					continue
				sp = [0.0] + [math.hypot(float(b["x"]) - float(a["x"]), float(b["y"]) - float(a["y"])) / 0.05 for a, b in zip(seg, seg[1:])]
				sp = [statistics.mean(sp[max(0, i - 1):i + 2]) for i in range(len(sp))]
				runs = []
				for s in (state(r, v) for r, v in zip(seg, sp)):
					if runs and runs[-1][0] == s:
						runs[-1][1] += 1
					else:
						runs.append([s, 1])
				merged = []
				for s, n in runs:
					if merged and (n < 3 or merged[-1][0] == s):
						merged[-1][1] += n
					else:
						merged.append([s, n])
				for i, (s, n) in enumerate(merged):
					occ[s] += n
					if 0 < i < len(merged) - 1:
						dwell[s].append(n * 0.05)
					if i + 1 < len(merged):
						trans[s][merged[i + 1][0]] += 1
	return occ, dwell, trans


def learn_context(bases):
	"""S&D state counts per (map, 512u area) and per round phase, humans only."""
	import bisect
	import awarescore as A
	import gen_map_model
	area = collections.defaultdict(collections.Counter)
	phase = collections.defaultdict(collections.Counter)
	for base in bases:
		meta = json.load(open(base + ".meta.json"))
		names = {k: A.clean_name(v["name"]) for k, v in meta["names"].items()}
		bots = demostats.bot_clients(meta, names)
		wins = gen_map_model.map_windows(meta)
		for mp in sorted({w[1] for w in wins if w[2] == "sd"}):
			by, snap = A.load_players(base + ".players.csv", A.make_inside(A.map_intervals(wins, mp)))
			starts = A.round_starts(snap)
			del snap
			for client, rs in by.items():
				if client in bots:
					continue
				for i in range(1, len(rs) - 1):
					a, b, c = rs[i - 1], rs[i], rs[i + 1]
					if c[A.T] - a[A.T] > 120:
						continue
					sp = math.hypot(c[A.X] - a[A.X], c[A.Y] - a[A.Y]) / ((c[A.T] - a[A.T]) / 1000)
					if sp > 600:
						continue
					st = state({"eflags": b[A.EF]}, sp)
					area[(mp, round(b[A.X] / AREA), round(b[A.Y] / AREA))][st] += 1
					k = bisect.bisect_right(starts, b[A.T]) - 1
					if k >= 0 and b[A.T] - starts[k] < 300000:
						phase[bisect.bisect_left(PHASES, (b[A.T] - starts[k]) / 1000)][st] += 1
	return area, phase


def lifts(counts, base):
	tot = sum(counts.values())
	btot = sum(base.values())
	out = []
	for s in STATES:
		p = (counts[s] + 2) / (tot + 2 * len(STATES))
		q = (base[s] + 2) / (btot + 2 * len(STATES))
		out.append(f"{s}:{max(25, min(400, round(100 * p / q)))}")
	return ",".join(out)


def gsc_context(name, area, phase):
	lines = []
	per_map = collections.defaultdict(collections.Counter)
	for (mp, _x, _y), c in area.items():
		per_map[mp].update(c)
	for (mp, x, y), c in sorted(area.items()):
		if sum(c.values()) >= MIN_AREA:
			lines.append(f'\t\tcase "{name}_area_{mp}_{x}_{y}": return "{lifts(c, per_map[mp])}";')
	allp = collections.Counter()
	for c in phase.values():
		allp.update(c)
	for k, c in sorted(phase.items()):
		lines.append(f'\t\tcase "{name}_phase_{k}": return "{lifts(c, allp)}";')
	return lines, len([1 for c in area.values() if sum(c.values()) >= MIN_AREA]), sorted(per_map)


def gsc_profile(name, occ, dwell, trans):
	lines = []
	total = sum(occ.values())
	for s in STATES:
		d = sorted(dwell[s]) or [0.5]
		deciles = [d[int(q / 10 * (len(d) - 1))] for q in range(1, 10)]
		t = trans[s]
		tt = sum(t.values()) or 1
		weights = ",".join(f"{k}:{max(1, round(1000 * v / tt))}" for k, v in t.most_common() if v)
		lines.append(f'\t\tcase "{name}_{s}_dwell": return "{",".join(f"{x:.2f}" for x in deciles)}";')
		lines.append(f'\t\tcase "{name}_{s}_next": return "{weights}";')
		lines.append(f'\t\tcase "{name}_{s}_share": return "{1000 * occ[s] / total:.0f}";')
	return lines


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--sd", nargs="+", required=True)
	ap.add_argument("--respawn", nargs="+", required=True)
	args = ap.parse_args()

	body = []
	summary = []
	for name, bases in (("sd", args.sd), ("respawn", args.respawn)):
		occ, dwell, trans = learn(bases)
		body += gsc_profile(name, occ, dwell, trans)
		if name == "sd":
			ctx, n_areas, maps = gsc_context(name, *learn_context(bases))
			body += ctx
			summary.append(f"sd context: {n_areas} areas ({AREA}u) on {', '.join(maps)}, {len(PHASES)} round phases")
		total = sum(occ.values())
		summary.append(f"{name}: " + ", ".join(f"{s} {100 * occ[s] / total:.0f}%" for s in STATES) + f" ({total * 0.05 / 60:.0f} player-min)")

	src = [
		"/*",
		"\t_bot_motor_data",
		"\tGENERATED by tools/gen_motor_model.py from human demo data. Do not edit.",
		"\tHuman movement state machine per profile: dwell-time deciles (s),",
		"\tnext-state weights (per mille) and time share (per mille);",
		"\tS&D context lifts per 512u map area and round phase (x100, see motorNext).",
	] + [f"\t  {s}" for s in summary] + [
		"*/",
		"",
		"/*",
		"\tReturns the data string for key (profile_state_field), or undefined.",
		"*/",
		"motor_data( key )",
		"{",
		"\tswitch ( key )",
		"\t{",
	] + body + [
		"\t}",
		"\t",
		"\treturn undefined;",
		"}",
		"",
	]
	with open(OUT, "wb") as f:
		f.write(("\r\n".join(src)).encode())
	print("\n".join(summary))
	print(f"wrote {OUT}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
