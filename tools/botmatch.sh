#!/usr/bin/env bash
# Unattended bot match: build -> container -> N minutes of bots -> telemetry ->
# score vs the human baseline -> diff against the previous run. No human, no demo.
#
#   tools/botmatch.sh [minutes] [label] [map] [gametype]
#   tools/botmatch.sh 12 my-batch mp_backlot sd
#   SKIP_BUILD=1 tools/botmatch.sh 12 label   # score a build already in output/
#
# The bots are 12 CoD4X bots the container fills by itself (server.cfg), the mod
# logs a 5 Hz BT; line per player over the server console (bots_telemetry_out 1,
# because CoD4X throttles games_mp.log to ~5 lines a minute), and tools/btlog.py
# scores it against the human baseline using the same machinery as
# tools/awarescore.py (FDR, bootstrap CIs, overlap, match-to-match yardstick,
# detector, run history).
#
# Human side: --human-src defaults to the human demo CSV, which carries position,
# pitch, yaw, weapon and stance per snapshot. Metrics a demo cannot see (look
# target, look source, trace depth) stay uncovered until someone plays a match on
# a server with the console telemetry on; the report says which.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# bash reads a script incrementally, so editing this file while a match is running
# corrupts the running instance (it did, three times). Work from a copy.
if [ "${BOTMATCH_COPIED:-0}" != "1" ]; then
	export BOTMATCH_COPIED=1
	mkdir -p "$REPO/output"
	cp "$0" "$REPO/output/.botmatch-run.sh"
	exec bash "$REPO/output/.botmatch-run.sh" "$@"
fi

cd "$REPO"
MINUTES="${1:-12}"
LABEL="${2:-run}"
MAP="${3:-mp_backlot}"
GAMETYPE="${4:-sd}"
COMPOSE="docker compose -f server/docker-compose.yml"
OUT="output/botmatch"
LOG="$OUT/$LABEL.telemetry.log"
HUMAN_SRC="${HUMAN_SRC:-output/demos/demo0000}"

say() { printf '\n== %s\n' "$*"; }

if [ "${SKIP_BUILD:-0}" = 1 ]; then
	say "using the mod already in output/ (SKIP_BUILD=1)"
else
	say "rebuilding the mod (so the match runs the current gsc)"
	./build.sh >/dev/null
	./tools/check.sh
fi

mkdir -p "$OUT"

say "restarting the server (down/up: an in-place restart has left it wedged twice,"
say " with rcon not answering and every client dropped)"
# g_gametype is only read at startup, so the mode has to go into the container command
export BOT_GAMETYPE="$GAMETYPE"
export BOT_MAP="$MAP"
$COMPOSE down >/dev/null 2>&1 || true
$COMPOSE up -d cod4x >/dev/null
for _ in $(seq 1 60); do
	python3 tools/rcon.py status >/dev/null 2>&1 && break
	sleep 5
done
python3 tools/rcon.py status >/dev/null 2>&1 || { echo "server never came up" >&2; exit 1; }

say "gametype $GAMETYPE, map $MAP, telemetry on the console channel"
python3 tools/rcon.py "set bots_telemetry 1" >/dev/null
python3 tools/rcon.py "set bots_telemetry_out 1" >/dev/null

# DVARS="set bots_idle_turn_slow 1.5 set bots_glance_wander 0" tunes a variant in one
# build instead of one build per variant; it goes into the run note so the history
# says what the match actually ran with.
# semicolon-separated, so each element is one whole rcon command:
#   DVARS="set bots_glance_dwell_lo 1200; set bots_glance_wander 1"
if [ -n "${DVARS:-}" ]; then
	IFS=';' read -ra DVAR_LIST <<< "$DVARS"
	for d in "${DVAR_LIST[@]}"; do
		d="$(echo "$d" | sed 's/^ *//; s/ *$//')"
		[ -z "$d" ] && continue
		python3 tools/rcon.py "$d" >/dev/null
		CTARGET="$(echo "$d" | awk '{print $2}')"
		say "  dvar: $d -> $CTARGET = $(python3 tools/rcon.py "$CTARGET" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '[0-9.]+$' | head -1)"
	done
fi
# server.cfg ships a rotation that eventually walks the server off this map, and the
# map-change window kills the run (rcon stops answering mid-load). Pin the rotation
# to the one map we are measuring instead of clearing it (empty cvar is engine-specific).
python3 tools/rcon.py "set sv_maprotation \"gametype $GAMETYPE map $MAP\"" >/dev/null
python3 tools/rcon.py "set g_gametype $GAMETYPE" >/dev/null
START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 tools/rcon.py "map $MAP" >/dev/null

# the map command resets the gametype, so wait for the map to actually be up and
# then re-assert it, rather than assuming the map command was enough
for _ in $(seq 1 60); do
	STATUS=$(python3 tools/rcon.py status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' || true)
	case "$STATUS" in
		*"$MAP"*) break ;;
	esac
	sleep 5
done

# Verify what the server is actually running. This is not paranoia: `set g_gametype`
# over rcon is ignored ("will be changed upon restarting"), so earlier matches silently
# ran in whatever mode the rotation had left the server in -- war instead of sd -- which
# is why two pools of the same build differed by 2x on turn metrics.
STATUS=$(python3 tools/rcon.py status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' || true)
# rcon replies carry CoD4 colour codes ("sd^7"), so strip both ANSI and ^. sequences
GAMEMODE=$(python3 tools/rcon.py g_gametype 2>/dev/null \
	| sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\^[0-9]//g' \
	| grep -oE '"[a-z_0-9]+" is: "[a-z_0-9]+"' | head -1 | sed 's/.*is: "//; s/"//' || true)
case "$GAMEMODE" in
	$"$GAMETYPE") ;;
	*)
		echo "server is running gametype '$GAMEMODE', not '$GAMETYPE' -- refusing to" >&2
		echo "score a match in the wrong mode (docker compose logs for the boot args)" >&2
		exit 1
		;;
esac

case "$STATUS" in
	*"$MAP"*) ;;
	*)
		echo "server is not on $MAP -- refusing to score" >&2
		exit 1
		;;
esac

say "verified: gametype $GAMEMODE, map $MAP"

say "letting 12 bots play for $MINUTES minutes (nobody in the server)"
sleep $((MINUTES * 60))
$COMPOSE logs --no-log-prefix --timestamps --since "$START" cod4x 2>/dev/null \
	| grep "BT;" > "$LOG" || true
LINES=$(wc -l < "$LOG")
say "captured $LINES telemetry lines -> $LOG"

if [ "$LINES" -lt 500 ]; then
	echo "only $LINES telemetry lines captured -- the console channel is not" >&2
	echo "producing (bots_telemetry_out=$1?). Check 'docker compose logs' for BT; lines" >&2
	echo "and that the container clock matches: --since $START" >&2
	exit 1
fi

# Cumulative pool: every capture from this build lands in $POOL and the score is
# computed over the whole pool, so repeated matches push the KS noise floor down
# (1/sqrt(n)) instead of each run being judged on ~14 sessions alone.
POOL="${POOL:-$OUT/pool}"
POOL_MAX="${POOL_MAX:-8}"       # newest N logs; older matches stop mattering
mkdir -p "$POOL"
cp "$LOG" "$POOL/$LABEL.telemetry.log"
BOT_LOGS=$(ls -1t "$POOL"/*.telemetry.log 2>/dev/null | head -"$POOL_MAX" | tr '\n' ' ')

say "scoring against $(echo "$BOT_LOGS" | wc -w) pooled match log(s) from $POOL"
python3 tools/btlog.py \
	--humans "$HUMAN_SRC" \
	--bots $BOT_LOGS \
	--map "$MAP" \
	--min-minutes "${MIN_MINUTES:-0.5}" \
	--save "$LABEL" \
	--diff \
	--html "$OUT/$LABEL.html" \
	--note "${NOTE:-untitled run}${DVARS:+ | dvars: ${DVARS}}"
