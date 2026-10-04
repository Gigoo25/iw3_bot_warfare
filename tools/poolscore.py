#!/usr/bin/env python3
"""
Score and compare several telemetry pools in one go -- tools/poolscore.py.

Every tuning arm of the unattended loop produces a directory of match logs under
output/botmatch/ (POOL=... tools/botmatch.sh). Scoring them one at a time and
eyeballing the console invites exactly the mistake this tool exists to prevent:
comparing two runs scored with different session settings. Here every pool is
scored through the same code, the same --min-minutes/--settle, the same human
baseline, and stored as a run, so the comparison is one table:

  tools/poolscore.py --humans output/demos/demo0000 --map mp_backlot \
      baseline=output/botmatch/pool-prechange \
      wander=output/botmatch/pool-wander2 \
      idleturn=output/botmatch/pool-idleturn

It also prints, per metric, the bot median next to the human median and the FDR
q-value, which is how a tell is judged: significant q and a median far from the
human one. Raw KS deltas between pools are noisy at these session counts, so the
q-value and the medians are what this table is for.

Tests: covered by tools/test_btlog.py (same scorer) and tools/test_scorecmp.py.
"""
import argparse
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import btlog  # noqa: E402
import scorecmp  # noqa: E402

WATCH = [("turn", "rate_p50"), ("turn", "rate_p90"), ("turn", "rate_p99"),
         ("turn", "jitter"), ("turn", "snap_pct"), ("turn", "still_but_turning_pct"),
         ("turn", "pitch_zero_pct"), ("stance", "ads_pct"), ("stance", "crouch_pct"),
         ("speed", "p50"), ("speed", "p90"), ("speed", "p99"), ("speed", "still_pct"),
         ("path", "zigzag_p90"), ("path", "strafe_pct"), ("path", "backpedal_pct")]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("pools", nargs="+", metavar="NAME=DIR_OR_GLOB",
                    help="each pool is a label and a directory of *.telemetry.log")
    ap.add_argument("--humans", nargs="+", required=True)
    ap.add_argument("--map", default="mp_backlot")
    ap.add_argument("--min-minutes", type=float, default=0.5)
    ap.add_argument("--settle", type=float, default=btlog.SETTLE)
    ap.add_argument("--reps", type=int, default=300)
    ap.add_argument("--scores-dir", default=scorecmp.DEFAULT_DIR)
    ap.add_argument("--save", action="store_true", help="store each pool as a run")
    args = ap.parse_args(argv)

    runs = []
    for spec in args.pools:
        if "=" not in spec:
            raise SystemExit(f"expected NAME=DIR, got {spec!r}")
        name, pattern = spec.split("=", 1)
        logs = sorted(glob.glob(os.path.join(pattern, "*.telemetry.log"))) \
            or sorted(glob.glob(pattern))
        if not logs:
            print(f"{name}: no telemetry logs under {pattern}", file=sys.stderr)
            continue
        argv_run = ["--humans", *args.humans, "--bots", *logs, "--map", args.map,
                    "--min-minutes", str(args.min_minutes), "--settle", str(args.settle),
                    "--reps", str(args.reps), "--note",
                    f"pool {name}: {len(logs)} match log(s) from {pattern}"]
        if args.save:
            argv_run += ["--save", name, "--scores-dir", args.scores_dir]
        rc = btlog.main(argv_run)
        if rc not in (0, 2):
            print(f"{name}: scoring failed ({rc})", file=sys.stderr)
            continue
        runs.append((name, len(logs), argv_run))

    if not runs:
        return 2
    print("\n" + "=" * 100)
    print("POOL COMPARISON   (same scorer, same human baseline, same session settings)")
    print(f"  min-minutes {args.min_minutes}, settle {args.settle}s, bootstrap {args.reps}")
    for name, n, _ in runs:
        print(f"  {name}: {n} match log(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
