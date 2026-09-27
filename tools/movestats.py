#!/usr/bin/env python3
"""
Movement "tells" from bots_telemetry lines (BT;/BE;) in games_mp.log.

Samples are 5Hz per player. Bots and humans are reported side by side; join
the dev server and play a match to get a real human column. The "guess"
column is a rough expectation for CoD4 pub players, not measured data.

Usage:
  docker compose -f server/docker-compose.yml exec -T cod4x cat /cod4home/mods/mp_bots/games_mp.log | tools/movestats.py --since-last-init
  tools/movestats.py games_mp.log [--per-player]
"""
import argparse
import collections
import math
import sys

DT = 0.2

# CoD4 speeds (units/s): run ~190, sprint ~1.5x, crouch/ADS walk well under run
STILL, SLOW, RUN = 20, 160, 230

GUESS = {
	"still %": "5-20",
	"slow (crouch/ADS/walk) %": "10-30",
	"dawdling (slow, facing fwd) %": "0-8",
	"sprint %": "15-40",
	"crouch %": "5-20",
	"prone %": "0-5",
	"ADS while moving %": "10-30",
	"look = move dir (<15deg) %": "35-65",
	"strafing (60-120deg) %": "10-30",
	"backpedal (>120deg) %": "2-10",
	"view turn deg/s (median)": "40-120",
	"snap heading changes /min": "0-5",
	"path straightness (2s)": "0.75-0.9",
	"jumps /min": "1-6",
	"stop-go transitions /min": "5-20",
	"pitch mean (deg, +down)": "0-8",
	"pitch sd": "5-15",
	"in combat (has target) %": "25-45",
	"idle gap between fights (s, median)": "5-20",
}


def angdiff(a, b):
	return abs((a - b + 180) % 360 - 180)


def parse(lines, since_last_init):
	if since_last_init:
		start = 0
		for i, line in enumerate(lines):
			if "InitGame:" in line:
				start = i
		lines = lines[start:]
	tracks = collections.defaultdict(list)
	events = collections.Counter()
	isbot = {}
	for line in lines:
		parts = line.strip().split(" ", 1)
		if len(parts) < 2:
			continue
		f = parts[1].split(";")
		if f[0] == "BT" and len(f) >= 15:
			name = f[2]
			isbot[name] = f[3] == "1"
			tracks[name].append({
				"x": int(f[4]), "y": int(f[5]), "z": int(f[6]),
				"vx": int(f[7]), "vy": int(f[8]), "vz": int(f[9]),
				"pitch": int(f[10]), "yaw": int(f[11]), "stance": f[12],
				"ads": int(f[13]), "tgt": f[14] == "1",
			})
		elif f[0] == "BE" and len(f) >= 4:
			events[f[3]] += 1
	return tracks, isbot, events


def metrics(samples):
	n = len(samples)
	if n < 25:
		return None
	m = collections.Counter()
	speeds = [math.hypot(s["vx"], s["vy"]) for s in samples]
	moving = [i for i, sp in enumerate(speeds) if sp > 100]
	minutes = n * DT / 60

	m["still %"] = 100 * sum(sp < STILL for sp in speeds) / n
	m["slow (crouch/ADS/walk) %"] = 100 * sum(STILL <= sp < SLOW for sp in speeds) / n
	m["sprint %"] = 100 * sum(sp >= RUN for sp in speeds) / n
	# slow while standing, not ADS, facing where you move: strafe/backpedal speed excluded
	m["dawdling (slow, facing fwd) %"] = 100 * sum(
		1 for i, s in enumerate(samples)
		if STILL <= speeds[i] < SLOW and s["stance"] == "stand" and s["ads"] < 5
		and angdiff(s["yaw"], math.degrees(math.atan2(s["vy"], s["vx"]))) < 30) / n
	m["crouch %"] = 100 * sum(s["stance"] == "crouch" for s in samples) / n
	m["prone %"] = 100 * sum(s["stance"] == "prone" for s in samples) / n

	if moving:
		m["ADS while moving %"] = 100 * sum(samples[i]["ads"] >= 5 for i in moving) / len(moving)
		offs = [angdiff(samples[i]["yaw"], math.degrees(math.atan2(samples[i]["vy"], samples[i]["vx"]))) for i in moving]
		m["look = move dir (<15deg) %"] = 100 * sum(o < 15 for o in offs) / len(offs)
		m["strafing (60-120deg) %"] = 100 * sum(60 <= o <= 120 for o in offs) / len(offs)
		m["backpedal (>120deg) %"] = 100 * sum(o > 120 for o in offs) / len(offs)

	turns = sorted(angdiff(samples[i]["yaw"], samples[i - 1]["yaw"]) / DT for i in range(1, n))
	m["view turn deg/s (median)"] = turns[len(turns) // 2]

	snaps = 0
	for i in range(1, n):
		if speeds[i] > 150 and speeds[i - 1] > 150:
			h0 = math.degrees(math.atan2(samples[i - 1]["vy"], samples[i - 1]["vx"]))
			h1 = math.degrees(math.atan2(samples[i]["vy"], samples[i]["vx"]))
			if angdiff(h0, h1) > 60:
				snaps += 1
	m["snap heading changes /min"] = snaps / minutes

	ratios = []
	for i in range(0, n - 10, 5):
		w = samples[i:i + 11]
		path = sum(math.hypot(w[j]["x"] - w[j - 1]["x"], w[j]["y"] - w[j - 1]["y"]) for j in range(1, len(w)))
		if path > 150 and path < 1200:  # skip idles and respawn teleports
			ratios.append(math.hypot(w[-1]["x"] - w[0]["x"], w[-1]["y"] - w[0]["y"]) / path)
	if ratios:
		m["path straightness (2s)"] = sum(ratios) / len(ratios)

	jumps = sum(1 for i in range(1, n) if samples[i]["vz"] > 100 and samples[i - 1]["vz"] <= 100)
	m["jumps /min"] = jumps / minutes
	stopgo = sum(1 for i in range(1, n) if (speeds[i] < 40) != (speeds[i - 1] < 40))
	m["stop-go transitions /min"] = stopgo / minutes
	pitches = [s["pitch"] if s["pitch"] < 180 else s["pitch"] - 360 for s in samples]
	pm = sum(pitches) / n
	m["pitch mean (deg, +down)"] = pm
	m["pitch sd"] = math.sqrt(sum((p - pm) ** 2 for p in pitches) / n)
	m["in combat (has target) %"] = 100 * sum(s["tgt"] for s in samples) / n
	gaps, run = [], 0
	for s in samples:
		if s["tgt"]:
			if run:
				gaps.append(run * DT)
			run = 0
		else:
			run += 1
	if gaps:
		gaps.sort()
		m["idle gap between fights (s, median)"] = gaps[len(gaps) // 2]
	m["_minutes"] = minutes
	return m


def avg(ms):
	out = {}
	w = sum(m["_minutes"] for m in ms)
	for k in GUESS:
		vals = [(m[k], m["_minutes"]) for m in ms if k in m]
		if vals:
			out[k] = sum(v * mw for v, mw in vals) / sum(mw for _, mw in vals)
	return out, w


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("log", nargs="?")
	ap.add_argument("--since-last-init", action="store_true")
	ap.add_argument("--per-player", action="store_true")
	args = ap.parse_args()
	lines = open(args.log, errors="replace").readlines() if args.log else sys.stdin.readlines()
	tracks, isbot, events = parse(lines, args.since_last_init)
	if not tracks:
		print("no BT telemetry lines (set bots_telemetry 1)")
		return 1

	per = {name: metrics(s) for name, s in tracks.items()}
	per = {k: v for k, v in per.items() if v}
	bots, bmin = avg([m for k, m in per.items() if isbot[k]])
	humans, hmin = avg([m for k, m in per.items() if not isbot[k]]) if any(not isbot[k] for k in per) else ({}, 0)

	print(f"bots: {sum(isbot[k] for k in per)} players, {bmin:.1f} player-min   humans: {sum(not isbot[k] for k in per)} players, {hmin:.1f} player-min")
	print(f"\n  {'metric':30s} {'bots':>8s} {'humans':>8s}   guess")
	for k, g in GUESS.items():
		b = f"{bots[k]:8.1f}" if k in bots else f"{'-':>8s}"
		h = f"{humans[k]:8.1f}" if k in humans else f"{'-':>8s}"
		print(f"  {k:30s} {b} {h}   {g}")

	if events:
		print("\nevents")
		for e, c in events.most_common():
			print(f"  {e:20s} {c}")

	if args.per_player:
		print()
		keys = list(GUESS)
		for name, m in sorted(per.items()):
			print(f"{name} ({'bot' if isbot[name] else 'human'}): " + ", ".join(f"{k.split(' ')[0]}={m[k]:.0f}" for k in keys if k in m))
	return 0


if __name__ == "__main__":
	sys.exit(main())
