#!/usr/bin/env bash
# A/B on mp_backlot S&D only, same harness, same duration, nothing destructive:
#   arm A  current working tree (with the console-telemetry instrument)
#   arm B  2208e03, the commit BEFORE the humanize pass, plus the same instrument
# Both runs land in scores/ and diff against each other on the metrics they share
# (scorecmp prints "overall, common metrics" because arm B's older build logs two
# telemetry columns fewer, so the plain OVERALL numbers are not comparable).
set -euo pipefail
cd "$(dirname "$0")/.."

MINS="${1:-15}"
OLD_REF="${OLD_REF:-2208e03}"
WT=/tmp/oldbuild

echo "=== arm A: current build, ${MINS} min"
./tools/botmatch.sh "$MINS" "ab-current-${MINS}m" mp_backlot sd

echo
echo "=== arm B: $OLD_REF (pre-humanize), same harness"
if [ ! -d "$WT" ]; then
	git worktree add --detach "$WT" "$OLD_REF" >/dev/null
fi
python3 - "$WT" <<'PY'
import sys, re
wt = sys.argv[1]
p = f"{wt}/maps/mp/bots/_bot.gsc"
s = open(p).read()
if "bots_telemetry_out" in s:
    print("instrument already present")
    raise SystemExit
m = re.search(r'^(\t+)logprint\( "BT;.*?" \);$', s, re.M)
if not m:
    raise SystemExit("could not find the BT logprint line")
indent = m.group(1)
body = m.group(0)
line = body[len(indent):]
switch = (
    f'{indent}line = {line[len("logprint( "):-len(" );")]};\n'
    f'{indent}out = getdvarint( "bots_telemetry_out" );\n'
    f'{indent}if ( out != 1 ) {{ logprint( line ); }}\n'
    f'{indent}if ( out ) {{ print( line ); }}'
)
s = s.replace(body, switch)
s = s.replace('''	if ( getdvar( "bots_telemetry" ) == "" )''',
              '''	if ( getdvar( "bots_telemetry_out" ) == "" )
	{
		setdvar( "bots_telemetry_out", 0 );
	}
	
	if ( getdvar( "bots_telemetry" ) == "" )''', 1)
open(p, "w").write(s)
print("instrument applied to the pre-humanize tree")
PY
(cd "$WT" && ./build.sh >/dev/null)
cp output/z_svr_bots.iwd /tmp/current-build.iwd.bak
cp "$WT/output/z_svr_bots.iwd" output/z_svr_bots.iwd
SKIP_BUILD=1 ./tools/botmatch.sh "$MINS" "ab-prehumanize-${MINS}m" mp_backlot sd

echo
echo "=== restoring the current build"
cp /tmp/current-build.iwd.bak output/z_svr_bots.iwd
./build.sh >/dev/null

echo
echo "=== A/B result (common metrics only)"
python3 tools/scorecmp.py diff "ab-current-${MINS}m" "ab-prehumanize-${MINS}m" || true
