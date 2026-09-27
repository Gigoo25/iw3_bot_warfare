#!/usr/bin/env python3
"""
Human movement baseline from a CoD4 demo, measured with the same code as our
bot telemetry (tools/movestats.py).

Input: <demo>.players.csv / <demo>.meta.json from tools/demo/extract.sh
(reference parser github.com/Iswenzz/CoD4-DM1 + tools/demo/export.cpp).

eFlags bits (verified against speeds on a NamelessNoobs S&D demo):
  bit 2 crouch, bit 3 prone, bit 6 firing, bit 18 ADS.

Usage: tools/demostats.py output/demos/demo0000 [--per-player]
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
import movestats  # noqa: E402

STEP = 0.2  # movestats sample period


def segments(rows):
	"""Split one player's rows into runs of consecutive ~50ms snapshots."""
	seg = [rows[0]]
	for a, b in zip(rows, rows[1:]):
		if int(b["t"]) - int(a["t"]) <= 60:
			seg.append(b)
		else:
			yield seg
			seg = [b]
	yield seg


def resample(seg):
	"""5Hz samples in movestats' format; velocity from 50ms finite differences."""
	out = []
	t0 = int(seg[0]["t"])
	next_t = t0
	for a, b in zip(seg, seg[1:]):
		tb = int(b["t"])
		if tb < next_t:
			continue
		dt = (tb - int(a["t"])) / 1000
		if dt <= 0:
			continue
		vx = (float(b["x"]) - float(a["x"])) / dt
		vy = (float(b["y"]) - float(a["y"])) / dt
		vz = (float(b["z"]) - float(a["z"])) / dt
		if math.hypot(vx, vy) > 600:  # decode glitch / teleport
			continue
		ef = int(b["eflags"])
		stance = "prone" if ef >> 3 & 1 else "crouch" if ef >> 2 & 1 else "stand"
		pitch = float(b["pitch"])
		out.append({
			"x": float(b["x"]), "y": float(b["y"]), "z": float(b["z"]),
			"vx": vx, "vy": vy, "vz": vz,
			"pitch": pitch if pitch >= 0 else pitch + 360, "yaw": float(b["yaw"]),
			"stance": stance, "ads": 10 if ef >> 18 & 1 else 0, "tgt": False,
		})
		next_t = tb + int(STEP * 1000)
	return out


def bot_clients(meta, names):
	"""Clients that are bots: 0 ping on every scoreboard ("b" command) they appear
	in, or a bot-style name ([BOT] tag, bot<N> seed bots)."""
	pings = collections.defaultdict(list)
	for c in meta["serverCommands"]:
		f = c["text"].split()
		if not f or f[0] != "b" or len(f) < 5:
			continue
		n, rest = int(f[1]), f[5:]
		for i in range(n):
			g = rest[i * 7:(i + 1) * 7]
			if len(g) >= 3:
				pings[g[0]].append(int(g[2]))
	bots = {c for c, p in pings.items() if p and max(p) == 0}
	for c, n in names.items():
		if re.fullmatch(r"bot\d+", n.strip().lower()) or "[bot]" in n.lower():
			bots.add(c)
	return bots


def chat_summary(meta, bot_names=()):
	bot_names = {n.lower() for n in bot_names}
	msgs = []
	for c in meta["serverCommands"]:
		m = re.match(r'^h "(.*)"$', c["text"])
		if not m:
			continue
		body = re.sub(r"[\x00-\x1f]", "", re.sub(r"\^.", "", m.group(1)))
		if ": " not in body or body.startswith("(NN)"):
			continue  # server announcements
		who, text = body.split(": ", 1)
		sender = re.sub(r"^\((GAME_DEAD|DEAD|Team|GAME_TEAM)\)", "", who).strip().lower()
		if sender in bot_names or any(b and b in sender for b in bot_names):
			continue  # bot chatter
		if sender.startswith("server"):
			continue  # admin plugin announcements / PMs
		if msgs and msgs[-1] == (who, text.strip()):
			continue  # reliable command resent
		msgs.append((who, text.strip()))
	if not msgs:
		return
	lens = sorted(len(t) for _, t in msgs)
	dead = sum("(GAME_DEAD)" in w or "(DEAD)" in w for w, _ in msgs)
	team = sum("(Team)" in w or "(GAME_TEAM)" in w for w, _ in msgs)
	lower = sum(t == t.lower() for _, t in msgs)
	print(f"\nchat: {len(msgs)} messages, median length {lens[len(lens) // 2]}, "
		f"lowercase {100 * lower // len(msgs)}%, from dead players {100 * dead // len(msgs)}%, team chat {100 * team // len(msgs)}%")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("base", help="path without extension, e.g. output/demos/demo0000")
	ap.add_argument("--per-player", action="store_true")
	args = ap.parse_args()

	rows = list(csv.DictReader(open(args.base + ".players.csv")))
	meta = json.load(open(args.base + ".meta.json"))
	names = {k: re.sub(r"\^.", "", v["name"]) for k, v in meta["names"].items()}

	bots = bot_clients(meta, names)
	by = collections.defaultdict(list)
	for r in rows:
		by[r["client"]].append(r)

	per, botper = {}, {}
	for client, rs in by.items():
		name = names.get(client, "#" + client)
		isbot = client in bots
		rs.sort(key=lambda r: int(r["t"]))
		samples = []
		for seg in segments(rs):
			if len(seg) >= 60:  # >= 3s continuous
				samples += resample(seg)
		m = movestats.metrics(samples)
		if m:
			(botper if isbot else per)[name] = m

	agg, minutes = movestats.avg(list(per.values()))
	bagg, bminutes = movestats.avg(list(botper.values())) if botper else ({}, 0)
	print(f"humans: {len(per)} players, {minutes:.1f} player-min (decoded); excluded bots: {len(botper)} ({bminutes:.1f} player-min)")
	skip = {"in combat (has target) %", "idle gap between fights (s, median)"}
	print(f"  {'metric':34s} {'humans':>7s} {'their bots':>10s}")
	for k in movestats.GUESS:
		if (k in agg or k in bagg) and k not in skip:
			h = f"{agg[k]:7.1f}" if k in agg else f"{'-':>7s}"
			b = f"{bagg[k]:10.1f}" if k in bagg else f"{'-':>10s}"
			print(f"  {k:34s} {h} {b}")
	if args.per_player:
		for name, m in sorted(per.items()):
			print(f"  {name:20s} {m['_minutes']:5.1f}min sprint {m['sprint %']:4.1f} crouch {m['crouch %']:4.1f} still {m['still %']:4.1f}")
	chat_summary(meta, [names[c] for c in bots if c in names])
	return 0


if __name__ == "__main__":
	sys.exit(main())
