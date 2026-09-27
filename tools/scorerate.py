#!/usr/bin/env python3
"""
Score per minute of players on the local server, measured like GameTracker
(score gained / minutes connected), from rcon status polls.

Human reference (GameTracker, NamelessNoobs S&D 66.45.234.194:28961, 243
regulars with >=1h played, bot2..bot9 seed bots excluded, 2026-09-26):
  p10 2.0  p25 2.5  median 3.1  p75 3.9  p90 4.6

Usage: tools/scorerate.py [minutes=10] [--interval 20]
"""
import argparse
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from rcon import rcon  # noqa: E402

HUMAN_SD = {"p10": 2.0, "p25": 2.5, "median": 3.1, "p75": 3.9, "p90": 4.6}
ROW = re.compile(r"^\s*(\d+)\s+(-?\d+)\s+(\d+)\s+\S+\s+\S+\s+(.+?)\s+\d+\s+(bot|\S+:\d+)")


def poll():
	out = rcon("127.0.0.1", 28960, "botdev123", "status") or ""
	rows = {}
	gametype = None
	for line in out.splitlines():
		m = ROW.match(line)
		if m:
			name = re.sub(r"\^.", "", m.group(4)).strip()
			rows[name] = int(m.group(2))
	info = rcon("127.0.0.1", 28960, "botdev123", "g_gametype") or ""
	m = re.search(r'is:\s*"([^"^]+)', info)
	if m:
		gametype = m.group(1)
	return rows, gametype


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("minutes", nargs="?", type=float, default=10)
	ap.add_argument("--interval", type=float, default=20)
	args = ap.parse_args()

	first, last = {}, {}
	gametypes = set()
	end = time.time() + args.minutes * 60
	while time.time() < end:
		rows, gt = poll()
		gametypes.add(gt)
		now = time.time()
		for name, score in rows.items():
			# a score drop means a new map/round reset: restart that player's window
			if name not in first or score < last[name][1]:
				first[name] = (now, score)
			last[name] = (now, score)
		time.sleep(args.interval)

	rates = []
	for name in first:
		t0, s0 = first[name]
		t1, s1 = last[name]
		minutes = (t1 - t0) / 60
		if minutes >= 3:
			rates.append((s1 - s0) / minutes)
	if not rates:
		print("not enough data")
		return 1
	rates.sort()
	q = lambda p: rates[int(p * (len(rates) - 1))]
	print(f"gametype(s): {', '.join(sorted(g for g in gametypes if g))}   players measured: {len(rates)}")
	print(f"  bots   p10 {q(.1):4.1f}  p25 {q(.25):4.1f}  median {q(.5):4.1f}  p75 {q(.75):4.1f}  p90 {q(.9):4.1f}")
	h = HUMAN_SD
	print(f"  humans p10 {h['p10']:4.1f}  p25 {h['p25']:4.1f}  median {h['median']:4.1f}  p75 {h['p75']:4.1f}  p90 {h['p90']:4.1f}   (S&D reference)")
	return 0


if __name__ == "__main__":
	sys.exit(main())
