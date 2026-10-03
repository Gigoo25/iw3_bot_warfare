#!/usr/bin/env python3
"""
Scores waypoint graphs against where humans actually go on a map.

  coverage   share of human ground positions (demo exports, bots excluded)
             with a node within 128u horizontally and 64u vertically
  gap        distance from human positions to the nearest node (median/p90)
  connected  share of nodes in the largest strongly connected component
             (can reach, and be reached from, each other)
  one-way    share of links with no link back (drops)

Usage: tools/navstats.py mp_backlot scriptdata/waypoints/mp_backlot_wp.csv scriptdata/navmesh/mp_backlot_wp.csv \
         --demos output/demos/demo0000 output/demos/demo0001 ...
"""
import argparse
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


def load_graph(path):
	lines = [l.strip() for l in open(path, encoding="latin-1") if l.strip()]
	n = int(lines[0])
	nodes, kids = [], []
	for line in lines[1:n + 1]:
		t = line.split(",")
		nodes.append(tuple(float(v) for v in t[0].split()))
		kids.append([int(c) for c in t[1].split()] if len(t) > 1 and t[1].strip() else [])
	return nodes, kids


def largest_scc(n, kids):
	# iterative Tarjan
	index, low, on, stack, best = {}, {}, set(), [], 0
	counter = 0
	for root in range(n):
		if root in index:
			continue
		work = [(root, 0)]
		while work:
			v, i = work.pop()
			if i == 0:
				index[v] = low[v] = counter
				counter += 1
				stack.append(v)
				on.add(v)
			recurse = False
			ks = [k for k in kids[v] if 0 <= k < n and k != v]
			for j in range(i, len(ks)):
				w = ks[j]
				if w not in index:
					work.append((v, j + 1))
					work.append((w, 0))
					recurse = True
					break
				if w in on:
					low[v] = min(low[v], index[w])
			if recurse:
				continue
			if low[v] == index[v]:
				size = 0
				while True:
					w = stack.pop()
					on.discard(w)
					size += 1
					if w == v:
						break
				best = max(best, size)
			if work:
				u = work[-1][0]
				low[u] = min(low[u], low[v])
	return best


def human_positions(bases, mapname):
	pts = []
	for base in bases:
		meta = json.load(open(base + ".meta.json"))
		names = {k: re.sub(r"\^.", "", v["name"]) for k, v in meta["names"].items()}
		bots = demostats.bot_clients(meta, names)
		wins = gen_map_model.map_windows(meta)
		for i, r in enumerate(csv.DictReader(open(base + ".players.csv"))):
			if i % 5 or r["client"] in bots or r["ground"] == "1023":
				continue  # 4Hz is plenty; skip bots and airborne samples
			w = gen_map_model.window_of(wins, int(r["t"]))
			if w and w[1] == mapname:
				pts.append((float(r["x"]), float(r["y"]), float(r["z"])))
	return pts


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("map")
	ap.add_argument("graphs", nargs="+")
	ap.add_argument("--demos", nargs="*", default=[])
	args = ap.parse_args()
	pts = human_positions(args.demos, args.map) if args.demos else []
	print(f"{args.map}: {len(pts)} human ground samples")
	for path in args.graphs:
		nodes, kids = load_graph(path)
		grid = collections.defaultdict(list)
		for p in nodes:
			grid[(int(p[0] // 128), int(p[1] // 128))].append(p)
		gaps, covered = [], 0
		for x, y, z in pts:
			best = 1e9
			gx, gy = int(x // 128), int(y // 128)
			for r in range(0, 12):
				for dx in range(-r, r + 1):
					for dy in range(-r, r + 1):
						if max(abs(dx), abs(dy)) != r:
							continue
						for p in grid.get((gx + dx, gy + dy), ()):
							if abs(p[2] - z) < 64:
								best = min(best, math.hypot(p[0] - x, p[1] - y))
				if best < r * 128:
					break
			gaps.append(best)
			covered += best <= 128
		links = sum(len([k for k in ks if k != i]) for i, ks in enumerate(kids))
		linkset = {(i, k) for i, ks in enumerate(kids) for k in ks if k != i}
		oneway = sum((k, i) not in linkset for i, k in linkset)
		scc = largest_scc(len(nodes), kids)
		gaps.sort()
		q = lambda f: gaps[int(f * (len(gaps) - 1))] if gaps else float("nan")
		print(f"  {path}")
		print(f"    {len(nodes)} nodes, {links} links ({100 * oneway / max(links, 1):.0f}% one-way), connected {100 * scc / max(len(nodes), 1):.0f}%")
		if pts:
			print(f"    coverage {100 * covered / len(pts):.0f}%   gap to nearest node: median {q(.5):.0f}u  p90 {q(.9):.0f}u")
	return 0


if __name__ == "__main__":
	sys.exit(main())
