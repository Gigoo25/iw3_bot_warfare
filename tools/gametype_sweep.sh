#!/bin/bash
# Robustness sweep: runs bots through every gametype on several maps via rcon and
# reports script runtime errors per run plus objective activity from telemetry.
# Needs the server up (tools/livetest.sh or docker compose up -d cod4x).
#
# Usage: tools/gametype_sweep.sh [minutes_per_run=4]
set -e
cd "$(dirname "$0")/.."

MIN="${1:-4}"
COMPOSE="docker compose -f server/docker-compose.yml"
RCON="python3 tools/rcon.py"
LOG=/cod4home/mods/mp_bots/games_mp.log

RUNS="war:mp_strike dm:mp_crossfire dom:mp_crash dom:mp_backlot sd:mp_crossfire sd:mp_strike sab:mp_backlot koth:mp_crash war:mp_vacant war:mp_bloc"

printf "%-6s %-14s %6s %8s %s\n" "gt" "map" "kills" "errors" "objective events"
for run in $RUNS; do
	gt="${run%%:*}"
	map="${run##*:}"
	since=$(date +%s)
	before=$($COMPOSE exec -T cod4x sh -c "wc -l < $LOG" 2>/dev/null || echo 0)
	$RCON "g_gametype $gt" >/dev/null
	$RCON "map $map" >/dev/null || true
	sleep $(( MIN * 60 ))
	chunk=$($COMPOSE exec -T cod4x sh -c "tail -n +$((before + 1)) $LOG")
	kills=$(echo "$chunk" | grep -c " K;" || true)
	errors=$($COMPOSE logs --since "$(( $(date +%s) - since + 5 ))s" --no-log-prefix cod4x 2>&1 | grep -c "script runtime error" || true)
	obj=$(echo "$chunk" | grep -oE "BE;[^;]*;[^;]*;(dom|sd|sab|hq|koth)[^ ]*" | awk -F';' '{print $4}' | sort | uniq -c | sort -rn | head -4 | awk '{printf "%s=%s ", $2, $1}')
	wp=$($COMPOSE logs --since "$(( $(date +%s) - since + 5 ))s" --no-log-prefix cod4x 2>&1 | grep -oE "Loaded [0-9]+ waypoints|No waypoints loaded" | tail -1)
	printf "%-6s %-14s %6s %8s %s [%s]\n" "$gt" "$map" "$kills" "$errors" "$obj" "$wp"
	if [ "$errors" != "0" ]; then
		$COMPOSE logs --since "$(( $(date +%s) - since + 5 ))s" --no-log-prefix cod4x 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -A8 "script runtime error" | head -20
	fi
done
