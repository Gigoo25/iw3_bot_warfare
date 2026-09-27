#!/usr/bin/env python3
"""
Builds bot navigation graphs from human movement in demos, in the mod's
waypoint CSV format (scriptdata/waypoints_human/<map>_wp.csv), so maps with
demo data need no hand-made waypoints and bots follow real human routes.

Nodes: 128u grid cells (64u height levels) that humans stood in on the ground
at least MIN_SAMPLES times; placed at the mean human position in the cell.
Edges: humans moving from one cell into another (walking, or a jump/drop
between two grounded samples within 1.5s). Seen at least MIN_EDGE times.
Walking edges are made two-way; drops of more than 48u stay one-way.
Only the largest connected component is kept.

Usage: tools/gen_human_nav.py output/demos/demo0000 output/demos/demo0001 ...
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
import gen_map_model  # noqa: E402

CELL = 128
LEVEL = 64
MIN_SAMPLES = 20
MIN_EDGE = 2
OUT_DIR = "scriptdata/waypoints_human"


def key_of(x, y, z):
	return (round(x / CELL), round(y / CELL), round(z / LEVEL))


def main():
	pos = collections.defaultdict(lambda: collections.defaultdict(list))  # map -> cell -> [(x,y,z,crouch)]
	edges = collections.defaultdict(collections.Counter)  # map -> (a,b) -> count

	for base in sys.argv[1:]:
		rows = list(csv.DictReader(open(base + ".players.csv")))
		meta = json.load(open(base + ".meta.json"))
		names = {k: re.sub(r"\^.", "", v["name"]) for k, v in meta["names"].items()}
		bots = demostats.bot_clients(meta, names)
		wins = gen_map_model.map_windows(meta)
		by = collections.defaultdict(list)
		for r in rows:
			if r["client"] not in bots:
				by[r["client"]].append(r)
		for client, rs in by.items():
			rs.sort(key=lambda r: int(r["t"]))
			last = None  # (t, cell, map)
			for r in rs:
				t = int(r["t"])
				w = gen_map_model.window_of(wins, t)
				if not w or r["ground"] == "1023":
					continue  # in the air / unknown map
				m = w[1]
				x, y, z = float(r["x"]), float(r["y"]), float(r["z"])
				ef = int(r["eflags"])
				c = key_of(x, y, z)
				pos[m][c].append((x, y, z, ef >> 2 & 1 or ef >> 3 & 1))
				if last and last[2] == m and last[1] != c and t - last[0] <= 1500:
					a, b = last[1], c
					# only link near cells (a teleport/respawn isn't a route)
					if abs(a[0] - b[0]) <= 2 and abs(a[1] - b[1]) <= 2:
						edges[m][(a, b)] += 1
				last = (t, c, m)

	os.makedirs(OUT_DIR, exist_ok=True)
	for m, cells in pos.items():
		nodes = {c: v for c, v in cells.items() if len(v) >= MIN_SAMPLES}
		adj = collections.defaultdict(set)
		for (a, b), n in edges[m].items():
			if n < MIN_EDGE or a not in nodes or b not in nodes:
				continue
			za = sum(p[2] for p in nodes[a]) / len(nodes[a])
			zb = sum(p[2] for p in nodes[b]) / len(nodes[b])
			adj[a].add(b)
			if zb - za > -48:  # not a big drop: walkable back
				adj[b].add(a)
		# largest connected component (undirected view)
		und = collections.defaultdict(set)
		for a, bs in adj.items():
			for b in bs:
				und[a].add(b)
				und[b].add(a)
		best = set()
		seen = set()
		for start in und:
			if start in seen:
				continue
			comp, stack = set(), [start]
			while stack:
				n = stack.pop()
				if n in comp:
					continue
				comp.add(n)
				stack.extend(und[n] - comp)
			seen |= comp
			if len(comp) > len(best):
				best = comp
		order = sorted(best)
		idx = {c: i for i, c in enumerate(order)}
		lines = [str(len(order))]
		for c in order:
			pts = nodes[c]
			x = sum(p[0] for p in pts) / len(pts)
			y = sum(p[1] for p in pts) / len(pts)
			z = sum(p[2] for p in pts) / len(pts)
			# always "stand": cells humans crouched in are mostly hold spots, not
			# crawlspaces. Every node has >= 1 child (empty fields break strtok).
			kids = " ".join(str(idx[b]) for b in sorted(adj[c]) if b in idx)
			if not kids:
				kids = str(idx[min(und[c] & set(idx), key=lambda b: abs(b[0] - c[0]) + abs(b[1] - c[1]))])
			lines.append(f"{x:.1f} {y:.1f} {z:.1f},{kids},stand,,,")
		path = os.path.join(OUT_DIR, f"{m}_wp.csv")
		with open(path, "wb") as f:
			f.write(("\r\n".join(lines) + "\r\n").encode())
		nedges = sum(len(adj[c]) for c in order)
		print(f"{m}: {len(order)} nodes, {nedges} links (of {len(nodes)} candidate cells, {len(edges[m])} raw transitions) -> {path}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
