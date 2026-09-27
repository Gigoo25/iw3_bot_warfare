#!/usr/bin/env python3
"""
Learns where humans are on each map from demo exports and writes GSC data for
the bots (maps/mp/bots/_bot_map_data.gsc).

Per map (and for S&D per spawn side and round phase) it records the grid
cells humans spend time in (128u x/y, 96u height levels), weighted by time,
with the share of time spent standing still and the mean view yaw while still.

S&D sides: each player's position right after a round start is matched to
one of two spawn clusters (k-means over all round-start positions on that
map); "A"/"B" are those clusters, and the bot picks the one nearest its own
spawn. Phases: 0 = first 25s of the round, 1 = 25-60s, 2 = later.
Respawn modes use one "any" side and phase 0.

Round-start freeze (first 8s) is skipped and cells within 700u of the side's
own spawn are down-weighted x0.3 (spawn time isn't a positioning choice).

Usage: tools/gen_map_model.py output/demos/demo0000 output/demos/demo0001 ...
"""
import collections
import csv
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import demostats  # noqa: E402

OUT = "maps/mp/bots/_bot_map_data.gsc"
CELL = 128
LEVEL = 96
TOP = 80


def map_windows(meta):
	wins = []
	for mp in meta.get("maps", []):
		s = mp["configStrings"].get("0", "")
		m = re.search(r"mapname\\([^\\]+)", s)
		g = re.search(r"g_gametype\\([^\\]+)", s)
		if m:
			wins.append((mp["time"], m.group(1), g.group(1) if g else "?"))
	return wins


def window_of(wins, t):
	cur = None
	for w in wins:
		if w[0] <= t:
			cur = w
	return cur


def round_starts(ts_alive):
	ts = sorted(ts_alive)
	n = [len(ts_alive[t]) for t in ts]
	starts, j = [], 0
	for i in range(len(ts)):
		j = max(j, i)
		while j < len(ts) and ts[j] - ts[i] < 3000:
			j += 1
		if j < len(ts) and n[j - 1] - n[i] >= 6 and (not starts or ts[i] - starts[-1] > 30000):
			starts.append(ts[j - 1])
	return starts


def kmeans2(pts):
	a, b = pts[0], max(pts, key=lambda p: math.dist(p, pts[0]))
	for _ in range(30):
		ga = [p for p in pts if math.dist(p, a) <= math.dist(p, b)]
		gb = [p for p in pts if math.dist(p, a) > math.dist(p, b)]
		if not ga or not gb:
			break
		a = tuple(sum(c) / len(ga) for c in zip(*ga))
		b = tuple(sum(c) / len(gb) for c in zip(*gb))
	return a, b


def main():
	cells = collections.defaultdict(lambda: [0, 0.0, 0, 0.0, 0.0])  # samples, zsum, still, cos, sin
	spawnpts = collections.defaultdict(list)
	pending = []  # (map, gametype, client, t, row, speed, round_start)

	for base in sys.argv[1:]:
		rows = list(csv.DictReader(open(base + ".players.csv")))
		meta = json.load(open(base + ".meta.json"))
		names = {k: re.sub(r"\^.", "", v["name"]) for k, v in meta["names"].items()}
		bots = demostats.bot_clients(meta, names)
		wins = map_windows(meta)
		alive = collections.defaultdict(set)
		for r in rows:
			alive[int(r["t"])].add(r["client"])
		starts = round_starts(alive)
		by = collections.defaultdict(list)
		for r in rows:
			if r["client"] not in bots:
				by[r["client"]].append(r)
		for client, rs in by.items():
			rs.sort(key=lambda r: int(r["t"]))
			prev = None
			for r in rs:
				t = int(r["t"])
				w = window_of(wins, t)
				if not w:
					continue
				sp = 0.0
				if prev and 0 < t - int(prev["t"]) <= 60:
					sp = math.hypot(float(r["x"]) - float(prev["x"]), float(r["y"]) - float(prev["y"])) / ((t - int(prev["t"])) / 1000)
				prev = r
				if sp > 600:
					continue
				rs_t = max([s for s in starts if s <= t], default=None) if w[2] == "sd" else None
				if rs_t is not None and t - rs_t <= 3000:
					spawnpts[w[1]].append((float(r["x"]), float(r["y"]), float(r["z"])))
				pending.append((w[1], w[2], client, t, r, sp, rs_t))

	centroids = {m: kmeans2(p) for m, p in spawnpts.items() if len(p) >= 20}

	# side per (map, client, round start): cluster of the player's first position in that round
	side_of = {}
	for m, g, client, t, r, sp, rs_t in pending:
		if g != "sd" or rs_t is None or m not in centroids:
			continue
		key = (m, client, rs_t)
		if key not in side_of and t - rs_t <= 3000:
			p = (float(r["x"]), float(r["y"]), float(r["z"]))
			a, b = centroids[m]
			side_of[key] = "A" if math.dist(p, a) <= math.dist(p, b) else "B"

	for m, g, client, t, r, sp, rs_t in pending:
		if g == "sd":
			if rs_t is None or (m, client, rs_t) not in side_of:
				continue
			side = side_of[(m, client, rs_t)]
			el = (t - rs_t) / 1000
			if el < 8:
				continue  # round-start freeze: everyone stands in spawn, not a choice
			phase = 0 if el < 25 else 1 if el < 60 else 2
		else:
			side, phase = "any", 0
		x, y, z = float(r["x"]), float(r["y"]), float(r["z"])
		c = cells[(m, side, phase, round(x / CELL), round(y / CELL), round(z / LEVEL))]
		c[0] += 1
		c[1] += z
		if sp < 25:
			c[2] += 1
			yaw = math.radians(float(r["yaw"]))
			c[3] += math.cos(yaw)
			c[4] += math.sin(yaw)

	# spawn areas are where rounds start, not where people choose to be
	for key, c in cells.items():
		m, side = key[0], key[1]
		if side in ("A", "B") and m in centroids:
			home = centroids[m][0 if side == "A" else 1]
			if math.dist((key[3] * CELL, key[4] * CELL), home[:2]) < 700:
				c[0] = max(1, int(c[0] * 0.3))

	groups = collections.defaultdict(list)
	for key, c in cells.items():
		groups[key[:3]].append((key, c))

	lines, summary = [], []
	for m, (a, b) in sorted(centroids.items()):
		lines.append(f'\t\tcase "{m}_sides": return "{a[0]:.0f} {a[1]:.0f} {a[2]:.0f};{b[0]:.0f} {b[1]:.0f} {b[2]:.0f}";')
	for (m, side, phase), items in sorted(groups.items()):
		items.sort(key=lambda kc: -kc[1][0])
		top = items[:TOP]
		tot = sum(c[0] for _, c in top)
		ents = []
		for (mm, s, ph, gx, gy, gl), c in top:
			still = c[2] / c[0]
			yaw = math.degrees(math.atan2(c[4], c[3])) if c[2] else 0
			ents.append(f"{gx * CELL} {gy * CELL} {c[1] / c[0]:.0f} {max(1, round(1000 * c[0] / tot))} {yaw:.0f} {100 * still:.0f}")
		lines.append(f'\t\tcase "{m}_{side}_{phase}": return "{";".join(ents)}";')
		summary.append(f"{m} side {side} phase {phase}: {len(items)} cells, top {len(top)} cover {100 * tot / sum(c[0] for _, c in items):.0f}% of time")

	src = [
		"/*",
		"\t_bot_map_data",
		"\tGENERATED by tools/gen_map_model.py from human demo data. Do not edit.",
		"\tPer map/side/phase: cells as \"x y z weight yaw still%\" joined by ';'",
		"\t(weight per mille of time, yaw = mean view direction while standing still).",
		"\t<map>_sides: spawn cluster centroids for S&D sides A;B.",
	] + [f"\t  {s}" for s in summary] + [
		"*/",
		"",
		"/*",
		"\tReturns the data string for key, or undefined when the map has no data.",
		"*/",
		"map_data( key )",
		"{",
		"\tswitch ( key )",
		"\t{",
	] + lines + [
		"\t}",
		"\t",
		"\treturn undefined;",
		"}",
		"",
	]
	with open(OUT, "wb") as f:
		f.write("\r\n".join(src).encode())
	print("\n".join(summary))
	print(f"wrote {OUT}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
