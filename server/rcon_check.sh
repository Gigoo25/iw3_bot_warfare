#!/usr/bin/env bash
# Health check: ask the CoD4X server for its status over rcon (UDP 28960).
#
# The container can stay "up" while the game loop has wedged -- that happened
# twice and silently killed a measurement run, so compose asks the server itself
# rather than the process. Uses bash's /dev/udp because the image has no python,
# no nc and no socat. `head -c` reads the datagram: bash's own `read` chokes on
# the binary prefix, and the reply arrives as one packet.
#
# The rcon password is the local test server's, same one as in server/server.cfg.
set -u
PORT="${RCON_PORT:-28960}"
PW="${RCON_PASSWORD:-botdev123}"

OUT=$(timeout 4 bash -c "
	exec 3<>/dev/udp/127.0.0.1/$PORT || exit 1
	printf '\xff\xff\xff\xffrcon $PW status' >&3
	timeout 3 head -c 32 <&3 2>/dev/null
" 2>/dev/null | tr -d '\377') || true

case "$OUT" in
	*hostname*|*version*|*print*) exit 0 ;;
	*) exit 1 ;;
esac
