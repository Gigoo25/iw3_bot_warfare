#!/usr/bin/env python3
"""
Bridges feedback marks from chat to the bots: CoD4x doesn't hand chat to
scripts, so this follows the server log for "!look", "!move", "!stuck",
"!nade", "!dumb", "!ok" said by a player and sets the bots_mark dvar over
rcon; the mod then logs a MARK line with the watched bot's state.

Usage: tools/markwatch.py        (runs until stopped)
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from rcon import rcon  # noqa: E402

CATS = {"look", "move", "stuck", "nade", "dumb", "ok"}
SAY = re.compile(r"\bsay(?:team)?;[^;]*;(\d+);[^;]*;\W*!(\w+)")


def main():
	compose = os.path.join(os.path.dirname(__file__), "..", "server", "docker-compose.yml")
	proc = subprocess.Popen(
		["docker", "compose", "-f", compose, "exec", "-T", "cod4x", "tail", "-n", "0", "-F", "/cod4home/mods/mp_bots/games_mp.log"],
		stdout=subprocess.PIPE, text=True, errors="replace")
	for line in proc.stdout:
		m = SAY.search(line)
		if m and m.group(2).lower() in CATS:
			rcon("127.0.0.1", 28960, "botdev123", f'set bots_mark "{m.group(1)} {m.group(2).lower()}"')
			print("mark", m.group(1), m.group(2), flush=True)
	return 0


if __name__ == "__main__":
	sys.exit(main())
