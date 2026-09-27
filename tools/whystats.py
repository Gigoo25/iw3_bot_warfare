#!/usr/bin/env python3
"""
Infers the "why" behind human behaviour from demo context: how much each
situation changes what players do (lift = P(behaviour | context) / P(behaviour)).

Context at each 20Hz sample (not while firing):
  heard     an enemy fired within the last 2s within 2000u
  near      nearest enemy (true position) within 1200u
  mate_died a teammate's corpse appeared within 1500u in the last 3s
  calm      none of the above
Behaviours:
  look_enemy  view within 20 deg of the nearest enemy's bearing
  look_shot   view within 20 deg of the most recent heard shot
  look_move   view within 20 deg of movement direction (when moving)
  stop        speed < 25
  crouch      crouched or prone
  sprint      speed > 230
  ads         aiming down sights

Usage: tools/whystats.py output/demos/demo0000 ... [--bots]
"""
import argparse
import bisect
import collections
import csv
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import demostats  # noqa: E402


def angd(a, b):
	return abs((a - b + 180) % 360 - 180)


def bearing(a, b):
	return math.degrees(math.atan2(float(b["y"]) - float(a["y"]), float(b["x"]) - float(a["x"])))


def analyze(base, want_bots, counts):
	rows = list(csv.DictReader(open(base + ".players.csv")))
	meta = json.load(open(base + ".meta.json"))
	names = {k: re.sub(r"\^.", "", v["name"]) for k, v in meta["names"].items()}
	bots = demostats.bot_clients(meta, names)
	snap = collections.defaultdict(dict)
	for r in rows:
		snap[int(r["t"])][r["client"]] = r
	team_of = {r["client"]: r["team"] for r in rows}
	deaths = []  # (t, x, y, team)
	seen = set()
	if os.path.exists(base + ".corpses.csv"):
		for r in csv.DictReader(open(base + ".corpses.csv")):
			if r["number"] not in seen:
				seen.add(r["number"])
				deaths.append((int(r["t"]), float(r["x"]), float(r["y"]), team_of.get(r["client"])))
	deaths.sort()
	death_t = [d[0] for d in deaths]
	shots = []  # (t, x, y, team)
	prev = {}
	for t in sorted(snap):
		for c, r in snap[t].items():
			if int(r["eflags"]) >> 6 & 1:
				shots.append((t, float(r["x"]), float(r["y"]), r["team"]))
			me = r
			if (c in bots) != want_bots or me["team"] in ("0", "3", "-1") or int(me["eflags"]) >> 6 & 1:
				prev[c] = r
				continue
			p = prev.get(c)
			prev[c] = r
			if not p or t - int(p["t"]) > 60:
				continue
			sp = math.hypot(float(r["x"]) - float(p["x"]), float(r["y"]) - float(p["y"])) / ((t - int(p["t"])) / 1000)
			if sp > 600:
				continue
			mx, my = float(me["x"]), float(me["y"])
			yaw = float(me["yaw"])
			enemies = [o for oc, o in snap[t].items() if oc != c and o["team"] not in ("0", "3", "-1", me["team"])]
			near = min(enemies, key=lambda o: math.hypot(float(o["x"]) - mx, float(o["y"]) - my)) if enemies else None
			near_d = math.hypot(float(near["x"]) - mx, float(near["y"]) - my) if near else 1e9
			heard = None
			for st, sx, sy, steam in reversed(shots[-400:]):
				if t - st > 2000:
					break
				if steam != me["team"] and math.hypot(sx - mx, sy - my) < 2000:
					heard = (sx, sy)
					break
			lo = bisect.bisect_left(death_t, t - 3000)
			hi = bisect.bisect_right(death_t, t)
			mate = any(dteam == me["team"] and math.hypot(dx - mx, dy - my) < 1500 for dt, dx, dy, dteam in deaths[lo:hi])
			ctxs = [k for k, v in (("heard", heard), ("near", near_d < 1200), ("mate_died", mate)) if v] or ["calm"]
			ef = int(me["eflags"])
			beh = {
				"look_enemy": near is not None and angd(yaw, bearing(me, near)) < 20,
				"look_shot": heard is not None and angd(yaw, math.degrees(math.atan2(heard[1] - my, heard[0] - mx))) < 20,
				"stop": sp < 25,
				"crouch": bool(ef >> 2 & 1 or ef >> 3 & 1),
				"sprint": sp > 230,
				"ads": bool(ef >> 18 & 1),
			}
			if sp > 60:
				beh["look_move"] = angd(yaw, math.degrees(math.atan2(float(r["y"]) - float(p["y"]), float(r["x"]) - float(p["x"])))) < 20
			for ctx in ctxs + ["all"]:
				counts[ctx]["n"] += 1
				for b, v in beh.items():
					counts[ctx][b + "_n"] += 1
					counts[ctx][b] += v
		# keep shot list bounded
		if len(shots) > 2000:
			shots = shots[-800:]


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("bases", nargs="+")
	ap.add_argument("--bots", action="store_true")
	args = ap.parse_args()
	counts = collections.defaultdict(collections.Counter)
	for b in args.bases:
		analyze(b, args.bots, counts)
	behs = ["look_enemy", "look_shot", "look_move", "stop", "crouch", "sprint", "ads"]
	allc = counts["all"]
	print(f"{'bots' if args.bots else 'humans'}: {allc['n'] * 0.05 / 60:.0f} player-min (not firing)")
	print(f"  {'context':10s} {'share':>6s}  " + "  ".join(f"{b:>11s}" for b in behs))
	for ctx in ("all", "calm", "heard", "near", "mate_died"):
		c = counts[ctx]
		if not c["n"]:
			continue
		cells = []
		for b in behs:
			if not c[b + "_n"]:
				cells.append(f"{'-':>11s}")
				continue
			p = c[b] / c[b + "_n"]
			base = allc[b] / allc[b + "_n"] if allc[b + "_n"] and allc[b] else 0
			lift = p / base if base else 0
			cells.append(f"{100 * p:5.1f}% x{lift:3.1f}" if ctx != "all" else f"{100 * p:10.1f}%")
		print(f"  {ctx:10s} {100 * c['n'] / allc['n']:5.1f}%  " + "  ".join(cells))
	return 0


if __name__ == "__main__":
	sys.exit(main())
