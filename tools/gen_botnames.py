#!/usr/bin/env python3
"""
Generates scriptdata/botnames.txt: fictional handles styled after names seen on
live CoD4x servers in 2026 (cod4xtracker.com, gametracker): plain words and
nicknames, regional first names/diminutives (the PC scene is EU/LatAm heavy),
pipe/bracket/equals clan tags shared by a few "clan-mates", .:x:. decorations,
number suffixes, a little leetspeak and ^color codes. No real players' handles.

Usage: tools/gen_botnames.py [--seed N] [--count N]
"""
import argparse
import random
import re

WORDS = """Flash Zero Stealth Eagle Resident Himera Optiplex Default Lobby Tuna Morfin
blaze frost toast pickle nugget biscuit spud twix doughnut raptor viper wolfy
nox kaizer ronin kami ziggy rusty smokey tank crash chupa zorro elmo pingu
gonzo lemmy mongo tonic jojo vinnie dexter fluffy nightfall shadow ghost storm
falcon hawk cobra mamba jackal bison moose badger otter ferret gecko kraken
yeti goblin troll pirate bandit outlaw sheriff ranger nomad drifter hobo
potato waffle pancake noodle taco burrito pretzel muffin cookie mango kiwi
pepper chili wasabi ginger cactus pebble boulder anvil hammer wrench bolt
rocket turbo diesel nitro piston gearbox tractor forklift sparky fuse
reaper sniper medic rookie veteran major captain sarge corporal private
lucky dizzy grumpy sleepy sneaky clumsy lazy crazy happy angry salty spicy
Ipad Laptop Nokia Pentium Radeon Geforce Windows Linux Modem Pager Toaster
Kebab Vodka Borscht Paprika Gulyas Pierogi Tapas Sushi Chorizo Feijoada""".split()

REGIONAL = """Laca Csabka Ocsike Tute Terre Pisti Gabesz Bence Zoli Feri Jani Ricsi
Kuba Maciek Bartek Tomek Kacper Wojtek Piotrek Kamil Szymon Grzesiek
Vova Dima Sasha Kolya Misha Artem Ruslan Igor Oleg Denis Zhenya Slava
Joao Rafa Pedrinho Thiago Gabriel Lucas Mateus Brenno Caio Diego Nando
Pepe Paco Nacho Javi Chema Alvaro Iker Unai Sergio Rodri Kike Manu
Luca Matteo Gianni Enzo Marco Paolo Simone Fede Ale Nico Tommi
Jonas Lukas Felix Moritz Basti Flo Tobi Jannik Timo Nils Malte Benni
Bram Jaap Pieter Sander Stijn Ruud Gijs Thijs Wout Kees
Lars Sven Emil Kalle Anton Rasmus Mikko Tuomas Jussi Olli Aksel
Mehmet Emre Burak Yusuf Can Kerem Ali Deniz Onur Baris
Andrei Vlad Mihai Ionut Cosmin Radu Bogdan Sorin Florin
Kev Dave Gaz Baz Robbo Jonno Deano Stu Jammy Scotty Olly Wezza Matty
Theo Hugo Louis Jules Maxime Bastien Remi Yann Quentin""".split()

LATIN_STYLE = """EL_SICARIO El_Loco ElChapo_jr LaBestia ElGringo ElNegro Chamaco
Guerrero Pistolero Bandido Diablito Tiburon Lobito Gato_Negro""".split()

TAGS = ["KsG", "AoD", "FF", "SoS", "MG", "TuD", "NwA", "eXe", "RoK", "HuN", "VnX", "BoB",
	"xDx", "ZzZ", "LoL", "PoW", "GoD", "1st", "SAS", "UKR"]
TAG_FORMATS = ["|{t}|{n}", "{t}|{n}", "[{t}] {n}", "[{t}]{n}", "={t}={n}", "{n}#{t}", "{t}.{n}", "-{t}-{n}"]
COLORS = ["^1", "^2", "^3", "^4", "^5", "^6"]
LEET = str.maketrans({"e": "3", "a": "4", "o": "0", "i": "1", "s": "5"})


def visible(name):
	return re.sub(r"\^[0-9]", "", name)


def styled(rng, base):
	r = rng.random()
	if r < 0.12:
		return base.lower()
	if r < 0.18:
		return base.upper()
	if r < 0.24:
		return base + str(rng.choice([rng.randint(1, 99), rng.randint(1985, 2009)]))
	if r < 0.28:
		return base + "_" + rng.choice(["xd", "pl", "br", "ru", "hu", "tr", "es", "nl", "pro", "gg", "ez"])
	if r < 0.32:
		return base.lower().translate(LEET)
	if r < 0.36:
		return ".:" + base + ":."
	if r < 0.40:
		c = rng.choice(COLORS)
		return c + base + "^7"
	return base


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--seed", type=int, default=4)
	ap.add_argument("--count", type=int, default=320)
	args = ap.parse_args()
	rng = random.Random(args.seed)

	names = set()
	# fixed few that every CoD4 lobby has
	for n in ["Unknown Soldier", "noobtuber", "lagger", "AFK", "Default", "Old Man Jenkins", "Dad"]:
		names.add(n)

	# clans: each tag used by 2-4 members with the same format
	for t in rng.sample(TAGS, 12):
		fmt = rng.choice(TAG_FORMATS)
		for _ in range(rng.randint(2, 4)):
			n = fmt.format(t=t, n=rng.choice(WORDS + REGIONAL))
			if len(visible(n)) <= 15:
				names.add(n)

	pool = [("w", WORDS)] * 4 + [("r", REGIONAL)] * 3 + [("l", LATIN_STYLE)]
	while len(names) < args.count:
		_, src = rng.choice(pool)
		base = rng.choice(src)
		if rng.random() < 0.08:
			base = base + rng.choice(WORDS).capitalize()  # compound: NinjaTuna, BigDog style
		n = styled(rng, base)
		if 2 <= len(visible(n)) <= 15:
			names.add(n)

	out = sorted(names, key=lambda _: rng.random())
	with open("scriptdata/botnames.txt", "wb") as f:
		f.write(("\r\n".join(out) + "\r\n").encode())
	print(f"{len(out)} names written; sample: " + ", ".join(out[:25]))


if __name__ == "__main__":
	main()
