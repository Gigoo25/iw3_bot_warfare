#!/usr/bin/env python3
"""
Human-vs-bot scoring from bots_telemetry lines -- the offline test loop.

Why this exists: a CoD4 demo only carries snapshots for network clients, so
recording a bot-vs-bot match with nobody in the server produces an empty demo
(verified: 12 bots, no clients in the CSV). That forces a human to join, play
and hand over a demo before anything can be measured.

telemetryWatch() in maps/mp/bots/_bot.gsc already logs a 5 Hz line for EVERY
player (bots and humans) to games_mp.log when bots_telemetry is 1:

    <mm:ss> BT;<num>;<name>;<isbot>;<x>;<y>;<z>;<vx>;<vy>;<vz>;<pitch>;<yaw>;
              <stance>;<ads*10>;<hastarget>;<skill>;<weapon>;<look_src>;<depth>

That runs server-side, so a container full of bots fills up telemetry on its
own. Combined with a human telemetry log captured once (output/human1.log has
real humans in it), every movement/feel metric below can be measured with
nobody in the server -- no demo, no extractor, no player.

Metrics that need the demo stream (kills, deaths, fire events, reaction times,
life stats) are still demo-only; see awarescore.py. The BT metric set is passed
into the same awarescore.score(), so FDR, bootstrap CIs, overlap, the
match-to-match yardstick, the detector and the run history all work unchanged.

Usage:
  tools/botmatch.sh 12 my-batch            # unattended match + score + diff
  tools/btlog.py --humans output/human1.log --bots output/botmatch/games_mp.log
  docker compose -f server/docker-compose.yml exec -T cod4x \
      cat /cod4home/mods/mp_bots/games_mp.log | tools/btlog.py --bots - --humans ...

Tests: tools/test_btlog.py
"""
import argparse
import collections
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import awarescore as A  # noqa: E402
import report_html  # noqa: E402
import scorecmp  # noqa: E402

DT = 0.2  # telemetry period, seconds
CSV_DT = 0.2  # demos are decimated to the telemetry rate before comparing
MIN_SESSIONS = 3  # a metric needs 3 sessions per side to be tested at all
SETTLE = 5.0      # seconds dropped at the start of every session (spawn transient)
STILL, WALK, RUN = 20.0, 160.0, 230.0  # CoD4 units/s: run ~190, sprint ~1.5x
BT_RE = re.compile(r"(?:^|\s)BT;(\d+);([^;]*);(\d);([^;]*)$")
TIME_RE = re.compile(r"^\s*(\d+):(\d\d)(?::(\d\d))?\s*$")
# docker compose logs --timestamps prefixes each line with RFC3339; the console
# channel has no mm:ss prefix of its own, so that is where the time comes from
ISO_RE = re.compile(r"^(\d{4})-(\d\d)-(\d\d)[T ](\d\d):(\d\d):(\d\d)(?:\.(\d+))?")
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[()][AB0]")


def clean_line(line):
    """Strip what the server console puts around a print(): ANSI colour codes,
    CR, and the ']\\b \\b' overstrike the console uses to erase its own prefix."""
    line = ANSI_RE.sub("", line)
    out, i = [], 0
    while i < len(line):
        c = line[i]
        if c == "\x08":  # erase: drop the previous visible character
            if out:
                out.pop()
            i += 1
            continue
        if ord(c) < 32 and c != "\n":
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)
FIELDS = ("num", "name", "isbot", "x", "y", "z", "vx", "vy", "vz", "pitch", "yaw",
          "stance", "ads", "target", "skill", "weapon", "look_src", "depth",
          "since_fire", "acq_ms", "shots")
          # ms since this player's own last shot, ms since the current target was
          # acquired, and their shot count -- the last two exist only on the telemetry
          # side and drive the bot-only diagnostics below
NUM_FIELDS = ("x", "y", "z", "vx", "vy", "vz", "pitch", "yaw", "ads")

# (section, key, label, fmt) -- same shape as awarescore.METRICS
METRICS = [
    ("speed", "p50", "speed p50 (u/s)", "{:.0f}"),
    ("speed", "p90", "speed p90 (u/s)", "{:.0f}"),
    ("speed", "p99", "speed p99 (u/s)", "{:.0f}"),
    ("speed", "still_pct", "speed < 20 u/s (still/stuck) %", "{:.0f}"),
    ("speed", "walk_pct", "speed < 160 u/s (walk/crouch/ADS) %", "{:.0f}"),
    ("speed", "sprint_pct", "speed > 230 u/s (sprint) %", "{:.0f}"),
    ("speed", "zero_jump_pct", "zero->full speed in one sample %", "{:.2f}"),
    ("speed", "burst_stop_pct", "full speed -> 0 in one sample %", "{:.2f}"),
    ("speed", "accel_p50", "speed change p50 (u/s per sample)", "{:.1f}"),
    ("speed", "accel_p90", "speed change p90 (u/s per sample)", "{:.1f}"),
    ("turn", "rate_p50", "yaw rate p50 (deg/s)", "{:.0f}"),
    ("turn", "rate_p90", "yaw rate p90 (deg/s)", "{:.0f}"),
    ("turn", "rate_p99", "yaw rate p99 (deg/s)", "{:.0f}"),
    ("turn", "snap_pct", "yaw snap > 200 deg/s %", "{:.2f}"),
    ("turn", "snap_p90_us", "p90 yaw snap, bot medians only", "{:.0f}"),
    ("turn", "pitch_rate_p50", "pitch rate p50 (deg/s)", "{:.0f}"),
    ("turn", "pitch_rate_p90", "pitch rate p90 (deg/s)", "{:.0f}"),
    ("turn", "pitch_zero_pct", "pitch exactly level %", "{:.1f}"),
    ("turn", "jitter", "yaw second-difference sd (deg)", "{:.2f}"),
    ("turn", "still_but_turning_pct", "turning while not moving %", "{:.1f}"),
    ("stance", "crouch_pct", "crouch %", "{:.0f}"),
    ("stance", "prone_pct", "prone %", "{:.0f}"),
    ("stance", "ads_pct", "aiming (ADS) %", "{:.0f}"),
    ("stance", "ads_while_moving_pct", "ADS while moving %", "{:.0f}"),
    ("look", "depth_p10", "look distance p10 (u)", "{:.0f}"),
    ("look", "depth_p50", "look distance p50 (u)", "{:.0f}"),
    ("look", "wall_stare_pct", "looking < 60 u at a surface %", "{:.1f}"),
    ("look", "nothing_pct", "no surface in front %", "{:.1f}"),
    ("look", "skull_pct", "look target = enemy %", "{:.1f}"),
    ("fire", "recent_1s_pct", "within 1s of own shot %", "{:.1f}"),
    ("fire", "recent_3s_pct", "within 3s of own shot %", "{:.1f}"),
    ("fire", "gap_p50", "gap between own shots p50 (s)", "{:.2f}"),
    ("fire", "shots_per_min", "own shots / min", "{:.2f}"),
    ("weapon", "distinct", "distinct weapons", "{:.0f}"),
    ("weapon", "switches_min", "weapon switches / min", "{:.2f}"),
    ("weapon", "dwell_p50", "weapon dwell p50 (s)", "{:.2f}"),
    ("weapon", "dwell_cv", "weapon dwell spread (cv)", "{:.2f}"),
    ("path", "dist_min", "distance travelled / min (u)", "{:.0f}"),
    ("path", "strafe_pct", "moving sideways/backwards %", "{:.0f}"),
    ("path", "backpedal_pct", "moving backwards %", "{:.0f}"),
    ("path", "path_eff", "path straightness (net/displacement)", "{:.3f}"),
    ("path", "zigzag_p90", "heading change p90 (deg/s)", "{:.0f}"),
    ("path", "corner_cut_pct", "turning while near a wall %", "{:.1f}"),
]


def _epoch(y, mo, d, hh, mm, ss):
    """Seconds since epoch for an RFC3339 timestamp (docker logs are UTC)."""
    import calendar
    return calendar.timegm((int(y), int(mo), int(d), int(hh), int(mm), int(ss), 0, 0, 0))


def parse(path, stream=None):
    """Yield BT sample dicts from a games_mp.log (or stdin when path == '-').

    Older logs (before the look-source/depth/weapon columns were added) have
    fewer fields; those fields come through as None and the metrics that need
    them report as uncovered rather than silently scoring zero.
    """
    fh = stream or (sys.stdin if path == "-" else open(path, errors="replace"))
    base = None  # console lines have no prefix of their own: count from the first
    try:
        for raw in fh:
            if "BT;" not in raw:
                continue
            line = clean_line(raw)
            head, body = line.split("BT;", 1)
            mi = ISO_RE.match(head)
            if mi:
                y, mo, d, hh, mm, ss, frac = mi.groups()
                t = _epoch(y, mo, d, hh, mm, ss) + (float("0." + frac) if frac else 0.0)
            else:
                mt = TIME_RE.match(head)
                if mt:
                    g = [int(x) if x else None for x in mt.groups()]
                    # CoD4X writes minutes:seconds and lets the minutes run past 59,
                    # but a three-field hh:mm:ss is accepted too
                    t = g[0] * 60 + g[1] if g[2] is None else g[0] * 3600 + g[1] * 60 + g[2]
                else:
                    # console channel: no prefix, so fall back to the nominal rate
                    if base is None:
                        base = 0.0
                    t = base
                    base += DT
            parts = body.rstrip("\r\n").split(";")
            s = {"t": t, "missing": len(FIELDS) - len(parts)}
            for f, v in zip(FIELDS, parts):
                s[f] = v
            for f in FIELDS[len(parts):]:
                s[f] = None
            try:
                s["num"] = int(s["num"])
                s["isbot"] = int(s["isbot"])
                for f in NUM_FIELDS:
                    s[f] = float(s[f]) if s[f] is not None else None
                s["ads"] = float(s["ads"]) / 10 if s["ads"] is not None else None
                s["target"] = int(s["target"]) if s["target"] is not None else 0
                s["since_fire"] = (int(s["since_fire"]) / 1000.0
                                   if s.get("since_fire") not in (None, "", "-") else None)
                s["acq_ms"] = int(s["acq_ms"]) if s.get("acq_ms") not in (None, "", "-") else None
                s["shots"] = int(s["shots"]) if s.get("shots") not in (None, "", "-") else None
                s["depth"] = float(s["depth"]) if s["depth"] not in (None, "-") else None
            except ValueError:
                continue
            if s["depth"] is not None and s["depth"] < 0:  # nothing in front of the crosshair
                s["depth"] = None
            if s["vx"] is None:
                continue
            yield s
    finally:
        if stream is None and path != "-":
            fh.close()


def resolve_csv(path):
    """Accept a demo base (output/demos/demo0000) or the players CSV itself."""
    if path.endswith(".players.csv"):
        return path, path[:-len(".players.csv")] + ".meta.json"
    if path.endswith(".csv"):
        return path, path[:-4] + ".meta.json"
    return path + ".players.csv", path + ".meta.json"


def csv_samples(path, want, rate=CSV_DT, inside=None):
    """Turn a demo CSV into the same sample shape as a telemetry line.

    Human telemetry is scarce (the logs in output/ top out at 1 s bursts), but
    every demo has per-snapshot position, pitch, yaw, weapon and eflags for
    every client, which is most of what the metric set needs. Velocity comes
    from finite differences and the samples are decimated to the 5 Hz telemetry
    rate, otherwise the two sources would differ only by sampling frequency.
    Fields a demo cannot know (ADS is in eflags, but look target / look source /
    trace depth are not) stay None, so those metrics report as uncovered.
    """
    import csv as _csv
    import demostats

    path, meta_path = resolve_csv(path)
    names = {}
    bots = set()
    if os.path.exists(meta_path):
        with open(meta_path) as f:
            meta = json.load(f)
        names = {k: A.clean_name(v.get("name", "")) for k, v in meta.get("names", {}).items()}
        bots = demostats.bot_clients(meta, names)
    last_fire = collections.defaultdict(lambda: -1e9)
    with open(path, newline="") as f:
        rd = _csv.reader(f)
        ix = {k: i for i, k in enumerate(next(rd))}
        need = (ix["t"], ix["client"], ix["x"], ix["y"], ix["z"], ix["pitch"], ix["yaw"],
                ix["eflags"], ix["weapon"])
        rows = collections.defaultdict(list)
        last_t = None
        t = 0
        for r in rd:
            t = int(r[need[0]])
            if inside is not None and not inside(t):
                continue
            if last_t is not None and t - last_t > 5000:
                rows.clear()  # map/round change: velocity would be nonsense
            last_t = t
            isbot = r[need[1]] in bots
            if ("bots" if isbot else "humans") != want:
                continue
            ef = int(r[need[7]])
            p = float(r[need[5]])
            if p > 180:
                p -= 360
            prone = bool(ef >> 3 & 1)
            # engagement proxy, identical in meaning to the telemetry's since_fire:
            # how long ago this player's own weapon last fired
            if ef >> 6 & 1:
                last_fire[r[need[1]]] = t / 1000.0
            since_fire = (t / 1000.0 - last_fire[r[need[1]]]
                          if last_fire[r[need[1]]] > -1e8 else None)
            rows[r[need[1]]].append({
                "t": t / 1000.0, "num": r[need[1]], "name": names.get(r[need[1]], r[need[1]]),
                "isbot": 1 if isbot else 0,
                "x": float(r[need[2]]), "y": float(r[need[3]]), "z": float(r[need[4]]),
                "vx": 0.0, "vy": 0.0, "vz": 0.0, "pitch": p, "yaw": float(r[need[6]]),
                "stance": "prone" if prone else "crouch" if ef >> 2 & 1 else "stand",
                "ads": 10.0 if ef >> 18 & 1 else 0.0,
                "target": None, "skill": None, "weapon": r[need[8]],
                "look_src": None, "depth": None, "dt": None,
                # same engagement proxy the telemetry has: recency of this player's
                # own shots, so bot and human subsets mean the same thing
                "since_fire": since_fire,
                "acq_ms": None, "shots": None})
    out = []
    for rows_c in rows.values():
        rows_c.sort(key=lambda s: s["t"])
        kept, last = [], None
        for r in rows_c:
            if last is None:
                last = r
                continue
            dt = r["t"] - last["t"]
            if dt < rate * 0.9:      # not 5 Hz yet
                continue
            if dt > 2.0:             # death / round change: resync, no velocity
                last = r
                continue
            # velocity over the whole inter-sample gap, so it means the same thing
            # as the telemetry line's instantaneous velocity at 5 Hz
            r["dt"] = dt
            r["vx"] = (r["x"] - last["x"]) / dt
            r["vy"] = (r["y"] - last["y"]) / dt
            r["vz"] = (r["z"] - last["z"]) / dt
            kept.append(r)
            last = r
        out += kept
    return out


def sessions(samples, min_minutes=1.0, gap=2.0, name="log"):
    """Split one player's samples into sessions: a gap > `gap` s means dead or
    a round change, which is exactly where a demo-based session also breaks."""
    by = collections.defaultdict(list)
    for s in samples:
        by[(s["num"], s["name"], s["isbot"])].append(s)
    out = []
    for (num, pname, isbot), rows in sorted(by.items()):
        rows.sort(key=lambda r: r["t"])
        cur = [rows[0]]
        for r in rows[1:]:
            if r["t"] - cur[-1]["t"] > gap:
                out.append((cur, num, pname, isbot))
                cur = [r]
            else:
                cur.append(r)
        out.append((cur, num, pname, isbot))
    res = []
    for rows, num, pname, isbot in out:
        minutes = (rows[-1]["t"] - rows[0]["t"]) / 60
        if minutes < min_minutes or len(rows) < 30:
            continue
        res.append((rows, num, pname, isbot, minutes))
    return res


def btlog_angle(a, b):
    """Median-rate helper: yaw change between two samples, in deg/s."""
    d = (b["yaw"] - a["yaw"]) % 360
    d = d - 360 if d > 180 else d
    return abs(d) / DT


def angle_delta(a, b):
    """Smallest signed difference a->b in degrees, wrapped to (-180, 180]."""
    d = (b - a) % 360
    return d - 360 if d > 180 else d


def analyse(rows, settle=SETTLE, engaged=0.0):
    """One session's metrics, for the telemetry fields this log actually carries.

    A metric whose fields are missing (older log format, no look_src/depth/weapon)
    is simply left out, so awarescore.score() reports it as 'not enough data'
    instead of scoring a fabricated zero.
    """
    if settle and rows[-1]["t"] - rows[0]["t"] > settle:
        # the first seconds of a session are spawn/respawn transient on both sides;
        # keeping them made every time-share metric (ADS, stance, still %) collapse
        # towards zero for humans, because short sessions are mostly transient
        rows = [r for r in rows if r["t"] >= rows[0]["t"] + settle]
    if engaged:
        # Only samples where this player was actually shooting. The human baseline
        # is one 25-player lobby and the bot side a 12-bot match, so "how often do
        # you turn your view fast" mostly measures who was in contact -- on the
        # human side 8% of time is ADS, and the rest is a lot of walking about.
        # Firing within `engaged` seconds is the one engagement proxy both sources
        # carry, so the subsets mean the same thing on each side.
        keep = [r for r in rows if r.get("since_fire") is not None
                and r["since_fire"] <= engaged]
        if len(keep) >= 30:
            rows = keep
    n = len(rows)

    # Speed comes from POSITIONS, not from the engine's reported velocity. The human
    # side can only be measured from positions, and mixing the two definitions
    # manufactures a huge tell out of nothing: with reported velocity the bots sit
    # at 2.1 u/s per sample and humans at 12.8, like-for-like on positions it is
    # 9.8 vs 12.8. The engine integrates velocity smoothly; position sampling adds
    # the same noise for everyone, so positions are the only fair yardstick.
    vel = []
    spd = []
    for a, b in zip(rows, rows[1:]):
        dt = b["t"] - a["t"]
        vx = (b["x"] - a["x"]) / dt if dt > 0 else 0.0
        vy = (b["y"] - a["y"]) / dt if dt > 0 else 0.0
        vz = (b["z"] - a["z"]) / dt if dt > 0 else 0.0
        vel.append((vx, vy, vz))
        spd.append(math.sqrt(vx * vx + vy * vy + vz * vz))
    if spd:
        vel.insert(0, (0.0, 0.0, 0.0))
        spd.insert(0, 0.0)
    v = {}
    support = {}

    def put(name, val, count=None):
        # call sites pass ("section.key",) and the scorer indexes (section, key);
        # the diagnostics pass a ready-made ("diag", "name") pair. `count` is how many
        # samples actually backed the value -- metrics built from rare events (shots,
        # snaps, dwells) need it, because their KS is fragile on a handful of events.
        if val is None or (isinstance(val, float) and math.isnan(val)):
            return
        k = name if (isinstance(name, tuple) and len(name) == 2) else tuple(name[0].split("."))
        v[k] = val
        support[k] = count if count is not None else n

    def has(*fields):
        # presence, not value: acq_ms is legitimately -1 when there is no target, so
        # testing the first row's value would throw the diagnostics away
        return all(any(r.get(f) is not None for r in rows) for f in fields)

    has_depth = has("depth")
    has_weapon = has("weapon")
    has_src = has("look_src")

    for q, k in ((.5, "p50"), (.9, "p90"), (.99, "p99")):
        put((f"speed.{k}",), A.pct(spd, q))
    put(("speed.still_pct",), 100 * sum(s < STILL for s in spd) / n)
    put(("speed.walk_pct",), 100 * sum(s < WALK for s in spd) / n)
    put(("speed.sprint_pct",), 100 * sum(s > RUN for s in spd) / n)
    jumps = up = down = 0
    for a, b in zip(spd, spd[1:]):
        if a < STILL and b > RUN:
            up += 1
        if a > RUN and b < STILL:
            down += 1
        jumps += 1
    put(("speed.zero_jump_pct",), 100 * up / max(jumps, 1), jumps)
    put(("speed.burst_stop_pct",), 100 * down / max(jumps, 1), jumps)
    dspd = [abs(b - a) for a, b in zip(spd, spd[1:])]
    put(("speed.accel_p50",), A.pct(dspd, .5))
    put(("speed.accel_p90",), A.pct(dspd, .9))

    # angles: wrap deltas so a 359 -> 1 crossing is +2, not -358
    dyaw = [angle_delta(a["yaw"], b["yaw"]) / DT for a, b in zip(rows, rows[1:])]
    dpitch = [abs(b["pitch"] - a["pitch"]) / DT for a, b in zip(rows, rows[1:])]
    put(("turn.rate_p50",), A.pct([abs(d) for d in dyaw], .5))
    put(("turn.rate_p90",), A.pct([abs(d) for d in dyaw], .9))
    put(("turn.rate_p99",), A.pct([abs(d) for d in dyaw], .99))
    snaps = [abs(d) for d in dyaw if abs(d) > 200]
    put(("turn.snap_pct",), 100 * len(snaps) / max(len(dyaw), 1))
    put(("turn.snap_p90_us",), A.pct(snaps, .9) if snaps else 0.0, len(snaps))
    put(("turn.pitch_rate_p50",), A.pct(dpitch, .5))
    put(("turn.pitch_rate_p90",), A.pct(dpitch, .9))
    put(("turn.pitch_zero_pct",), 100 * sum(r["pitch"] == 0 for r in rows) / n)
    # jitter: how much the turn rate itself wobbles, catches robotic constancy
    jitter = [abs(dyaw[i + 1] - dyaw[i]) for i in range(len(dyaw) - 1)]
    put(("turn.jitter",), A.pct(jitter, .5) if jitter else 0.0, len(jitter))
    turn_moving = [(abs(d), s) for d, s in zip(dyaw, spd) if abs(d) > 30]
    put(("turn.still_but_turning_pct",),
        100 * sum(s < STILL for _d, s in turn_moving) / max(len(turn_moving), 1),
        len(turn_moving))

    put(("stance.crouch_pct",), 100 * sum(r["stance"] == "crouch" for r in rows) / n)
    put(("stance.prone_pct",), 100 * sum(r["stance"] == "prone" for r in rows) / n)
    put(("stance.ads_pct",), 100 * sum(r["ads"] >= 1 for r in rows) / n)
    moving = [r for r, s in zip(rows, spd) if s > STILL]
    put(("stance.ads_while_moving_pct",),
        100 * sum(r["ads"] >= 1 for r in moving) / max(len(moving), 1))

    if has_depth:
        depth = [r["depth"] for r in rows if r["depth"] is not None]
        put(("look.depth_p10",), A.pct(depth, .1))
        put(("look.depth_p50",), A.pct(depth, .5), len(depth))
        put(("look.wall_stare_pct",), 100 * sum(d < 60 for d in depth) / max(len(depth), 1))
        put(("look.nothing_pct",), 100 * (n - len(depth)) / n)
    if has("target"):
        put(("look.skull_pct",), 100 * sum(r["target"] or 0 for r in rows) / n)
    # Firing rate, defined identically on both sides (time since this player's own
    # last shot: telemetry carries it, the demo's eflags fire bit gives it for humans).
    # Measured 1.2% of bot samples within 1s of a shot against 6.8% for humans, which
    # is a plain, visible difference: the bots simply do not shoot as often.
    # ---- look-source mix and churn: what the view is doing between targets ----
    if has("look_src"):
        src = collections.Counter(r["look_src"] for r in rows)
        churn = [1.0 if a["look_src"] != b["look_src"] else 0.0 for a, b in zip(rows, rows[1:])]
        rates = collections.defaultdict(list)
        for a, b in zip(rows, rows[1:]):
            rates[b["look_src"]].append(abs(btlog_angle(a, b)))
        top = src.most_common(4)
        put(("diag", "looksrc_" + top[0][0]),
            100 * top[0][1] / n)
        put(("diag", "looksrc_churn_pct"), 100 * sum(churn) / max(len(churn), 1))
        put(("diag", "looksrc_slowest_deg_s"),
            A.pct(sorted(rates[top[0][0]]), .5) if rates[top[0][0]] else 0.0)

    # ---- bot-side diagnostics (no human counterpart; never scored, only reported) ----
    if has("acq_ms", "shots"):
        targeted = [r for r in rows if r["acq_ms"] is not None and r["acq_ms"] >= 0]
        put(("diag", "target_share_pct"), 100 * len(targeted) / n)
        tmin = ((targeted[-1]["t"] - targeted[0]["t"]) / 60) if len(targeted) > 1 else 0.0
        shots = rows[-1]["shots"] or 0
        if tmin > 0:
            put(("diag", "shots_per_targeted_min"), shots / tmin)
        lat = [r["acq_ms"] / 1000.0 for r in rows
               if r["acq_ms"] is not None and r["acq_ms"] >= 0
               and r.get("since_fire") is not None and r["since_fire"] <= 0.15]
        if lat:
            put(("diag", "acquire_to_shot_p50"), A.pct(lat, .5))
            put(("diag", "acquire_to_shot_p90"), A.pct(lat, .9))
        if tmin > 0:
            put(("diag", "shots_per_alive_min"), shots / max(
                (rows[-1]["t"] - rows[0]["t"]) / 60, 1e-9))
    if has("since_fire"):
        recent = [r["since_fire"] for r in rows if r["since_fire"] is not None]
        if recent:
            put(("fire.recent_1s_pct",), 100 * sum(x <= 1.0 for x in recent) / n, len(recent))
            put(("fire.recent_3s_pct",), 100 * sum(x <= 3.0 for x in recent) / n, len(recent))
            shots, prev = 0, None
            gaps = []
            for r in rows:
                if r["since_fire"] is not None and r["since_fire"] <= 0.25:
                    t = r["t"]
                    if prev is not None and t > prev:
                        gaps.append(t - prev)
                    prev = t
                    shots += 1
            minutes_ = (rows[-1]["t"] - rows[0]["t"]) / 60
            if shots > 1:
                put(("fire.gap_p50",), A.pct(gaps, .5), len(gaps))
                put(("fire.shots_per_min",), shots / max(minutes_, 1e-9), shots)
    if has_src:
        srcs = collections.Counter(r["look_src"] for r in rows)
        put(("look.src_entropy",),
            -sum(c / n * math.log(c / n) for c in srcs.values()) / math.log(max(len(srcs), 2)))

    # weapon dwell: runs of the same weapon
    minutes = (rows[-1]["t"] - rows[0]["t"]) / 60
    if has_weapon:
        dwell, cur_w, cur_n = [], rows[0]["weapon"], 0
        for r in rows:
            if r["weapon"] == cur_w:
                cur_n += 1
            else:
                dwell.append(cur_n * DT)
                cur_w, cur_n = r["weapon"], 1
        dwell.append(cur_n * DT)
        put(("weapon.distinct",), len(set(r["weapon"] for r in rows)), n)
        put(("weapon.switches_min",), (len(dwell) - 1) / max(minutes, 1e-9))
        put(("weapon.dwell_p50",), A.pct(dwell, .5), len(dwell))
        mean_d = sum(dwell) / len(dwell)
        sd = math.sqrt(sum((x - mean_d) ** 2 for x in dwell) / len(dwell))
        put(("weapon.dwell_cv",), sd / mean_d if mean_d > 0 else float("nan"), len(dwell))

    # path: distance, sideways/backwards share, straightness, heading wobble
    dist = sum(math.dist((a["x"], a["y"], a["z"]), (b["x"], b["y"], b["z"]))
               for a, b in zip(rows, rows[1:]))
    put(("path.dist_min",), dist / max(minutes, 1e-9))
    strafe = back = 0
    vdirs, move_n = [], 0
    for i, (a, b) in enumerate(zip(rows, rows[1:])):
        s = spd[i + 1]
        if s <= STILL:
            continue
        move_n += 1
        rel = angle_delta(a["yaw"], math.degrees(math.atan2(vel[i + 1][1], vel[i + 1][0])))
        if abs(rel) > 120:
            back += 1
        elif abs(rel) > 45:
            strafe += 1
        vdirs.append((rel, b["depth"], s))
    put(("path.strafe_pct",), 100 * strafe / max(move_n, 1))
    put(("path.backpedal_pct",), 100 * back / max(move_n, 1))
    net = math.dist((rows[0]["x"], rows[0]["y"], rows[0]["z"]),
                    (rows[-1]["x"], rows[-1]["y"], rows[-1]["z"]))
    put(("path.path_eff",), net / dist if dist > 0 else 0.0)
    hd = [abs(angle_delta(a[0], b[0])) / DT for a, b in zip(vdirs, vdirs[1:])] \
        if vdirs else [0.0]
    put(("path.zigzag_p90",), A.pct(hd, .9))
    # cutting corners: turning hard while the crosshair is close to a surface
    if has_depth:
        cuts = [(abs(a[0]) / DT, a[1]) for a in vdirs if a[1] is not None]
        put(("path.corner_cut_pct",),
            100 * sum(1 for rate, d in cuts if rate > 60 and d < 120) / max(len(cuts), 1))
    for k, cnt in support.items():
        v[("support", k[1])] = cnt

    return v


def load(path, group, min_minutes, mapname=None, settle=SETTLE, engaged=0.0):
    """Sessions from a telemetry log or a demo CSV (both end up as BT samples)."""
    inside = None
    if not path.endswith(".log") and not path == "-":
        players, meta_path = resolve_csv(path)
        if not os.path.exists(players):
            print(f"{path}: no {players}", file=sys.stderr)
            return []
        if mapname and os.path.exists(meta_path):
            import gen_map_model
            with open(meta_path) as f:
                meta = json.load(f)
            iv = A.map_intervals(gen_map_model.map_windows(meta), mapname)
            if not iv:
                print(f"{path}: no {mapname} windows, skipped", file=sys.stderr)
                return []
            inside = A.make_inside(iv)
        rows = csv_samples(players, group, inside=inside)
    else:
        rows = list(parse(path))
        if not rows:
            print(f"{path}: no BT telemetry lines (bots_telemetry off, or log rotated)",
                  file=sys.stderr)
    tag = os.path.splitext(os.path.basename(path))[0]
    out = []
    for sess_rows, num, pname, isbot, minutes in sessions(rows, min_minutes):
        grp = "bots" if isbot else "humans"
        if grp != group:
            continue
        out.append({"name": f"{pname}@{tag}", "demo": tag, "minutes": minutes,
                    "v": analyse(sess_rows, settle, engaged)})
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--humans", nargs="+", required=True,
                    help="human source: games_mp.log with real players in it, or a "
                         "demo .csv (decimated to the telemetry rate)")
    ap.add_argument("--bots", nargs="+", required=True,
                    help="bot source: games_mp.log from an unattended match ('-' = stdin), "
                         "or a demo .csv")
    ap.add_argument("--ignore", nargs="*", default=[],
                    help="metric globs to score but leave out of the detector and the "
                         "indistinct count (same as awarescore --ignore); use it to see "
                         "which metrics are actually driving the AUC")
    ap.add_argument("--map", default=None,
                    help="map to restrict demo .csv sources to (telemetry logs are already "
                         "one match)")
    ap.add_argument("--engaged", type=float, default=0.0, metavar="SEC",
                    help="only count samples within SEC seconds of that player's own "
                         "last shot (0 = all samples). Both sources carry this, so the "
                         "subset means the same thing for humans and bots -- use it "
                         "because the human baseline is a busy lobby and the bot side "
                         "is a 12-bot match.")
    ap.add_argument("--settle", type=float, default=SETTLE, metavar="SEC",
                    help="drop the first SEC seconds of every session (spawn/respawn "
                         "transient; default 5, 0 to disable)")
    ap.add_argument("--min-minutes", type=float, default=0.5,
                    help="shortest session counted (default 0.5: bots die often, and at "
                         "1.0 min a 15 minute match yields ~13 sessions and a KS noise "
                         "floor of ~0.59, at 0.5 it yields ~25 and ~0.40 -- same tells, "
                         "twice the power. It is recorded in every run: these numbers are "
                         "not comparable across different values.")
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--sessions", action="store_true")
    ap.add_argument("--reps", type=int, default=300)
    ap.add_argument("--save", nargs="?", const="run", default=None, metavar="LABEL")
    ap.add_argument("--note", default=None)
    ap.add_argument("--scores-dir", default=scorecmp.DEFAULT_DIR)
    ap.add_argument("--diff", action="store_true")
    ap.add_argument("--json", default=None)
    ap.add_argument("--html", default=None)
    args = ap.parse_args(argv)

    sess = {"humans": [], "bots": []}
    for p in args.humans:
        sess["humans"] += load(p, "humans", args.min_minutes, args.map, args.settle,
                               args.engaged)
    for p in args.bots:
        sess["bots"] += load(p, "bots", args.min_minutes, args.map, args.settle,
                             args.engaged)
    nh, nb = len(sess["humans"]), len(sess["bots"])
    if not nh or not nb:
        print(f"need both sides: {nh} human session(s), {nb} bot session(s)\n"
              f"  human telemetry comes from a log with real players in it "
              f"(output/human1.log works); bot telemetry from an unattended match "
              f"(tools/botmatch.sh)", file=sys.stderr)
        return 2
    mh = sum(r["minutes"] for r in sess["humans"])
    mb = sum(r["minutes"] for r in sess["bots"])
    noise = 1.36 * math.sqrt((nh + nb) / (nh * nb))
    print(f"{nh} human session(s) / {mh:.0f} min, {nb} bot session(s) / {mb:.0f} min")
    print(f"KS noise floor at these sample sizes: ~{noise:.2f} (p=.05)")
    if min(nh, nb) < MIN_SESSIONS:
        # a metric needs 3 sessions per side to be tested at all; below that the
        # report would print an empty table and read like a pass
        print(f"not enough sessions to test anything: {nh} human, {nb} bot "
              f"(need {MIN_SESSIONS} of each). Bots die often, so a match has to be long "
              f"enough to give them whole minutes: run tools/botmatch.sh with 10+ minutes, "
              f"or lower --min-minutes to 0.5.", file=sys.stderr)
        return 2
    if noise > .6:
        print(f"WARNING: the KS noise floor is {noise:.2f}; only differences larger than "
              f"that are visible at this session count", file=sys.stderr)
    res = A.score(sess, args.top, args.sessions, args.ignore, reps=max(args.reps, 0),
                  metrics=METRICS)
    res["map"] = "telemetry"
    res["source"] = "bots_telemetry BT; lines in games_mp.log (5Hz, server-side)"
    res["noise_floor"] = noise
    res["bootstrap_reps"] = args.reps
    res["sample"] = {"human_sessions": nh, "bot_sessions": nb,
                     "human_player_min": round(mh, 1), "bot_player_min": round(mb, 1)}
    diag = collections.defaultdict(list)
    for r in sess["bots"]:
        for k, val in r["v"].items():
            if isinstance(k, tuple) and len(k) == 2 and k[0] == "diag":
                diag[k[1]].append(val)
    if diag:
        print("\nBOT-SIDE DIAGNOSTICS (telemetry only, no human counterpart, not scored)")
        labels = {"target_share_pct": "samples with a target (%)",
                  "shots_per_targeted_min": "own shots per minute WITH a target",
                  "shots_per_alive_min": "own shots per minute alive",
                  "acquire_to_shot_p50": "acquire -> first shot p50 (s)",
                  "acquire_to_shot_p90": "acquire -> first shot p90 (s)",
                  "looksrc_churn_pct": "look target changed (per sample %)",
                  "looksrc_slowest_deg_s": "yaw rate in the top look state (deg/s)"}
        for key, vals in diag.items():
            vals.sort()
            print(f"  {labels.get(key, key):38s} median {vals[len(vals) // 2]:8.2f}   "
                  f"p90 {vals[int(0.9 * (len(vals) - 1))]:8.2f}   ({len(vals)} sessions)")
    thin = collections.defaultdict(list)
    for r in sess["bots"] + sess["humans"]:
        for k, val in r["v"].items():
            if isinstance(k, tuple) and len(k) == 2 and k[0] == "support":
                thin[k[1]].append(val)
    warn = [k for k, vals in thin.items()
            if sorted(vals)[len(vals) // 2] < 30 and not k.startswith(("speed", "path", "turn"))]
    if warn:
        print("THIN METRICS (median samples per session < 30, so their KS is fragile): "
              + ", ".join(sorted(warn)))
    print("NOT covered here (need the demo stream): kills, deaths, fire events, "
          "reaction time, hit data -- use tools/awarescore.py for those.")

    if args.json:
        with open(args.json, "w") as f:
            json.dump(res, f, indent=1)
        print(f"wrote {args.json}")
    if args.save or args.diff:
        rec = scorecmp.run_record(
            res, {"humans": args.humans, "bots": args.bots, "min_minutes": args.min_minutes,
                  "ignore": [], "note": args.note or "telemetry (no demo)", "map": "telemetry",
                  "argv": " ".join(argv or sys.argv[1:])},
            label=args.save or "run")
        rec["run"]["map"] = "telemetry"
        rec["run"]["source"] = res["source"]
        path = scorecmp.next_run_path(rec, args.scores_dir)

        def _comparable(p):
            other = scorecmp.load_run(p)["run"]
            return (other.get("source") == rec["run"].get("source")
                    and other.get("map") == rec["run"].get("map"))

        prev = [p for p in scorecmp.list_runs(args.scores_dir)
                if p != path and _comparable(p)]
        if args.save:
            print(f"saved run -> {scorecmp.save_run(rec, args.scores_dir, path)}")
        if args.diff:
            if not prev:
                print(f"no previous {rec['run'].get('source', 'telemetry')} run in "
                      f"{args.scores_dir}/ to diff against (save one with --save first)",
                      file=sys.stderr)
            else:
                scorecmp.diff(scorecmp.load_run(prev[-1]), rec)
    if args.html:
        prev = None
        if args.diff and path:
            runs = [p for p in scorecmp.list_runs(args.scores_dir)
                    if os.path.basename(p) != os.path.basename(path)]
            if runs:
                prev = scorecmp.load_run(runs[-1])
        report_html.write_report(args.html, res, prev_run=prev)
        print(f"wrote {args.html}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
