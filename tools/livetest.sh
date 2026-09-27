#!/bin/bash
# Build, deploy to the containerized server with a fresh match log, let bots play
# for N minutes, then save the log and print combat + movement stats.
#
# Usage: tools/livetest.sh [minutes=12] [out.log] [gametype map]
#   e.g. tools/livetest.sh 16 output/sd.log sd mp_backlot   (locks the rotation to that map/mode)
set -e
cd "$(dirname "$0")/.."

MINUTES="${1:-12}"
OUT="${2:-output/livetest_$(date +%Y%m%d_%H%M%S).log}"
GT="$3"
MAP="$4"
COMPOSE="docker compose -f server/docker-compose.yml"
LOG=/cod4home/mods/mp_bots/games_mp.log

./tools/check.sh >/dev/null
./build.sh >/dev/null

$COMPOSE stop cod4x >/dev/null 2>&1 || true
docker run --rm -v server_cod4x-home:/h debian:bookworm-slim sh -c ": > /h/mods/mp_bots/games_mp.log" 2>/dev/null || true
$COMPOSE up -d cod4x >/dev/null 2>&1
START=$(date +%s)

# fail fast on load errors
for _ in $(seq 1 30); do
	if $COMPOSE logs --since "$(( $(date +%s) - START + 5 ))s" cod4x 2>&1 | grep -qE "script compile error|Sys_Error"; then
		$COMPOSE logs --no-log-prefix cod4x 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -A10 -E "script compile error|Sys_Error"
		exit 1
	fi
	if $COMPOSE logs --since "$(( $(date +%s) - START + 5 ))s" cod4x 2>&1 | grep -q "Steam: Server connected"; then
		break
	fi
	sleep 3
done

if [ -n "$GT" ] && [ -n "$MAP" ]; then
	# rcon isn't always answering right after "Steam: Server connected"
	for _ in $(seq 1 20); do python3 tools/rcon.py status >/dev/null 2>&1 && break; sleep 3; done
	python3 tools/rcon.py "set sv_maprotation gametype $GT map $MAP" >/dev/null
	python3 tools/rcon.py "g_gametype $GT" >/dev/null
	# output produced during an rcon command (the whole map load) goes to the
	# rcon reply, not the console log: capture it and surface load/script errors
	loadout=$(python3 tools/rcon.py --wait 20 "map $MAP" 2>&1 || true)
	echo "$loadout" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "waypoints from|script (compile|runtime) error" -A6 | head -20
	sleep 15
	$COMPOSE exec -T cod4x sh -c ": > $LOG"
fi

echo "running ${MINUTES}m of bot matches${GT:+ ($GT on $MAP)}..."
sleep $(( MINUTES * 60 ))

$COMPOSE exec -T cod4x cat "$LOG" > "$OUT"
echo "log: $OUT"
echo "script runtime errors: $($COMPOSE logs --since "$(( $(date +%s) - START + 5 ))s" --no-log-prefix cod4x 2>&1 | grep -c 'script runtime error' || true)"
echo
python3 tools/matchstats.py "$OUT"
echo
python3 tools/movestats.py "$OUT"
