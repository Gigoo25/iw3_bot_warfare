#!/usr/bin/env python3
"""
Grenade usage from a demo export (<base>.missiles.csv / .players.csv from
tools/demo/extract.sh): throws per minute by kind and timing within S&D rounds.

Kinds are inferred from behaviour (weapon indices change per map): gravity arc
with ~3.3s life = uncooked frag; shorter arc = flash/stun/smoke or cooked frag;
straight line = noob tube / RPG; stationary 20s+ = claymore / C4.
Round starts = live-player count jumping by 6+ within 3s.

Usage: tools/nadestats.py output/demos/demo0000 [...]
"""
import collections
import csv
import statistics
import sys


def throws_of(base):
	throws, cur = [], {}
	for r in csv.DictReader(open(base + ".missiles.csv")):
		n, t = r["number"], int(r["t"])
		c = cur.get(n)
		if c and t - c["last"] <= 500 and c["w"] == r["weapon"]:
			c["last"] = t
		else:
			if c:
				throws.append(c)
			cur[n] = {"first": t, "last": t, "w": r["weapon"], "tr": r["trtype"]}
	return throws + list(cur.values())


def throws_of_rows(base):
	"""Like throws_of, plus p0/p1: the trajectory base at the first and last sample."""
	throws, cur = [], {}
	for r in csv.DictReader(open(base + ".missiles.csv")):
		n, t = r["number"], int(r["t"])
		p = (float(r["x"]), float(r["y"]), float(r["z"]))
		c = cur.get(n)
		if c and t - c["last"] <= 500 and c["w"] == r["weapon"]:
			c["last"] = t
			c["p1"] = p
		else:
			if c:
				throws.append(c)
			cur[n] = {"first": t, "last": t, "w": r["weapon"], "tr": r["trtype"], "p0": p, "p1": p}
	return throws + list(cur.values())


def kind(th):
	dur = (th["last"] - th["first"]) / 1000
	if th["tr"] == "0" or dur > 20:
		return "claymore/c4"
	if th["tr"] == "2":
		return "tube/rpg"
	return "frag (uncooked)" if dur >= 3.0 else "flash/stun/smoke/cooked frag"


def round_starts(base):
	alive = collections.defaultdict(set)
	for r in csv.DictReader(open(base + ".players.csv")):
		alive[int(r["t"])].add(r["client"])
	ts = sorted(alive)
	n = [len(alive[t]) for t in ts]
	starts, j = [], 0
	for i in range(len(ts)):
		j = max(j, i)
		while j < len(ts) and ts[j] - ts[i] < 3000:
			j += 1
		if j < len(ts) and n[j - 1] - n[i] >= 6 and (not starts or ts[i] - starts[-1] > 30000):
			starts.append(ts[j - 1])
	return starts, (ts[-1] - ts[0]) / 60000


def main():
	for base in sys.argv[1:]:
		throws = throws_of(base)
		starts, minutes = round_starts(base)
		kinds = collections.Counter(kind(t) for t in throws)
		hand = [t for t in throws if kind(t) in ("frag (uncooked)", "flash/stun/smoke/cooked frag")]
		since = []
		for t in hand:
			prev = [s for s in starts if s <= t["first"]]
			if prev:
				since.append((t["first"] - prev[-1]) / 1000)
		since.sort()
		print(f"{base}: {minutes:.0f} min, {len(starts)} round starts")
		for k, v in kinds.most_common():
			print(f"  {k:30s} {v:4d}  ({v / minutes:.1f}/min)")
		if since:
			early = sum(s <= 20 for s in since) / len(since)
			q = lambda p: since[int(p * (len(since) - 1))]
			print(f"  hand grenades in first 20s of a round: {100 * early:.0f}%  (s into round p25/median/p75: {q(.25):.0f}/{q(.5):.0f}/{q(.75):.0f})")
	return 0


if __name__ == "__main__":
	sys.exit(main())
