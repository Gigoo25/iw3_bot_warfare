#!/usr/bin/env python3
"""
Learns where humans look from each spot on a map (demo exports) and writes
scriptdata/gaze/<map>.txt for the bots: per 128u cell (96u height levels)
and context -- standing still ("s") or moving with heading sector 0-7 ("m0"
.. "m7", 45 deg each) -- the view directions humans used there, as up to 5
yaw bins (22.5 deg) with their mean yaw, mean pitch and share of time.

Bots sample from these instead of inventing look targets, so they check
the doors, windows and lanes real players check from that spot.
Samples: human players (bots excluded), alive, not firing, 10Hz.

Line format: "ix iy iz ctx yaw pitch share;yaw pitch share;..."
Usage: tools/gen_gaze_model.py output/demos/demo0000 output/demos/demo0001 ...
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
LEVEL = 96
MIN_SAMPLES = 10
OUT_DIR = "scriptdata/gaze"


def main():
	# (map, ix, iy, iz, ctx) -> yaw bin -> [n, sin, cos, pitch sum]
	data = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0.0, 0.0, 0.0]))
	for base in sys.argv[1:]:
		meta = json.load(open(base + ".meta.json"))
		names = {k: re.sub(r"\^.", "", v["name"]) for k, v in meta["names"].items()}
		bots = demostats.bot_clients(meta, names)
		wins = gen_map_model.map_windows(meta)
		by = collections.defaultdict(list)
		for r in csv.DictReader(open(base + ".players.csv")):
			if r["client"] not in bots and r["team"] not in ("0", "3", "-1"):
				by[r["client"]].append(r)
		for rs in by.values():
			rs.sort(key=lambda r: int(r["t"]))
			for i in range(2, len(rs), 2):
				a, b = rs[i - 2], rs[i]
				dt = int(b["t"]) - int(a["t"])
				if dt <= 0 or dt > 150 or int(b["eflags"]) >> 6 & 1:
					continue
				w = gen_map_model.window_of(wins, int(b["t"]))
				if not w:
					continue
				vx, vy = float(b["x"]) - float(a["x"]), float(b["y"]) - float(a["y"])
				sp = math.hypot(vx, vy) / (dt / 1000)
				if sp > 600:
					continue
				if sp > 60:
					ctx = "m%d" % (int(((math.degrees(math.atan2(vy, vx)) + 22.5) % 360) // 45))
				elif sp < 25:
					ctx = "s"
				else:
					continue
				x, y, z = float(b["x"]), float(b["y"]), float(b["z"])
				yaw = float(b["yaw"])
				pitch = float(b["pitch"])
				pitch = pitch - 360 if pitch > 180 else pitch
				key = (w[1], round(x / CELL), round(y / CELL), round(z / LEVEL), ctx)
				bin_ = int((yaw % 360) // 22.5)
				c = data[key][bin_]
				c[0] += 1
				c[1] += math.sin(math.radians(yaw))
				c[2] += math.cos(math.radians(yaw))
				c[3] += pitch

	per_map = collections.defaultdict(list)
	for (m, ix, iy, iz, ctx), bins in data.items():
		tot = sum(c[0] for c in bins.values())
		if tot < MIN_SAMPLES:
			continue
		top = sorted(bins.values(), key=lambda c: -c[0])[:5]
		ents = []
		for c in top:
			share = c[0] / tot
			if share < 0.05:
				continue
			yaw = math.degrees(math.atan2(c[1], c[2]))
			ents.append(f"{yaw:.0f} {c[3] / c[0]:.0f} {round(100 * share)}")
		if ents:
			per_map[m].append(f"{ix} {iy} {iz} {ctx} " + ";".join(ents))

	os.makedirs(OUT_DIR, exist_ok=True)
	for m, lines in sorted(per_map.items()):
		path = os.path.join(OUT_DIR, f"{m}.txt")
		with open(path, "wb") as f:
			f.write(("\r\n".join(lines) + "\r\n").encode())
		print(f"{m}: {len(lines)} cell/context entries -> {path}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
