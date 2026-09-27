#!/usr/bin/env python3
"""
Player-style archetypes from demo data: per-player movement metrics (same code
as tools/demostats.py / movestats.py), clustered with k-means (pure Python).

Each demo session of a player counts separately (a player on two demos = two
points). Players with < MIN_MINUTES of decoded data are skipped.

Usage: tools/archetypes.py output/demos/demo0000 output/demos/demo0001 [--k 4]
"""
import argparse
import collections
import csv
import json
import math
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import demostats  # noqa: E402
import movestats  # noqa: E402

MIN_MINUTES = 3.0
FEATURES = [
	("sprint %", "sprint"),
	("crouch %", "crouch"),
	("prone %", "prone"),
	("still %", "still"),
	("ADS while moving %", "ads_move"),
	("jumps /min", "jumps"),
	("strafing (60-120deg) %", "strafe"),
	("stop-go transitions /min", "stopgo"),
]


def player_metrics(base):
	rows = list(csv.DictReader(open(base + ".players.csv")))
	meta = json.load(open(base + ".meta.json"))
	names = {k: re.sub(r"\^.", "", v["name"]) for k, v in meta["names"].items()}
	bots = demostats.bot_clients(meta, names)
	by = collections.defaultdict(list)
	for r in rows:
		by[r["client"]].append(r)
	out = {}
	for client, rs in by.items():
		name = names.get(client, "#" + client)
		if client in bots:
			continue
		rs.sort(key=lambda r: int(r["t"]))
		samples = []
		for seg in demostats.segments(rs):
			if len(seg) >= 60:
				samples += demostats.resample(seg)
		m = movestats.metrics(samples)
		if m and m["_minutes"] >= MIN_MINUTES:
			out[f"{name} ({os.path.basename(base)})"] = m
	return out


def kmeans(points, k, restarts=50, seed=1):
	rng = random.Random(seed)
	best = None
	for _ in range(restarts):
		cents = [list(p) for p in rng.sample(points, k)]
		for _ in range(100):
			groups = [[] for _ in range(k)]
			for p in points:
				groups[min(range(k), key=lambda c: sum((a - b) ** 2 for a, b in zip(p, cents[c])))].append(p)
			new = [[sum(col) / len(g) for col in zip(*g)] if g else cents[i] for i, g in enumerate(groups)]
			if new == cents:
				break
			cents = new
		sse = sum(min(sum((a - b) ** 2 for a, b in zip(p, c)) for c in cents) for p in points)
		if best is None or sse < best[0]:
			best = (sse, cents)
	return best


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("bases", nargs="+")
	ap.add_argument("--k", type=int, default=0, help="clusters (0 = show k=2..5 SSE and use elbow)")
	args = ap.parse_args()

	per = {}
	for b in args.bases:
		per.update(player_metrics(b))
	names = sorted(per)
	raw = [[per[n][f] for f, _ in FEATURES] for n in names]
	mu = [sum(c) / len(c) for c in zip(*raw)]
	sd = [math.sqrt(sum((x - m) ** 2 for x in c) / len(c)) or 1 for c, m in zip(zip(*raw), mu)]
	pts = [[(x - m) / s for x, m, s in zip(r, mu, sd)] for r in raw]
	print(f"{len(names)} player-sessions with >= {MIN_MINUTES} min")

	k = args.k
	if not k:
		sses = {kk: kmeans(pts, kk)[0] for kk in range(2, 6)}
		print("SSE by k:", {kk: round(v, 1) for kk, v in sses.items()})
		# elbow: first k whose next step improves SSE by < 15%
		k = next((kk for kk in range(2, 5) if (sses[kk] - sses[kk + 1]) / sses[kk] < 0.15), 4)
	_, cents = kmeans(pts, k)

	assign = {n: min(range(k), key=lambda c: sum((a - b) ** 2 for a, b in zip(p, cents[c]))) for n, p in zip(names, pts)}
	print(f"\nk={k} archetypes (cluster means, raw units; share of player-sessions)")
	hdr = "  ".join(f"{short:>7s}" for _, short in FEATURES)
	print(f"  {'':12s} {'share':>6s}  {hdr}")
	for c in range(k):
		members = [n for n in names if assign[n] == c]
		means = [sum(per[n][f] for n in members) / len(members) for f, _ in FEATURES]
		print(f"  type {c:<7d} {100 * len(members) / len(names):5.0f}%  " + "  ".join(f"{v:7.1f}" for v in means))
		print(f"    e.g. {', '.join(m.split(' (')[0] for m in members[:6])}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
