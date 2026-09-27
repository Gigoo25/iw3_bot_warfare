#!/bin/sh
# Merge the CoD4x files into the game basepath, then start the server.
set -e
BASE=/cod4

if [ ! -f "$BASE/main/iw_00.iwd" ]; then
	echo "entrypoint: no CoD4 game data in $BASE (run: STEAM_USER=<name> docker compose run --rm steamcmd)" >&2
	exit 1
fi

cp -u /opt/cod4x/main/*.iwd "$BASE/main/"
cp -u /opt/cod4x/zone/*.ff "$BASE/zone/"

exec /opt/cod4x/cod4x18_dedrun "$@"
