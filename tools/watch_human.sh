#!/usr/bin/env bash
# Wait for a human to join the local test server, then record them.
#
#   tools/watch_human.sh [minutes]
#
# Why: the demo exporter only captures network clients, so every measurement of a
# human has needed someone to play. This waits for a non-bot client to appear,
# prints their name and client id, starts the server-side demo recording for them
# (record <client>, which CoD4X accepts for any client), and leaves the console
# telemetry running so the same session is usable by tools/btlog.py as well.
#
# Nothing here changes the bot behaviour: the dvars are put back to the adopted
# defaults first, so a human recording sits next to a comparable bot pool.
set -euo pipefail
cd "$(dirname "$0")/.."

RCON="python3 tools/rcon.py"
COMPOSE="docker compose -f server/docker-compose.yml"

say() { printf '\n== %s\n' "$*"; }

# --attach: do not recreate the container or touch the map. Use it when the server is
# already up (and mid-match): we only need to notice you and start recording, because
# restarting the server would drop you and change what the bots are doing.
ATTACH=0
[ "${1:-}" = "--attach" ] && { ATTACH=1; shift; }
MINS="${1:-15}"

if [ "$ATTACH" = "1" ]; then
	say "attaching to the running server (no restart, no map change)"
else
	say "putting the bots back on the adopted defaults"
	for d in "set bots_steady_look 0" "set bots_acq_slow 1.8" "set bots_pursuit_gain 1.0" \
	         "set bots_glance_dwell_lo 1200" "set bots_glance_dwell_hi 3500" \
	         "set bots_glance_wander 0" "set bots_idle_turn_slow 1.0" \
	         "set bots_max_turn_rate 450" "set bots_telemetry 1" "set bots_telemetry_out 2"; do
		$RCON "$d" >/dev/null 2>&1 || true
	done
	$RCON "set g_gametype sd" >/dev/null 2>&1 || true
	START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "   telemetry is now logging to games_mp.log AND the console from $START"
fi

say "waiting for a human client (bots report address 'bot')"
CLIENT=""
NAME=""
for _ in $(seq 1 "${WAIT_TICKS:-360}"); do
	STATUS=$($RCON status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' || true)
	# the address column is third from the right (address, qport, rate); names can
	# contain spaces, so fixed column positions are not safe here
	while read -r num addr rest; do
		[ "$addr" = "bot" ] && continue
		case "$addr" in
			*[0-9].[0-9]*) ;;
			*) continue ;;
		esac
		if [ -z "$CLIENT" ]; then
			CLIENT="$num"
			NAME="$rest"
		fi
	done < <(echo "$STATUS" | sed 's/\^.[0-9]//g' \
		| awk '$0 ~ / [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)? +[0-9]+ +[0-9]+ *$/ { print $1, $(NF-2), $0 }')
	if [ -n "$CLIENT" ]; then
		break
	fi
	sleep 5
done

if [ -z "$CLIENT" ]; then
	echo "no human client appeared within the wait window" >&2
	exit 1
fi

say "human client $CLIENT ($NAME) is in -- starting the server-side demo recording"
$RCON "record $CLIENT"
echo
echo "Play mp_backlot S&D for about $MINS minutes. Everything is recorded from here;"
echo "you do not need to do anything else in game. Stop it early with:"
echo "    python3 tools/rcon.py stoprecord $CLIENT"
echo
# Watch for the CoD4X hang: the container stays up but the game loop stops
# emitting anything (it has happened three times on this host, twice with no
# human in the server at all). Detect it, pull what we have, and say so, rather
# than sitting here for the rest of the countdown.
STALE_AFTER="${STALE_AFTER:-90}"     # seconds without a telemetry line
last_seen=$(date +%s)

for i in $(seq 1 "$((MINS * 2))"); do
	sleep 15
	now=$(date +%s)

	if [ -n "$CLIENT" ]; then
		if $COMPOSE logs --since 20s --no-log-prefix cod4x 2>/dev/null | grep -q "BT;"; then
			last_seen=$now
			printf '.'
		elif [ $((now - last_seen)) -ge "$STALE_AFTER" ]; then
			echo
			echo "!! no telemetry for ${STALE_AFTER}s -- the CoD4X server has hung again"
			echo "   (container up, game loop dead; it is an engine hang, not your connection)"
			echo "   pulling what was captured so far; the demo may be truncated"
			break
		fi
	fi
done
echo
say "stopping the recording"
$RCON "stoprecord $CLIENT" 2>/dev/null || echo "   (server not answering; the demo may be incomplete)"
sleep 3

say "pulling the artefacts"
mkdir -p output/human
docker compose -f server/docker-compose.yml exec -T cod4x \
	sh -c 'ls -1t /cod4home/demos/*.dm_1 2>/dev/null | head -3' | while read -r f; do
	[ -n "$f" ] || continue
	base=$(basename "$f")
	[ -e "output/human/$base" ] || docker compose -f server/docker-compose.yml cp \
		"cod4x:/cod4home/demos/$base" "output/human/$base" >/dev/null 2>&1 || true
done
docker compose -f server/docker-compose.yml exec -T cod4x \
	cat /cod4home/mods/mp_bots/games_mp.log > output/human/games_mp.log 2>/dev/null || true

echo "  output/human/:"
ls -la output/human/ 2>/dev/null || echo "    (nothing copied -- check the container)"
say "done. Score it with:"
echo "  tools/btlog.py --humans output/human/games_mp.log --bots <a bot pool> --save human-sd"
echo "  tools/demo/extract.sh output/human/<demo>.dm_1   # then tools/awarescore.py"
