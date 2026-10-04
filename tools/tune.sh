#!/usr/bin/env bash
# One tuning experiment, run the way the evidence requires.
#
#   tools/tune.sh <label> <matches> [dvars] [reference-pool-label]
#
# Why this exists: a single 15 min match swings OVERALL by ~5 points and the
# detector AUC by ~0.06 on nothing at all, so one match cannot decide a change.
# This runs N matches into a pool for the label, scores the pool, and diffs it
# against a reference pool, printing the resolved/new tells -- which is the part
# of the output that actually means something. It also verifies the gametype and
# map before every match, because a match in the wrong mode is how a whole
# evening of arms was once invalidated.
#
# Example:
#   tools/tune.sh pursuit-0.8 2 "set bots_pursuit_gain 0.8" sd_shipped
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

LABEL="${1:?usage: tune.sh <label> <matches> [dvars] [reference]}"
MATCHES="${2:-2}"
DVARS="${3:-}"
REF="${4:-}"

export POOL="output/botmatch/pool-$LABEL"
export POOL_MAX="${POOL_MAX:-6}"
export DVARS

echo "== experiment '$LABEL': $MATCHES verified S&D match(es), pool $POOL"
[ -n "$DVARS" ] && echo "   dvars: $DVARS"
mkdir -p "$POOL"

for i in $(seq 1 "$MATCHES"); do
	echo "== match $i/$MATCHES"
	./tools/botmatch.sh 15 "$LABEL-m$i" mp_backlot sd
done

echo
echo "== verdict for '$LABEL' (pool of $MATCHES matches)"
POOLS="$LABEL=$POOL"
[ -n "$REF" ] && POOLS="$REF=output/botmatch/pool-$REF $POOLS"
# shellcheck disable=SC2086
python3 tools/poolscore.py --humans output/demos/demo0000 --map mp_backlot --reps 400 $POOLS --save

if [ -n "$REF" ]; then
	echo
	python3 tools/scorecmp.py diff "$REF" "$LABEL"
	echo
	echo "Read it as: RESOLVED tells are wins, NEW TELLs are regressions, and anything"
	echo "marked '*' moved less than the KS noise floor (sampling noise, not a result)."
	echo "The '[95% CI below 0]' tags are the ones to trust: that is the difference between"
	echo "two pools bootstrapped against the same humans, not one run's noise floor."
	echo
	# durable decision record, so 'why did we adopt this?' is answerable later
	python3 - "$REF" "$LABEL" "$DVARS" <<'PY2'
import glob, json, sys, os
sys.path.insert(0, "tools")
import scorecmp
ref, label, dvars = sys.argv[1], sys.argv[2], sys.argv[3]
def newest(pat):
    hits = sorted(glob.glob(f"scores/*{pat}*.json"))
    return scorecmp.load_run(hits[-1]) if hits else None
a, b = newest(ref), newest(label)
out = {"label": label, "reference": ref, "dvars": dvars,
       "reference_label": (a or {}).get("run", {}).get("label"),
       "reference_overall": (a or {}).get("overall"), "overall": (b or {}).get("overall"),
       "reference_auc": (a or {}).get("auc"), "auc": (b or {}).get("auc"),
       "reference_tells": len([1 for v in ((a or {}).get("metrics") or {}).values()
                               if (v.get("q") or 1) < .05]),
       "tells": len([1 for v in ((b or {}).get("metrics") or {}).values()
                     if (v.get("q") or 1) < .05]),
       "matches": len((b or {}).get("run", {}).get("bots") or []),
       "bot_sessions": (b or {}).get("run", {}).get("sample", {}).get("bot_sessions")}
d = out["overall"] - out["reference_overall"] if out["overall"] is not None and out["reference_overall"] is not None else None
out["overall_delta"] = round(d, 2) if d is not None else None
out["note"] = ("adopt only with more matches than the reference, no new tells, and a "
               "positive overall delta; see TODO.md for the arms already tried")
path = f"scores/{label}-verdict.json"
with open(path, "w") as f:
    json.dump(out, f, indent=1)
print(f"wrote {path}")
PY2
fi
