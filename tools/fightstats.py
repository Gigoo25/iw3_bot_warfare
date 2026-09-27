#!/usr/bin/env python3
"""
Gunfight behaviour from demo exports (20Hz), humans vs bots, same code for both.

Per firing burst (eFlags bit 6 = firing, gaps < 250ms merged):
  duration, gap to next burst, speed / strafe / stance / ADS / jumping while
  firing, view swing in the 0.5s before the first shot (the "flick"), and
  aim error: angle between view and the nearest enemy (other team) within a
  45 deg cone while firing.

Usage: tools/fightstats.py output/demos/demo0000 output/demos/demo0001 [--bots-only]
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


def angdiff(a, b):
	return abs((a - b + 180) % 360 - 180)


def q(v, p):
	v = sorted(v)
	return v[int(p * (len(v) - 1))] if v else float("nan")


def analyze(base, want_bots):
	rows = list(csv.DictReader(open(base + ".players.csv")))
	meta = json.load(open(base + ".meta.json"))
	names = {k: re.sub(r"\^.", "", v["name"]) for k, v in meta["names"].items()}
	bots = demostats.bot_clients(meta, names)
	snap = collections.defaultdict(dict)
	for r in rows:
		snap[int(r["t"])][r["client"]] = r
	by = collections.defaultdict(list)
	for r in rows:
		if (r["client"] in bots) == want_bots:
			by[r["client"]].append(r)

	res = collections.defaultdict(list)
	minutes = 0
	for client, rs in by.items():
		rs.sort(key=lambda r: int(r["t"]))
		minutes += len(rs) * 0.05 / 60
		for seg in demostats.segments(rs):
			if len(seg) < 40:
				continue
			fire = [int(r["eflags"]) >> 6 & 1 for r in seg]
			# merge short gaps
			bursts, i = [], 0
			while i < len(seg):
				if fire[i]:
					j = i
					while j < len(seg) and (fire[j] or any(fire[j:j + 5])):
						j += 1
					bursts.append((i, j))
					i = j
				else:
					i += 1
			for n, (s, e) in enumerate(bursts):
				res["burst_s"].append((e - s) * 0.05)
				if n + 1 < len(bursts):
					res["gap_s"].append((bursts[n + 1][0] - e) * 0.05)
				# lead-in view swing (0.5s before first shot)
				if s >= 10:
					y0, p0 = float(seg[s - 10]["yaw"]), float(seg[s - 10]["pitch"])
					y1, p1 = float(seg[s]["yaw"]), float(seg[s]["pitch"])
					res["flick_deg"].append(math.hypot(angdiff(y1, y0), angdiff(p1, p0)))
					peak = max(math.hypot(angdiff(float(seg[k]["yaw"]), float(seg[k - 1]["yaw"])), angdiff(float(seg[k]["pitch"]), float(seg[k - 1]["pitch"]))) / 0.05 for k in range(s - 9, s + 1))
					res["flick_peak_dps"].append(peak)
				for k in range(s + 1, e):
					a, b = seg[k - 1], seg[k]
					vx, vy = float(b["x"]) - float(a["x"]), float(b["y"]) - float(a["y"])
					sp = math.hypot(vx, vy) / 0.05
					if sp > 600:
						continue
					ef = int(b["eflags"])
					res["speed"].append(sp)
					res["crouch"].append(ef >> 2 & 1)
					res["prone"].append(ef >> 3 & 1)
					res["ads"].append(ef >> 18 & 1)
					res["air"].append(1 if b["ground"] == "1023" else 0)
					if sp > 40:
						move = math.degrees(math.atan2(vy, vx))
						off = angdiff(float(b["yaw"]), move)
						res["strafe"].append(1 if 60 <= off <= 120 else 0)
					# aim error to nearest enemy in a 45deg cone
					me = b
					others = snap[int(me["t"])]
					best = None
					for oc, o in others.items():
						if oc == client or o["team"] == me["team"] or o["team"] in ("0", "3", "-1"):
							continue
						dx, dy = float(o["x"]) - float(me["x"]), float(o["y"]) - float(me["y"])
						dz = float(o["z"]) + 40 - (float(me["z"]) + 60)
						dist = math.hypot(dx, dy)
						if dist < 50:
							continue
						yaw_to = math.degrees(math.atan2(dy, dx))
						pitch_to = -math.degrees(math.atan2(dz, dist))
						err = math.hypot(angdiff(float(me["yaw"]), yaw_to), angdiff(float(me["pitch"]), pitch_to))
						if err < 45 and (best is None or err < best[0]):
							best = (err, dist)
					if best:
						res["aim_err"].append(best[0])
						res["fight_dist"].append(best[1])
	return res, minutes


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("bases", nargs="+")
	ap.add_argument("--bots-only", action="store_true", help="analyze bots (0 ping / [BOT]) instead of humans")
	args = ap.parse_args()
	allres = collections.defaultdict(list)
	mins = 0
	for b in args.bases:
		r, m = analyze(b, args.bots_only)
		mins += m
		for k, v in r.items():
			allres[k] += v
	r = allres
	pct = lambda k: 100 * sum(r[k]) / max(len(r[k]), 1)
	print(f"{'bots' if args.bots_only else 'humans'}: {mins:.0f} player-min, {len(r['burst_s'])} bursts ({len(r['burst_s']) / max(mins, 1e-9):.1f}/min)")
	print(f"  burst length s        p25 {q(r['burst_s'], .25):.2f}  med {q(r['burst_s'], .5):.2f}  p75 {q(r['burst_s'], .75):.2f}  p90 {q(r['burst_s'], .9):.2f}")
	print(f"  gap between bursts s  p25 {q(r['gap_s'], .25):.2f}  med {q(r['gap_s'], .5):.2f}  p75 {q(r['gap_s'], .75):.2f}")
	print(f"  view swing 0.5s before 1st shot deg  med {q(r['flick_deg'], .5):.1f}  p75 {q(r['flick_deg'], .75):.1f}  p90 {q(r['flick_deg'], .9):.1f}")
	print(f"  peak view speed before 1st shot deg/s  med {q(r['flick_peak_dps'], .5):.0f}  p90 {q(r['flick_peak_dps'], .9):.0f}")
	print(f"  while firing: speed med {q(r['speed'], .5):.0f}  moving(>40) {100 * sum(s > 40 for s in r['speed']) / max(len(r['speed']), 1):.0f}%  strafing {pct('strafe'):.0f}%  crouch {pct('crouch'):.0f}%  prone {pct('prone'):.0f}%  ADS {pct('ads'):.0f}%  airborne {pct('air'):.1f}%")
	print(f"  aim error to nearest enemy (deg)  med {q(r['aim_err'], .5):.1f}  p75 {q(r['aim_err'], .75):.1f}   fight distance med {q(r['fight_dist'], .5):.0f}u")
	return 0


if __name__ == "__main__":
	sys.exit(main())
