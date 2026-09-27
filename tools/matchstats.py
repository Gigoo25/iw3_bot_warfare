#!/usr/bin/env python3
"""
Summarize a CoD4 games_mp.log and compare it with a human baseline.

Baseline: stats.sexycod4.de (UltraStats over ~2.2M human kills on public CoD4
servers, fetched 2026-09-26): headshot kills 10.2% of all kills, 12.1% of
bullet kills; grenade ~6.5%, knife ~1.2%. Top human K/D there ~1.2-1.9.

Usage:
  docker compose -f server/docker-compose.yml exec -T cod4x cat /cod4home/mods/mp_bots/games_mp.log | tools/matchstats.py
  tools/matchstats.py games_mp.log [--since-last-init]
"""
import argparse
import collections
import sys

BASELINE = {
	"hs_kills_pct": (10.2, "headshot kills / all kills"),
	"hs_bullet_pct": (12.1, "headshot kills / bullet kills"),
	"nade_pct": (6.5, "grenade splash kills / all kills"),
	"knife_pct": (1.2, "knife kills / all kills"),
}

BULLET = {"MOD_RIFLE_BULLET", "MOD_PISTOL_BULLET", "MOD_HEAD_SHOT"}


def weapon_class(w):
	w = w.replace("_mp", "")
	base = w.split("_")[0]
	if base in ("m16", "ak47", "m4", "g3", "g36c", "m14", "mp44"):
		return "assault"
	if base in ("mp5", "skorpion", "uzi", "ak74u", "p90"):
		return "smg"
	if base in ("saw", "rpd", "m60e4"):
		return "lmg"
	if base in ("winchester1200", "m1014"):
		return "shotgun"
	if base in ("m40a3", "m21", "dragunov", "remington700", "barrett"):
		return "sniper"
	if base in ("beretta", "colt45", "usp", "deserteagle", "deserteaglegold"):
		return "pistol"
	return "other"


def hit_group(loc):
	if loc in ("head", "helmet", "neck"):
		return "head/neck"
	if loc.startswith("torso"):
		return "torso"
	if "arm" in loc or "hand" in loc:
		return "arms"
	if "leg" in loc or "foot" in loc:
		return "legs"
	return "other"


def parse(lines, since_last_init):
	if since_last_init:
		start = 0
		for i, line in enumerate(lines):
			if "InitGame:" in line:
				start = i
		lines = lines[start:]
	events = []
	for line in lines:
		parts = line.strip().split(" ", 1)
		if len(parts) < 2:
			continue
		f = parts[1].split(";")
		if f[0] in ("D", "K") and len(f) >= 13:
			events.append({
				"type": f[0], "victim": f[4], "attacker": f[8], "weapon": f[9],
				"dmg": int(f[10] or 0), "mod": f[11], "loc": f[12],
			})
	return events


def pct(a, b):
	return 100.0 * a / b if b else 0.0


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("log", nargs="?")
	ap.add_argument("--since-last-init", action="store_true", help="only the most recent map")
	args = ap.parse_args()
	lines = open(args.log, errors="replace").readlines() if args.log else sys.stdin.readlines()
	ev = parse(lines, args.since_last_init)

	kills = [e for e in ev if e["type"] == "K" and e["attacker"] and e["attacker"] != e["victim"]]
	dmg = [e for e in ev if e["type"] == "D"]
	if not kills:
		print("no kills in log")
		return 1

	bullet_kills = [k for k in kills if k["mod"] in BULLET]
	hs = [k for k in kills if k["mod"] == "MOD_HEAD_SHOT"]
	got = {
		"hs_kills_pct": pct(len(hs), len(kills)),
		"hs_bullet_pct": pct(len(hs), len(bullet_kills)),
		"nade_pct": pct(sum(k["mod"] == "MOD_GRENADE_SPLASH" for k in kills), len(kills)),
		"knife_pct": pct(sum(k["mod"] == "MOD_MELEE" for k in kills), len(kills)),
	}

	print(f"kills {len(kills)}   damage events {len(dmg)}")
	print("\nvs human baseline")
	for key, (base, label) in BASELINE.items():
		flag = "  <-- off" if abs(got[key] - base) > max(3.0, base * 0.5) else ""
		print(f"  {label:34s} bots {got[key]:5.1f}%   humans {base:5.1f}%{flag}")

	print("\nhit locations (all damage)")
	hg = collections.Counter(hit_group(e["loc"]) for e in dmg)
	for g, n in hg.most_common():
		print(f"  {g:10s} {pct(n, len(dmg)):5.1f}%")

	print("\nkills by weapon class")
	wc = collections.Counter(weapon_class(k["weapon"]) for k in kills)
	for g, n in wc.most_common():
		print(f"  {g:10s} {pct(n, len(kills)):5.1f}%")

	print("\ntop weapons (kills)")
	for w, n in collections.Counter(k["weapon"] for k in kills).most_common(10):
		print(f"  {w:28s} {n:4d}  {pct(n, len(kills)):4.1f}%")

	# K/D spread: humans in a pub range roughly 0.4-2.5 with most 0.7-1.3
	# per-skill headshot rate (skill from BT telemetry lines, if present)
	skill = {}
	for line in lines:
		if " BT;" in line:
			f = line.strip().split(" ", 1)[1].split(";")
			if len(f) >= 16 and f[3] == "1":
				skill[f[2]] = f[15]
	if skill:
		print("\nheadshot kills by bot skill")
		by = collections.defaultdict(lambda: [0, 0])
		for k in kills:
			if k["attacker"] in skill:
				by[skill[k["attacker"]]][0] += k["mod"] == "MOD_HEAD_SHOT"
				by[skill[k["attacker"]]][1] += 1
		for sk in sorted(by):
			h, n = by[sk]
			print(f"  skill {sk}: {h:3d}/{n:3d} = {pct(h, n):4.1f}%")

	k_by = collections.Counter(k["attacker"] for k in kills)
	d_by = collections.Counter(k["victim"] for k in kills)
	players = sorted(set(k_by) | set(d_by), key=lambda p: -(k_by[p] / max(d_by[p], 1)))
	print("\nK/D")
	for p in players:
		print(f"  {p:24s} {k_by[p]:3d}/{d_by[p]:3d}  {k_by[p] / max(d_by[p], 1):4.2f}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
