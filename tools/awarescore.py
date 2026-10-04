#!/usr/bin/env python3
"""
Human-vs-bot "tell" test: how far are the bots from feeling human, and why.

Every player-session (one client in one demo, >= --min-minutes alive on the
map) is ONE point. Each metric compares the human distribution against the bot
distribution:

  KS      two-sample Kolmogorov-Smirnov distance (0 = same, 1 = disjoint)
  p       asymptotic KS p-value; '*' = the gap is bigger than sampling noise
  in-rng  % of bot sessions inside the human p10..p90 band
  spread  bot IQR / human IQR across sessions (bots all alike -> << 1)
  score   100 * (1 - KS)

Matching a share is NOT enough ("humans crouch 20% so bots crouch 20%"). The
`context` section checks that the behaviour happens the way humans do it:
  - bout lengths (20% as one 6-minute crouch vs many short ones)
  - state given WHERE (map cell), WHEN (time into round) and THREAT (nearest
    enemy distance), as a log-lift over the human base rate, human prior
    leave-one-out: > 0 means the state is used where/when humans use it
  - state-transition divergence + entropy rate (order of run/stop/ADS/fire)
  - minute-to-minute variation of still/crouch/ADS shares
and the detector sees every metric at once, so matching each one separately
while getting the combination wrong still gets caught.

Headline numbers:
  detector AUC   leave-one-out naive Bayes over ALL metrics: can a detector that
                 sees everything we measure tell a bot session from a human one?
                 0.50 = indistinguishable, 1.00 = trivially caught.
  indistinct     % of metrics with no significant difference.
  TOP TELLS      metrics ranked by KS with the direction bots are off.

Data limits (honest): entity view angles in demos are quantized to ~1 degree,
so "0 change" means < 1 deg per 50ms frame (same for both groups); the
scoreboard is only sent while the recorder holds TAB (sparse); projectile owners
are not decoded (throws go to the nearest player at first sighting); demos are recorded from one client, so entities outside
its PVS are missing for humans and bots alike; there are no raycasts, so
"looks at enemy" means direction, not visibility; entity events are not decoded,
so reloads/pain reactions/hit locations are NOT covered (use tools/matchstats.py
on games_mp.log for accuracy and hit locations).

Usage:
  tools/awarescore.py --humans output/demos/demo0000 \
      --bots output/demos/ours_1 output/demos/ours_2 [...] [--map mp_backlot]
      [--top 25] [--sessions] [--ignore GLOB ...] [--json out.json]

Run history (tools/scorecmp.py): --save LABEL stores a trimmed run under
scores/ with the demos, filters and git commit used for scoring; --diff prints
the metric-level delta against the previous run (new tells, resolved tells,
better/worse). Use --note to say which build produced the demos: the recorded
commit is the tree that scored them, not the tree that built the bots.
Tests: tools/test_awarescore.py
"""
import argparse
import bisect
import collections
import csv
import fnmatch
import json
import math
import os
import random
import re
import sys
import zlib

sys.path.insert(0, os.path.dirname(__file__))
import demostats  # noqa: E402
import scorecmp  # noqa: E402
import gen_map_model  # noqa: E402
import movestats  # noqa: E402
import nadestats  # noqa: E402

CELL, LEVEL, HEAT, AREA = 128, 96, 256, 512
HEAR_DIST, HEAR_AGE = 2000, 2000
REACT_WINDOW = 3000
CONE, WIDE_CONE = 20, 45
SPEC = ("0", "3", "-1")
AIR = 1023  # groundEntityNum ENTITYNUM_NONE
MAX_DT = 0.15  # 20Hz frames further apart than this break continuity
EPS = 1e-6
STATES = ("fire", "prone", "crouch_still", "crouch_move", "ads_still", "ads_move",
          "still", "walk", "run", "sprint")
PHASES = (5, 15, 30, 60, 120, 1e9)          # seconds into round
THREAT = (500, 1000, 2000, 1e9)             # nearest known enemy distance

# compact row layout (tuples, not dicts: a 270k-row demo must fit in memory)
T, X, Y, Z, P, YW, EF, W, G, TM = range(10)


# ---------------------------------------------------------------- utilities

def angdiff(a, b):
    return abs((a - b + 180) % 360 - 180)


def sdiff(a, b):
    """Signed a - b wrapped to [-180, 180)."""
    return (a - b + 180) % 360 - 180


def bearing(ax, ay, bx, by):
    return math.degrees(math.atan2(by - ay, bx - ax))


def pct(vals, p):
    v = sorted(vals)
    return v[int(p * (len(v) - 1))] if v else float("nan")


def share(num, den, min_den):
    return 100 * num / den if den >= min_den else None


def ks_dist(a, b):
    a, b = sorted(a), sorted(b)
    na, nb = len(a), len(b)
    i = j = 0
    d = 0.0
    while i < na and j < nb:
        v = min(a[i], b[j])
        while i < na and a[i] == v:
            i += 1
        while j < nb and b[j] == v:
            j += 1
        d = max(d, abs(i / na - j / nb))
    return d


def ks_p(d, n, m):
    """Asymptotic two-sample KS p-value (Stephens' small-sample correction)."""
    if d <= 0:
        return 1.0
    en = math.sqrt(n * m / (n + m))
    lam = (en + 0.12 + 0.11 / en) * d
    s = sum((-1) ** (j - 1) * math.exp(-2 * j * j * lam * lam) for j in range(1, 101))
    return max(0.0, min(1.0, 2 * s))


def fdr_bh(ps):
    """Benjamini-Hochberg q-values: the smallest FDR at which each p survives.

    With ~110 metrics on screen, raw p<.05 is expected to flag ~5 by chance, so
    the report shows q alongside p and counts tells that survive FDR control.
    """
    n = len(ps)
    q = [1.0] * n
    order = sorted(range(n), key=lambda i: ps[i])
    prev = 1.0
    for rank in range(n, 0, -1):
        i = order[rank - 1]
        prev = min(prev, ps[i] * n / rank)
        q[i] = min(1.0, prev)
    return q


def ovl(a, b, ngrid=64):
    """Overlap coefficient of smoothed densities: shared mass everywhere.

    Not the same as 1-KS: KS is the total-variation distance between the empirical
    CDFs, so it saturates at 1.00 for one stray tail value and ignores everything
    in between. Smoothing with a Silverman bandwidth first makes the estimate
    stable at these sample sizes -- two samples from the SAME distribution score
    around 0.9 here instead of 1-KS, so a metric can have a moderate KS and still
    be visibly the same distribution, which is exactly what we want to see.
    """
    na, nb = len(a), len(b)
    if na < 2 or nb < 2:
        return float("nan")
    mean = (sum(a) + sum(b)) / (na + nb)
    var = (sum((x - mean) ** 2 for x in a) + sum((x - mean) ** 2 for x in b)) / (na + nb - 2)
    sd = math.sqrt(max(var, 1e-12))
    q1, q3 = pct(a + b, .25), pct(a + b, .75)
    iqr_sd = (q3 - q1) / 1.349 if q3 > q1 else 0.0
    sd = max(sd, iqr_sd, 1e-9)
    h = 1.06 * sd * (na * nb / (na + nb)) ** .2
    lo, hi = min(a + b) - 3 * h, max(a + b) + 3 * h
    if hi <= lo:
        return 1.0
    step = (hi - lo) / ngrid
    fa = [0.0] * ngrid
    fb = [0.0] * ngrid
    inv = 1.0 / h
    for i in range(ngrid):
        x = lo + (i + .5) * step
        fa[i] = sum(math.exp(-.5 * ((x - v) * inv) ** 2) for v in a)
        fb[i] = sum(math.exp(-.5 * ((x - v) * inv) ** 2) for v in b)
    sa, sb = sum(fa), sum(fb)
    if sa <= 0 or sb <= 0:
        return float("nan")
    return sum(min(fa[i] / sa, fb[i] / sb) for i in range(ngrid))


def pct_rank(x, vals):
    """Where x sits inside vals, in percent (50 = typical human)."""
    if not vals:
        return float("nan")
    s = sorted(vals)
    return 100 * (bisect.bisect_left(s, x) + .5 * (bisect.bisect_right(s, x)
                                                   - bisect.bisect_left(s, x))) / len(s)


def ks_ci(a, b, reps=300, seed=0, level=.90):
    """Bootstrap percentile CI for KS. Seeded per metric so runs diff cleanly."""
    na, nb = len(a), len(b)
    if na < 2 or nb < 2 or reps < 2:
        return None
    rng = random.Random(seed)
    vals = []
    for _ in range(reps):
        vals.append(ks_dist([a[rng.randrange(na)] for _ in range(na)],
                            [b[rng.randrange(nb)] for _ in range(nb)]))
    vals.sort()
    return (vals[int((1 - level) / 2 * reps)],
            vals[min(reps - 1, int((1 + level) / 2 * reps))])


def median(v):
    s = sorted(v)
    return s[len(s) // 2] if len(s) % 2 else (s[len(s) // 2 - 1] + s[len(s) // 2]) / 2


def entropy16(yaws):
    bins = [0] * 16
    for y in yaws:
        bins[int((y % 360) // 22.5) % 16] += 1
    n = len(yaws)
    return -sum((c / n) * math.log2(c / n) for c in bins if c)


def js_div(p, q, alpha=0.5):
    """Jensen-Shannon divergence (bits) between two Counters, smoothed."""
    keys = set(p) | set(q)
    if not keys:
        return None
    sp = sum(p.values()) + alpha * len(keys)
    sq = sum(q.values()) + alpha * len(keys)
    d = 0.0
    for k in keys:
        a = (p.get(k, 0) + alpha) / sp
        b = (q.get(k, 0) + alpha) / sq
        m = (a + b) / 2
        d += 0.5 * a * math.log2(a / m) + 0.5 * b * math.log2(b / m)
    return d


def bin_of(v, edges):
    return bisect.bisect_left(edges, v)


def clean_name(s):
    return re.sub(r"[\x00-\x1f]", "", re.sub(r"\^.", "", s)).strip()


# ---------------------------------------------------------------- loading

def map_intervals(wins, want):
    """[start, end) serverTime windows for one map, in demo order."""
    iv, ordered = [], sorted(wins)
    for i, (t, m, _g) in enumerate(ordered):
        if m == want:
            iv.append((t, ordered[i + 1][0] if i + 1 < len(ordered) else 10 ** 18))
    return iv


def make_inside(iv):
    starts = [a for a, _b in iv]

    def inside(t):
        i = bisect.bisect_right(starts, t) - 1
        return i >= 0 and t < iv[i][1]
    return inside


def load_players(path, inside):
    """Per-client row tuples + per-snapshot positions, map windows only."""
    by = collections.defaultdict(list)
    snap = collections.defaultdict(list)
    with open(path, newline="") as f:
        rd = csv.reader(f)
        ix = {k: i for i, k in enumerate(next(rd))}
        it, ic, itm = ix["t"], ix["client"], ix["team"]
        ixx, iy, iz, ip, iyw = ix["x"], ix["y"], ix["z"], ix["pitch"], ix["yaw"]
        ief, iw, ig = ix["eflags"], ix["weapon"], ix["ground"]
        for r in rd:
            t = int(r[it])
            if not inside(t) or r[itm] in SPEC:
                continue
            p = float(r[ip])
            if p > 180:
                p -= 360
            x, y, z = float(r[ixx]), float(r[iy]), float(r[iz])
            by[r[ic]].append((t, x, y, z, p, float(r[iyw]), int(r[ief]),
                              int(r[iw]), int(r[ig]), r[itm]))
            snap[t].append((r[ic], x, y, z, r[itm]))
    for rs in by.values():
        rs.sort()
    return by, snap


def load_deaths(path, inside):
    """Death times per client from corpse entities.

    corpses.csv repeats every corpse on every snapshot; a death is the FIRST
    sighting of a corpse entity with a new owner or position (body-queue slots
    get reused)."""
    deaths = collections.defaultdict(list)
    if not os.path.exists(path):
        return deaths
    state = {}
    with open(path, newline="") as f:
        rd = csv.reader(f)
        ix = {k: i for i, k in enumerate(next(rd))}
        it, inum, icl, ixx, iy = ix["t"], ix["number"], ix["client"], ix["x"], ix["y"]
        for r in rd:
            t = int(r[it])
            num, cl = r[inum], r[icl]
            x, y = float(r[ixx]), float(r[iy])
            old = state.get(num)
            if old is None or old[0] != cl or math.hypot(old[1] - x, old[2] - y) > 16:
                if inside(t):
                    deaths[cl].append(t)
            state[num] = (cl, x, y)
    for v in deaths.values():
        v.sort()
    return deaths


THROWER_DIST = 100  # a fresh projectile appears ~60u from the thrower


def thrower(snap, t, x, y, z):
    best, bd = None, THROWER_DIST
    for cl, px, py, pz, _tm in snap.get(t, ()):
        d = math.dist((x, y, z), (px, py, pz + 40))
        if d < bd:
            best, bd = cl, d
    return best


def load_throws(path, inside, snap):
    """Grenade/projectile throws per client (nadestats.kind-compatible dicts).

    The owner column is never decoded (always 0/64), so a throw belongs to the
    nearest player within THROWER_DIST at its first sighting; others are dropped."""
    throws = collections.defaultdict(list)
    if not os.path.exists(path):
        return throws
    cur = {}
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            t = int(r["t"])
            if not inside(t):
                continue
            num = r["number"]
            c = cur.get(num)
            if c and t - c["last"] <= 500 and c["w"] == r["weapon"]:
                c["last"] = t
                continue
            if c and c["client"] is not None:
                throws[c["client"]].append(c)
            cur[num] = {"first": t, "last": t, "w": r["weapon"], "tr": r["trtype"],
                        "client": thrower(snap, t, float(r["x"]), float(r["y"]), float(r["z"]))}
    for c in cur.values():
        if c["client"] is not None:
            throws[c["client"]].append(c)
    for v in throws.values():
        v.sort(key=lambda c: c["first"])
    return throws


def parse_scoreboard(text):
    """'b' command -> [(client, score, ping, deaths, kills, assists)].

    Layout (checked on NamelessNoobs S&D, score = 5 * kills): b <n> <4 header
    fields> then per client: client score ping deaths status kills assists."""
    f = text.split()
    if len(f) < 6 or f[0] != "b":
        return []
    try:
        n = int(f[1])
    except ValueError:
        return []
    out, rest = [], f[5:]
    for i in range(n):
        g = rest[i * 7:(i + 1) * 7]
        if len(g) < 7:
            break
        try:
            row = (g[0], int(g[1]), int(g[2]), int(g[3]), int(g[5]), int(g[6]))
        except ValueError:
            continue
        out.append(row)
    return out


CHAT_PREFIX = re.compile(r"^\((GAME_DEAD|DEAD|Team|GAME_TEAM)\)")


def parse_chat(text):
    """'h' command -> (sender, text, dead) or None for server announcements."""
    m = re.match(r'^h "(.*)"\s*$', text, re.S)
    if not m:
        return None
    body = clean_name(m.group(1))
    if ": " not in body or body.startswith("(NN)"):
        return None
    who, msg = body.split(": ", 1)
    dead = "(GAME_DEAD)" in who or "(DEAD)" in who
    sender = who.strip()
    while CHAT_PREFIX.match(sender):
        sender = CHAT_PREFIX.sub("", sender).strip()
    if sender.lower().startswith("server"):
        return None
    return sender, msg.strip(), dead


def resolve_sender(sender, name_to_cl):
    s = sender.lower()
    if s in name_to_cl:
        return name_to_cl[s]
    hits = [c for n, c in name_to_cl.items() if n and (n in s or s in n)]
    return hits[0] if len(hits) == 1 else None


def load_commands(meta, names, inside):
    """Chat per client + scoreboard series per client."""
    name_to_cl = {n.lower(): c for c, n in names.items()}
    chat = collections.defaultdict(list)       # client -> [(t, text, dead)]
    board = collections.defaultdict(list)      # client -> [(t, score, ping, deaths, kills, assists)]
    last_chat = None
    for c in meta["serverCommands"]:
        t = c.get("time", -1)
        if not inside(t):
            continue
        txt = c["text"]
        if txt.startswith("h "):
            pc = parse_chat(txt)
            if pc is None or pc == last_chat:  # announcement / reliable command resent
                continue
            last_chat = pc
            cl = resolve_sender(pc[0], name_to_cl)
            if cl is not None:
                chat[cl].append((t, pc[1], pc[2]))
        elif txt.startswith("b "):
            for cl, sc, pg, de, ki, asn in parse_scoreboard(txt):
                board[cl].append((t, sc, pg, de, ki, asn))
    return chat, board


BOARD_GAP = 10  # minutes; 'b' is only sent while the recorder holds TAB, so it is sparse


def board_rates(series):
    """Positive increments over time; a drop in any counter means a reset."""
    if len(series) < 2:
        return None
    mins = 0.0
    inc = [0, 0, 0, 0]  # score, deaths, kills, assists
    for a, b in zip(series, series[1:]):
        gap = (b[0] - a[0]) / 60000
        if gap <= 0 or gap > BOARD_GAP:
            continue
        mins += gap
        va, vb = (a[1], a[3], a[4], a[5]), (b[1], b[3], b[4], b[5])
        if any(y < x for x, y in zip(va, vb)):
            continue
        for k in range(4):
            inc[k] += vb[k] - va[k]
    return {"mins": mins, "score": inc[0], "deaths": inc[1], "kills": inc[2],
            "assists": inc[3], "pings": [s[2] for s in series]}


def round_starts(snap):
    ts = sorted(snap)
    n = [len(snap[t]) for t in ts]
    starts, j = [], 0
    for i in range(len(ts)):
        j = max(j, i)
        while j < len(ts) and ts[j] - ts[i] < 3000:
            j += 1
        if j < len(ts) and n[j - 1] - n[i] >= 6 and (not starts or ts[i] - starts[-1] > 30000):
            starts.append(ts[j - 1])
    return starts


def fire_onsets(by):
    """Enemy-audible stimuli: (t, x, y, team) at each rising edge of the fire bit."""
    out = []
    for rs in by.values():
        was = False
        for r in rs:
            fire = r[EF] >> 6 & 1
            if fire and not was:
                out.append((r[T], r[X], r[Y], r[TM]))
            was = fire
    out.sort()
    return out


# ---------------------------------------------------------------- 5Hz attention + state

def state_of(sm):
    if sm["fire"]:
        return "fire"
    moving = sm["speed"] >= 25
    if sm["prone"]:
        return "prone"
    if sm["crouch"]:
        return "crouch_move" if moving else "crouch_still"
    if sm["ads"]:
        return "ads_move" if moving else "ads_still"
    if not moving:
        return "still"
    return "sprint" if sm["speed"] >= 230 else "run" if sm["speed"] >= 160 else "walk"


def sample_subject(rows, snap, bursts, btimes, starts=()):
    """5Hz samples + movestats-compatible samples + mate spacing."""
    out, mv, mates = [], [], []
    last = None
    for r in rows:
        t = r[T]
        if last is not None and t - last[T] < 180:
            continue
        if last is not None and t - last[T] > 500:
            out.append(None)
        if last is not None and t > last[T]:
            dt = (t - last[T]) / 1000.0
            vx, vy, vz = (r[X] - last[X]) / dt, (r[Y] - last[Y]) / dt, (r[Z] - last[Z]) / dt
            if math.hypot(vx, vy) > 600:
                last = r
                continue
            ef = r[EF]
            x, y, yaw, team = r[X], r[Y], r[YW], r[TM]
            prone = bool(ef >> 3 & 1)
            ads = bool(ef >> 18 & 1)
            speed = math.hypot(vx, vy)
            near_b, near_d, mate_d = None, 1e9, 1e9
            for _oc, ox, oy, _oz, ot in snap.get(t, ()):
                if ox == x and oy == y and ot == team:
                    continue  # self
                d = math.hypot(ox - x, oy - y)
                if ot == team:
                    mate_d = min(mate_d, d)
                elif d < near_d:
                    near_d, near_b = d, bearing(x, y, ox, oy)
            heard_b = None
            i = bisect.bisect_right(btimes, t) - 1
            while i >= 0 and t - bursts[i][0] <= HEAR_AGE:
                _bt, bx, by, bteam = bursts[i]
                if bteam != team and math.hypot(bx - x, by - y) < HEAR_DIST:
                    heard_b = bearing(x, y, bx, by)
                    break
                i -= 1
            k = bisect.bisect_right(starts, t) - 1
            phase = (t - starts[k]) / 1000.0 if k >= 0 else None
            sm = {"t": t, "x": x, "y": y, "yaw": yaw, "speed": speed,
                  "vx": vx, "vy": vy, "fire": ef >> 6 & 1, "prone": prone,
                  "crouch": bool(ef >> 2 & 1 or prone), "ads": ads, "team": team,
                  "cell": (round(x / CELL), round(y / CELL), round(r[Z] / LEVEL)),
                  "heat": (round(x / HEAT), round(y / HEAT)),
                  "near_b": near_b, "near_d": near_d, "heard_b": heard_b, "phase": phase}
            sm["state"] = state_of(sm)
            out.append(sm)
            mv.append({"x": x, "y": y, "z": r[Z], "vx": vx, "vy": vy, "vz": vz,
                       "pitch": r[P], "yaw": yaw,
                       "stance": "prone" if prone else "crouch" if ef >> 2 & 1 else "stand",
                       "ads": 10 if ads else 0, "tgt": False})
            mates.append(mate_d)
        last = r
    return out, mv, mates


def analyze_feel(samples, bursts):
    s = {"micro": [], "holds": [], "preaim": [], "delays": [],
         "stim": 0, "miss": 0, "still_cells": [], "cells": collections.Counter(),
         "heat": collections.Counter(), "look_enemy": [0, 0], "look_shot": [0, 0]}
    visited, hold, open_ev = {}, 0, collections.deque()
    prev = None
    bi = 0

    def close_all():
        while open_ev:
            s["miss"] += 1
            open_ev.popleft()

    for sm in samples:
        if sm is None:
            if hold >= 2:
                s["holds"].append(hold * 0.2)
            hold, prev = 0, None
            close_all()
            continue
        prev2, prev = prev, sm
        s["cells"][sm["cell"]] += 1
        s["heat"][sm["heat"]] += 1
        still = sm["speed"] < 25
        while bi < len(bursts) and bursts[bi][0] <= sm["t"]:
            bt, bx, by, bteam = bursts[bi]
            bi += 1
            if sm["t"] - bt <= REACT_WINDOW and bteam != sm["team"] \
                    and math.hypot(bx - sm["x"], by - sm["y"]) < HEAR_DIST:
                open_ev.append((bt, bearing(sm["x"], sm["y"], bx, by)))
                s["stim"] += 1
        if not sm["fire"]:
            while open_ev:
                bt, bb = open_ev[0]
                if sm["t"] - bt > REACT_WINDOW:
                    s["miss"] += 1
                    open_ev.popleft()
                elif angdiff(sm["yaw"], bb) < CONE:
                    s["delays"].append((sm["t"] - bt) / 1000.0)
                    open_ev.popleft()
                else:
                    break
        if still and not sm["fire"] and prev2 is not None:
            dt = (sm["t"] - prev2["t"]) / 1000.0
            if 0 < dt <= 0.5:
                s["micro"].append(angdiff(sm["yaw"], prev2["yaw"]) / dt)
            s["still_cells"].append((sm["cell"], sm["yaw"]))
        if still and sm["ads"] and not sm["fire"]:
            hold += 1
        else:
            if hold >= 2:
                s["holds"].append(hold * 0.2)
            hold = 0
        # corner entry: first visit to a cell in 10s while moving -> view vs move dir
        if sm["t"] - visited.get(sm["cell"], -1e9) > 10000 and sm["speed"] > 60 \
                and prev2 is not None and prev2["speed"] > 60:
            mvd = math.degrees(math.atan2(prev2["vy"] + sm["vy"], prev2["vx"] + sm["vx"]))
            s["preaim"].append(angdiff(sm["yaw"], mvd))
        visited[sm["cell"]] = sm["t"]
        if not sm["fire"]:
            if sm["near_b"] is not None:
                s["look_enemy"][1] += 1
                s["look_enemy"][0] += angdiff(sm["yaw"], sm["near_b"]) < CONE
            if sm["heard_b"] is not None:
                s["look_shot"][1] += 1
                s["look_shot"][0] += angdiff(sm["yaw"], sm["heard_b"]) < CONE
    if hold >= 2:
        s["holds"].append(hold * 0.2)
    close_all()
    return s


def feel_scalars(s):
    o = {}
    o["fidget"] = share(sum(m > 5 for m in s["micro"]), len(s["micro"]), 20)
    o["hold_p50"] = pct(s["holds"], .5) if len(s["holds"]) >= 3 else None
    o["hold_max"] = max(s["holds"]) if s["holds"] else None
    o["preaim_p50"] = pct(s["preaim"], .5) if len(s["preaim"]) >= 5 else None
    o["react_p50"] = pct(s["delays"], .5) if len(s["delays"]) >= 5 else None
    o["react_p90"] = pct(s["delays"], .9) if len(s["delays"]) >= 5 else None
    o["react_miss"] = share(s["miss"], s["stim"], 5)
    cells_yaw = collections.defaultdict(list)
    for cell, yaw in s["still_cells"]:
        cells_yaw[cell].append(yaw)
    ent, tot = 0.0, 0
    for yl in cells_yaw.values():
        if len(yl) >= 10:
            ent += entropy16(yl) * len(yl)
            tot += len(yl)
    o["gaze_ent"] = ent / tot if tot else None
    o["look_enemy"] = share(*s["look_enemy"], 50)
    o["look_shot"] = share(*s["look_shot"], 50)
    return o


# ---------------------------------------------------------------- context (anti "match the share")

BOUTS = {"crouch": ("crouch_still", "crouch_move"), "prone": ("prone",),
         "still": ("still", "ads_still", "crouch_still"), "ads": ("ads_still", "ads_move"),
         "run": ("run", "sprint")}


def context_counts(samples):
    """Counters the human prior is built from (and subtracted from, leave-one-out)."""
    c = {"where": collections.Counter(), "when": collections.Counter(),
         "threat": collections.Counter(), "trans": collections.Counter()}
    prev = None
    for sm in samples:
        if sm is None:
            prev = None
            continue
        st = sm["state"]
        c["where"][((sm["cell"], (round(sm["x"] / AREA), round(sm["y"] / AREA))), st)] += 1
        if sm["phase"] is not None and sm["phase"] < 300:
            c["when"][((bin_of(sm["phase"], PHASES),), st)] += 1
        c["threat"][((bin_of(sm["near_d"], THREAT),), st)] += 1
        if prev is not None:
            c["trans"][(prev, st)] += 1
        prev = st
    return c


def context_scalars(samples):
    o = {}
    runs = collections.defaultdict(list)
    cur, n = None, 0
    for sm in samples + [None]:
        g = None
        if sm is not None:
            g = next((k for k, v in BOUTS.items() if sm["state"] in v), None)
        if g == cur and sm is not None:
            n += 1
            continue
        if cur is not None:
            runs[cur].append(n * 0.2)
        cur, n = g, 1
    for g in BOUTS:
        if len(runs[g]) >= 5:
            o[f"bout_{g}_p50"] = pct(runs[g], .5)
            o[f"bout_{g}_p90"] = pct(runs[g], .9)
    # minute-to-minute variation of state shares
    live = [sm for sm in samples if sm]
    blocks = [live[i:i + 300] for i in range(0, len(live) - 299, 300)]
    if len(blocks) >= 3:
        for g in ("still", "crouch", "ads"):
            sh = [100 * sum(sm["state"] in BOUTS[g] for sm in b) / len(b) for b in blocks]
            m = sum(sh) / len(sh)
            o[f"var_{g}"] = math.sqrt(sum((x - m) ** 2 for x in sh) / (len(sh) - 1))
    # state share near vs away from enemies: does the stance react to threat?
    near = [sm for sm in live if sm["near_d"] < 1000]
    far = [sm for sm in live if sm["near_d"] >= 2000]
    if len(near) >= 50 and len(far) >= 50:
        for g in ("crouch", "still", "ads"):
            a = sum(sm["state"] in BOUTS[g] for sm in near) / len(near)
            b = sum(sm["state"] in BOUTS[g] for sm in far) / len(far)
            o[f"lift_{g}"] = 100 * (a - b)
    return o


def cond_lift(own, prior, prior_own, min_ctx=20):
    """Mean log2 P_h(state | ctx) / P_h(state) over the session's samples.

    ctx is a tuple of levels, fine to coarse; each sample uses the finest level
    with >= min_ctx human samples (leave-one-out) and is skipped if none has."""
    if not prior:
        return None
    levels = len(next(iter(prior))[0])
    joint = [collections.Counter() for _ in range(levels)]
    ctx_tot = [collections.Counter() for _ in range(levels)]
    st_tot = collections.Counter()
    for table, sign in ((prior, 1), (prior_own, -1)):
        for (cx, st), v in table.items():
            st_tot[st] += sign * v
            for lv in range(levels):
                joint[lv][(cx[lv], st)] += sign * v
                ctx_tot[lv][cx[lv]] += sign * v
    total = sum(st_tot.values())
    k = len(STATES)
    lift, n = 0.0, 0
    for (cx, st), v in own.items():
        for lv in range(levels):
            nc = ctx_tot[lv][cx[lv]]
            if nc >= min_ctx:
                pc = (joint[lv][(cx[lv], st)] + 0.5) / (nc + 0.5 * k)
                break
        else:
            continue
        ps = (st_tot[st] + 0.5) / (total + 0.5 * k)
        lift += v * math.log2(pc / ps)
        n += v
    return lift / n if n >= 100 else None


def trans_entropy(trans):
    """Conditional entropy H(next | prev) in bits (5Hz, self-transitions included)."""
    by = collections.defaultdict(collections.Counter)
    for (a, b), v in trans.items():
        by[a][b] += v
    tot = sum(trans.values())
    h = 0.0
    for c in by.values():
        n = sum(c.values())
        h += n / tot * -sum(v / n * math.log2(v / n) for v in c.values())
    return h


# ---------------------------------------------------------------- 20Hz texture

def frames(rows):
    """Consecutive 20Hz steps: (t, dt, dyaw, dpitch, speed, vx, vy, row) or None at breaks."""
    out = []
    for a, b in zip(rows, rows[1:]):
        dt = (b[T] - a[T]) / 1000.0
        if not 0 < dt <= MAX_DT:
            out.append(None)
            continue
        vx, vy = (b[X] - a[X]) / dt, (b[Y] - a[Y]) / dt
        sp = math.hypot(vx, vy)
        if sp > 600:
            out.append(None)
            continue
        out.append((b[T], dt, sdiff(b[YW], a[YW]), b[P] - a[P], sp, vx, vy, b))
    return out


def find_flicks(fr, start_dps=120, keep_dps=30, min_amp=10):
    """Fast same-direction yaw movements: (amp, peak dps, dur s, overshoot, peak/mean, end idx)."""
    out = []
    i, n = 0, len(fr)

    def moving(k, s):
        f = fr[k]
        return f is not None and f[2] * s > 0 and abs(f[2]) / f[1] > keep_dps

    while i < n:
        f = fr[i]
        if f is None or abs(f[2]) / f[1] < start_dps:
            i += 1
            continue
        s = 1 if f[2] > 0 else -1
        a = i
        floor = out[-1][5] + 1 if out else 0
        while a - 1 >= floor and moving(a - 1, s):
            a -= 1
        j = i
        while j < n and moving(j, s):
            j += 1
        amp = sum(abs(fr[k][2]) for k in range(a, j))
        dur = sum(fr[k][1] for k in range(a, j))
        peak = max(abs(fr[k][2]) / fr[k][1] for k in range(a, j))
        back = 0.0
        for k in range(j, min(n, j + 6)):
            if fr[k] is None:
                break
            if fr[k][2] * s < 0:
                back += abs(fr[k][2])
        if amp >= min_amp:
            out.append((amp, peak, dur, back > max(1.0, 0.05 * amp), peak / (amp / dur), j - 1))
        i = j
    return out


def aim_texture(fr, alive_s):
    o = {}
    live = [f for f in fr if f]
    if len(live) < 200:
        return o
    turns = [abs(f[2]) / f[1] for f in live]
    o["turn_active"] = 100 * sum(t > 0 for t in turns) / len(turns)
    o["turn_p90"] = pct(turns, .9)
    o["turn_p99"] = pct(turns, .99)
    run = [abs(f[2]) / f[1] for f in live if f[4] > 150]
    o["turn_run_p90"] = pct(run, .9) if len(run) >= 100 else None
    mov = [f for f in live if f[4] > 100]
    o["freeze_move"] = share(sum(abs(f[2]) < EPS and abs(f[3]) < EPS for f in mov), len(mov), 100)
    turning = [f for f in live if abs(f[2]) / f[1] > 30]
    o["pure_yaw"] = share(sum(abs(f[3]) < EPS for f in turning), len(turning), 50)
    pit = [f for f in live if abs(f[3]) / f[1] > 30]
    o["pure_pitch"] = share(sum(abs(f[2]) < EPS for f in pit), len(pit), 30)
    o["pitch_zero"] = share(sum(abs(f[7][P]) < 0.01 for f in live), len(live), 200)
    ps = [f[7][P] for f in live]
    m = sum(ps) / len(ps)
    o["pitch_p90"] = pct([abs(p - m) for p in ps], .9)
    flips, prev = 0, None
    for f in fr:
        if f is None:
            prev = None
            continue
        if abs(f[2]) < 0.02:
            continue
        s = f[2] > 0
        if prev is not None and s != prev:
            flips += 1
        prev = s
    mins = alive_s / 60
    if mins >= 1:
        o["tremor"] = flips / alive_s
    stretch, frozen, longest = 0.0, 0, 0.0
    for f in fr + [None]:
        if f and f[4] < 20 and abs(f[2]) < EPS and abs(f[3]) < EPS:
            stretch += f[1]
            continue
        frozen += stretch >= 2
        longest = max(longest, stretch)
        stretch = 0.0
    if mins >= 1:
        o["frozen_min"] = frozen / mins
    o["frozen_max"] = longest
    fl = find_flicks(fr)
    if mins >= 1:
        o["flicks_min"] = len(fl) / mins
    if len(fl) >= 5:
        o["flick_amp"] = pct([f[0] for f in fl], .5)
        o["flick_peak"] = pct([f[1] for f in fl], .5)
        o["flick_dur"] = pct([f[2] for f in fl], .5)
        o["flick_over"] = 100 * sum(f[3] for f in fl) / len(fl)
        o["flick_shape"] = pct([f[4] for f in fl], .5)
        o["flick_fitts"] = pct([f[2] / math.log2(1 + f[0] / 2) for f in fl], .5)
    return o


def move_texture(rows, fr, alive_s):
    o = {}
    rel = []
    for f in fr:
        if f and f[4] > 100 and f[7][G] != AIR:
            d = sdiff(math.degrees(math.atan2(f[6], f[5])), f[7][YW])
            rel.append(abs(((d + 22.5) % 45) - 22.5))
    o["wasd"] = share(sum(r < 3 for r in rel), len(rel), 200)
    o["wasd_off_p50"] = pct(rel, .5) if len(rel) >= 200 else None
    tog = collections.Counter()
    for a, b in zip(rows, rows[1:]):
        if 0 < b[T] - a[T] <= MAX_DT * 1000:
            for bit, k in ((2, "crouch"), (3, "prone"), (18, "ads")):
                if b[EF] >> bit & 1 and not a[EF] >> bit & 1:
                    tog[k] += 1
    if alive_s >= 60:
        for k in ("crouch", "prone", "ads"):
            o[k + "_on_min"] = tog[k] / (alive_s / 60)
    # run -> still: hard stop (<=0.2s) vs coasting
    stops, soft = 0, 0
    for k in range(len(fr) - 10):
        f = fr[k]
        if f is None or f[4] < 170:
            continue
        for m in range(k + 1, k + 11):
            g = fr[m]
            if g is None or g[4] >= 170:
                break
            if g[4] < 20:
                if m - k <= 4:
                    stops += 1
                else:
                    soft += 1
                break
    o["hard_stop"] = share(stops, stops + soft, 10)
    return o


def analyze_fight(rows, snap):
    """Per-session gunfight texture from 20Hz rows."""
    g = {"bursts": [], "gaps": [], "flicks": [], "speeds": [], "strafe": [0, 0],
         "crouch": [0, 0], "ads": [0, 0], "air": [0, 0], "aim": [], "dists": [],
         "prefire": 0, "shots": 0, "ads_lead": [], "swap": [0, 0]}
    fire = [r[EF] >> 6 & 1 for r in rows]
    ts = [r[T] for r in rows]
    n = len(rows)
    bursts, i = [], 0
    while i < n:
        if fire[i]:
            j = i + 1
            while j < n and ts[j] - ts[j - 1] <= 500 and (fire[j] or any(fire[j:j + 5])):
                j += 1
            while not fire[j - 1]:
                j -= 1
            bursts.append((i, j))
            i = j
        else:
            i += 1
    for k, (a, b) in enumerate(bursts):
        g["bursts"].append((ts[b - 1] - ts[a]) / 1000.0 + 0.05)
        if k:
            g["gaps"].append((ts[a] - ts[bursts[k - 1][1] - 1]) / 1000.0)
        if a >= 10 and ts[a] - ts[a - 10] <= 600:
            g["flicks"].append(math.hypot(angdiff(rows[a][YW], rows[a - 10][YW]),
                                          rows[a][P] - rows[a - 10][P]))
        if rows[a][EF] >> 18 & 1:
            m = a
            while m > 0 and rows[m - 1][EF] >> 18 & 1 and ts[m] - ts[m - 1] <= 150:
                m -= 1
            if m > 0 and ts[m] - ts[m - 1] <= 150 and ts[a] - ts[m] <= 3000:
                g["ads_lead"].append((ts[a] - ts[m]) / 1000.0)
        # another weapon within 1.5s after the burst (swap instead of reload)
        end_t, w0 = ts[b - 1], rows[b - 1][W]
        m = b
        while m < n and ts[m] - end_t <= 1500 and ts[m] - ts[m - 1] <= 150:
            m += 1
        if m > b:
            g["swap"][1] += 1
            g["swap"][0] += any(rows[q][W] != w0 for q in range(b, m))
        seen_enemy = False
        for m in range(a + 1, b):
            r0, r1 = rows[m - 1], rows[m]
            dt = (r1[T] - r0[T]) / 1000.0
            if dt <= 0 or dt > 0.5:
                continue
            vx, vy = (r1[X] - r0[X]) / dt, (r1[Y] - r0[Y]) / dt
            sp = math.hypot(vx, vy)
            if sp > 600:
                continue
            ef = r1[EF]
            g["speeds"].append(sp)
            g["crouch"][1] += 1
            g["crouch"][0] += bool(ef >> 2 & 1 or ef >> 3 & 1)
            g["ads"][1] += 1
            g["ads"][0] += ef >> 18 & 1
            g["air"][1] += 1
            g["air"][0] += r1[G] == AIR
            if sp > 40:
                g["strafe"][1] += 1
                g["strafe"][0] += 60 <= angdiff(r1[YW], math.degrees(math.atan2(vy, vx))) <= 120
            best, bdist = None, 0
            for _oc, ox, oy, _oz, ot in snap.get(r1[T], ()):
                if ot == r1[TM]:
                    continue
                dx, dy = ox - r1[X], oy - r1[Y]
                dist = math.hypot(dx, dy)
                if dist < 50:
                    continue
                err = angdiff(r1[YW], math.degrees(math.atan2(dy, dx)))
                if err < WIDE_CONE and (best is None or err < best):
                    best, bdist = err, dist
            if best is not None:
                seen_enemy = True
                g["aim"].append(best)
                g["dists"].append(bdist)
        g["shots"] += 1
        g["prefire"] += not seen_enemy
    return g


def fight_scalars(g, fmin):
    o = {}
    o["bursts_min"] = g["shots"] / fmin if fmin >= 1 else None
    o["burst_p50"] = pct(g["bursts"], .5) if len(g["bursts"]) >= 5 else None
    o["burst_p90"] = pct(g["bursts"], .9) if len(g["bursts"]) >= 5 else None
    o["gap_p50"] = pct(g["gaps"], .5) if len(g["gaps"]) >= 5 else None
    o["flick_p50"] = pct(g["flicks"], .5) if len(g["flicks"]) >= 5 else None
    o["aim_p50"] = pct(g["aim"], .5) if len(g["aim"]) >= 20 else None
    o["aim_p90"] = pct(g["aim"], .9) if len(g["aim"]) >= 20 else None
    o["dist_p50"] = pct(g["dists"], .5) if len(g["dists"]) >= 20 else None
    o["speed_fire"] = pct(g["speeds"], .5) if len(g["speeds"]) >= 20 else None
    for k in ("strafe", "crouch", "ads", "air"):
        o[k + "_fire"] = share(g[k][0], g[k][1], 50)
    o["prefire"] = share(g["prefire"], g["shots"], 5)
    o["ads_lead"] = pct(g["ads_lead"], .5) if len(g["ads_lead"]) >= 5 else None
    o["swap_fire"] = share(g["swap"][0], g["swap"][1], 5)
    return o


# ---------------------------------------------------------------- per session

MOVE_SKIP = {"in combat (has target) %", "idle gap between fights (s, median)"}


def analyze_session(rows, demo, client, min_minutes):
    snap, bursts, btimes, starts = demo["snap"], demo["bursts"], demo["btimes"], demo["starts"]
    samples, mv, mates = sample_subject(rows, snap, bursts, btimes, starts)
    minutes = sum(1 for s in samples if s) * 0.2 / 60
    if minutes < min_minutes:
        return None
    feel = analyze_feel(samples, bursts)
    fr = frames(rows)
    alive_s = sum(f[1] for f in fr if f)
    v = {}

    def put(sec, d):
        for k, x in d.items():
            if x is not None and not (isinstance(x, float) and math.isnan(x)):
                v[(sec, k)] = x

    put("feel", feel_scalars(feel))
    put("aim", aim_texture(fr, alive_s))
    mm = movestats.metrics(mv) or {}
    put("move", {k: mm[k] for k in movestats.GUESS if k in mm and k not in MOVE_SKIP})
    put("move", move_texture(rows, fr, alive_s))
    put("context", context_scalars(samples))
    put("fight", fight_scalars(analyze_fight(rows, snap), alive_s / 60))

    # life: scoreboard (authoritative), corpses (timing), round structure
    life = {}
    br = board_rates(demo["board"].get(client, []))
    if br and br["mins"] >= 3:
        m = br["mins"]
        life.update({"kills_min": br["kills"] / m, "deaths_min": br["deaths"] / m,
                     "assists_min": br["assists"] / m,
                     "kd": br["kills"] / max(br["deaths"], 1)})
    surv = []
    for t in demo["deaths"].get(client, []):
        i = bisect.bisect_right(starts, t) - 1
        if i >= 0 and 0 < t - starts[i] < 240000:
            surv.append((t - starts[i]) / 1000.0)
    if len(surv) >= 3:
        life["surv_p50"] = pct(surv, .5)
    exits, routes = [], []
    rts = [r[T] for r in rows]
    for s in starts:
        prev = None
        for r in rows[bisect.bisect_left(rts, s):]:
            if r[T] > s + 30000:
                break
            if prev and 0 < r[T] - prev[T] <= 100 and \
                    math.hypot(r[X] - prev[X], r[Y] - prev[Y]) / ((r[T] - prev[T]) / 1000) > 100:
                exits.append((r[T] - s) / 1000.0)
                break
            prev = r
        k = bisect.bisect_left(rts, s + 8000)
        if k < len(rows) and abs(rts[k] - (s + 8000)) <= 300:
            routes.append((round(rows[k][X] / HEAT), round(rows[k][Y] / HEAT)))
    if len(exits) >= 3:
        life["exit_p50"] = pct(exits, .5)
        life["exit_iqr"] = pct(exits, .75) - pct(exits, .25)
    if len(routes) >= 4:
        life["route_rep"] = 100 * collections.Counter(routes).most_common(1)[0][1] / len(routes)
    known = [d for d in mates if d < 1e9]
    if len(known) >= 20:
        life["mate_p50"] = pct(known, .5)
        life["alone"] = 100 * sum(d > 1000 for d in known) / len(known)
    put("life", life)

    th = demo["throws"].get(client, [])
    ordn = {"nades_min": len(th) / minutes}
    if len(th) >= 3:
        ordn["frag_share"] = 100 * sum(nadestats.kind(t) == "frag (uncooked)" for t in th) / len(th)
    present, spawn = 0, 0
    tf = [t["first"] for t in th]
    for s in starts:
        a = bisect.bisect_left(rts, s)
        if a < len(rts) and rts[a] - s <= 10000:
            present += 1
            k = bisect.bisect_left(tf, s)
            spawn += k < len(tf) and tf[k] - s <= 20000
    ordn["spawn_nade"] = share(spawn, present, 4)
    put("ordnance", ordn)

    wrows = [r[W] for r in rows]
    wc = collections.Counter(wrows)
    if alive_s >= 60:
        put("loadout", {"switches_min": sum(1 for a, b in zip(wrows, wrows[1:]) if a != b) / (alive_s / 60),
                        "distinct": len(wc),
                        "top_share": 100 * max(wc.values()) / len(wrows)})

    soc = {}
    span_min = (rows[-1][T] - rows[0][T]) / 60000
    if br and br["mins"] >= 1:
        span_min = max(span_min, br["mins"])
    msgs = demo["chat"].get(client, [])
    if span_min >= 1:
        soc["chat_min"] = len(msgs) / span_min
    if len(msgs) >= 2:
        soc["chat_len"] = pct([len(m[1]) for m in msgs], .5)
    if len(msgs) >= 3:
        soc["chat_dead"] = 100 * sum(m[2] for m in msgs) / len(msgs)
        soc["chat_lower"] = 100 * sum(m[1] == m[1].lower() for m in msgs) / len(msgs)
    if br and br["pings"]:
        soc["ping"] = pct(br["pings"], .5)
        if len(br["pings"]) >= 3:
            soc["ping_jit"] = pct(br["pings"], .9) - pct(br["pings"], .1)
        if br["mins"] >= 3:
            soc["score_min"] = br["score"] / br["mins"]
    put("social", soc)

    return {"name": demo["names"].get(client, "#" + client) + "@" + demo["tag"],
            "minutes": minutes, "v": v, "still_cells": feel["still_cells"],
            "cells": feel["cells"], "heat": feel["heat"], "chat": msgs,
            "ctx": context_counts(samples)}


def load_demo(base, want, group, min_minutes):
    meta = json.load(open(base + ".meta.json"))
    names = {k: clean_name(v["name"]) for k, v in meta["names"].items()}
    bots = demostats.bot_clients(meta, names)
    iv = map_intervals(gen_map_model.map_windows(meta), want)
    if not iv:
        print(f"{base}: no {want} windows, skipped", file=sys.stderr)
        return []
    inside = make_inside(iv)
    by, snap = load_players(base + ".players.csv", inside)
    if not by:
        return []
    bursts = fire_onsets(by)
    chat, board = load_commands(meta, names, inside)
    del meta
    demo = {"tag": os.path.basename(base), "names": names, "snap": snap,
            "bursts": bursts, "btimes": [b[0] for b in bursts],
            "starts": round_starts(snap),
            "deaths": load_deaths(base + ".corpses.csv", inside),
            "throws": load_throws(base + ".missiles.csv", inside, snap),
            "chat": chat, "board": board}
    want_bot = group == "bots"
    out = []
    for client, rows in sorted(by.items()):
        if (client in bots) != want_bot:
            continue
        s = analyze_session(rows, demo, client, min_minutes)
        if s:
            s["demo"] = demo["tag"]
            out.append(s)
    return out


# ---------------------------------------------------------------- human priors (leave-one-out)

def top_half(counter):
    tot = sum(counter.values()) or 1
    home, acc = set(), 0
    for c, cc in counter.most_common():
        home.add(c)
        acc += cc
        if acc >= tot / 2:
            break
    return home


def gaze_counts(still_cells):
    g = collections.defaultdict(lambda: [0, 0.0, 0.0])
    for cell, yaw in still_cells:
        q = g[cell]
        q[0] += 1
        q[1] += math.sin(math.radians(yaw))
        q[2] += math.cos(math.radians(yaw))
    return g


def apply_priors(sess):
    """Human map/gaze/context priors; each human is scored against the OTHER humans."""
    prior = collections.defaultdict(lambda: [0, 0.0, 0.0])
    hcells, hheat = collections.Counter(), collections.Counter()
    hctx = {k: collections.Counter() for k in ("where", "when", "threat", "trans")}
    for r in sess["humans"]:
        r["gaze"] = gaze_counts(r["still_cells"])
        for c, q in r["gaze"].items():
            p = prior[c]
            p[0] += q[0]
            p[1] += q[1]
            p[2] += q[2]
        hcells.update(r["cells"])
        hheat.update(r["heat"])
        for k in hctx:
            hctx[k].update(r["ctx"][k])
    no_ctx = {k: collections.Counter() for k in hctx}
    bot_home = top_half(hcells)
    for grp in ("humans", "bots"):
        human = grp == "humans"
        for r in sess[grp]:
            mine = r["gaze"] if human else {}
            errs = []
            for c, y in r["still_cells"]:
                p = prior.get(c)
                if p is None:
                    continue
                q = mine.get(c, (0, 0.0, 0.0))
                if p[0] - q[0] >= 10:
                    errs.append(angdiff(y, math.degrees(math.atan2(p[1] - q[1], p[2] - q[2]))))
            if len(errs) >= 20:
                r["v"][("feel", "yaw_err")] = pct(errs, .5)
            ref_cells = hcells - r["cells"] if human else hcells
            ref_heat = hheat - r["heat"] if human else hheat
            home = top_half(ref_cells) if human else bot_home
            stot = sum(r["cells"].values())
            if stot:
                r["v"][("feel", "home")] = 100 * sum(cc for c, cc in r["cells"].items() if c in home) / stot
            if stot >= 100 and ref_heat:
                r["v"][("feel", "heat_js")] = js_div(r["heat"], ref_heat)
            own = r["ctx"] if human else no_ctx
            for k in ("where", "when", "threat"):
                x = cond_lift(r["ctx"][k], hctx[k], own[k])
                if x is not None:
                    r["v"][("context", "ctx_" + k)] = x
            if sum(r["ctx"]["trans"].values()) >= 300:
                ref = hctx["trans"] - own["trans"]
                changes = collections.Counter({k: v for k, v in r["ctx"]["trans"].items() if k[0] != k[1]})
                ref_changes = collections.Counter({k: v for k, v in ref.items() if k[0] != k[1]})
                if sum(changes.values()) >= 30:
                    r["v"][("context", "trans_js")] = js_div(changes, ref_changes)
                r["v"][("context", "trans_ent")] = trans_entropy(r["ctx"]["trans"])
    return len([c for c, p in prior.items() if p[0] >= 10]), len(bot_home)


# ---------------------------------------------------------------- scoring

# section, key, label, format
METRICS = [
    ("aim", "turn_active", "frames the view moves (%)", "{:.0f}"),
    ("aim", "turn_p90", "view turn p90 (deg/s)", "{:.0f}"),
    ("aim", "turn_p99", "view turn p99 (deg/s)", "{:.0f}"),
    ("aim", "turn_run_p90", "view turn while running p90", "{:.0f}"),
    ("aim", "freeze_move", "view dead-still while moving (%)", "{:.0f}"),
    ("aim", "pure_yaw", "yaw turns with 0 pitch change (%)", "{:.0f}"),
    ("aim", "pure_pitch", "pitch moves with 0 yaw change (%)", "{:.0f}"),
    ("aim", "pitch_zero", "pitch exactly level (%)", "{:.1f}"),
    ("aim", "pitch_p90", "pitch spread p90 (deg)", "{:.1f}"),
    ("aim", "tremor", "turn direction flips (/s)", "{:.2f}"),
    ("aim", "frozen_min", "frozen-view stretches >2s (/min)", "{:.2f}"),
    ("aim", "frozen_max", "longest frozen view (s)", "{:.1f}"),
    ("aim", "flicks_min", "flicks >10deg (/min)", "{:.1f}"),
    ("aim", "flick_amp", "flick amplitude p50 (deg)", "{:.0f}"),
    ("aim", "flick_peak", "flick peak speed p50 (deg/s)", "{:.0f}"),
    ("aim", "flick_dur", "flick duration p50 (s)", "{:.2f}"),
    ("aim", "flick_over", "flicks that overshoot (%)", "{:.0f}"),
    ("aim", "flick_shape", "flick peak/mean speed p50", "{:.2f}"),
    ("aim", "flick_fitts", "flick s per Fitts bit p50", "{:.3f}"),
    ("feel", "fidget", "still time fidgeting (>5dps) (%)", "{:.0f}"),
    ("feel", "hold_p50", "ADS hold median (s)", "{:.1f}"),
    ("feel", "hold_max", "ADS hold longest (s)", "{:.1f}"),
    ("feel", "preaim_p50", "corner-entry aim err p50 (deg)", "{:.1f}"),
    ("feel", "react_p50", "reaction delay p50 (s)", "{:.2f}"),
    ("feel", "react_p90", "reaction delay p90 (s)", "{:.2f}"),
    ("feel", "react_miss", "stimuli ignored (%)", "{:.0f}"),
    ("feel", "gaze_ent", "gaze entropy (bits)", "{:.2f}"),
    ("feel", "yaw_err", "still-look err vs humans (deg)", "{:.1f}"),
    ("feel", "home", "time on human home turf (%)", "{:.0f}"),
    ("feel", "heat_js", "map heat divergence (bits)", "{:.3f}"),
    ("feel", "look_enemy", "looks at nearest enemy (%)", "{:.1f}"),
    ("feel", "look_shot", "looks at heard shot (%)", "{:.1f}"),
    ("move", "still %", "still (%)", "{:.0f}"),
    ("move", "slow (crouch/ADS/walk) %", "slow, crouch/ADS/walk (%)", "{:.0f}"),
    ("move", "sprint %", "sprint (%)", "{:.0f}"),
    ("move", "crouch %", "crouch (%)", "{:.0f}"),
    ("move", "prone %", "prone (%)", "{:.1f}"),
    ("move", "ADS while moving %", "ADS while moving (%)", "{:.1f}"),
    ("move", "look = move dir (<15deg) %", "look=move dir (%)", "{:.0f}"),
    ("move", "strafing (60-120deg) %", "strafing (%)", "{:.0f}"),
    ("move", "backpedal (>120deg) %", "backpedal (%)", "{:.1f}"),
    ("move", "view turn deg/s (median)", "view turn 5Hz median (deg/s)", "{:.1f}"),
    ("move", "snap heading changes /min", "snap heading changes (/min)", "{:.1f}"),
    ("move", "path straightness (2s)", "path straightness", "{:.2f}"),
    ("move", "jumps /min", "jumps (/min)", "{:.1f}"),
    ("move", "stop-go transitions /min", "stop-go (/min)", "{:.0f}"),
    ("move", "pitch mean (deg, +down)", "pitch mean (deg)", "{:.1f}"),
    ("move", "pitch sd", "pitch sd (deg)", "{:.1f}"),
    ("move", "dawdling (slow, facing fwd) %", "dawdling slow+fwd (%)", "{:.1f}"),
    ("move", "wasd", "move dir on 45deg grid (%)", "{:.0f}"),
    ("move", "wasd_off_p50", "move dir off 45deg grid p50", "{:.1f}"),
    ("move", "crouch_on_min", "crouch presses (/min)", "{:.1f}"),
    ("move", "prone_on_min", "prone drops (/min)", "{:.2f}"),
    ("move", "ads_on_min", "ADS presses (/min)", "{:.1f}"),
    ("move", "hard_stop", "run->still in <0.2s (%)", "{:.0f}"),
    ("context", "bout_crouch_p50", "crouch bout p50 (s)", "{:.1f}"),
    ("context", "bout_crouch_p90", "crouch bout p90 (s)", "{:.1f}"),
    ("context", "bout_prone_p50", "prone bout p50 (s)", "{:.1f}"),
    ("context", "bout_prone_p90", "prone bout p90 (s)", "{:.1f}"),
    ("context", "bout_still_p50", "still bout p50 (s)", "{:.1f}"),
    ("context", "bout_still_p90", "still bout p90 (s)", "{:.1f}"),
    ("context", "bout_ads_p50", "ADS bout p50 (s)", "{:.1f}"),
    ("context", "bout_ads_p90", "ADS bout p90 (s)", "{:.1f}"),
    ("context", "bout_run_p50", "run bout p50 (s)", "{:.1f}"),
    ("context", "bout_run_p90", "run bout p90 (s)", "{:.1f}"),
    ("context", "var_still", "still share sd per minute (pp)", "{:.1f}"),
    ("context", "var_crouch", "crouch share sd per minute (pp)", "{:.1f}"),
    ("context", "var_ads", "ADS share sd per minute (pp)", "{:.1f}"),
    ("context", "lift_crouch", "crouch near-far enemy (pp)", "{:.1f}"),
    ("context", "lift_still", "still near-far enemy (pp)", "{:.1f}"),
    ("context", "lift_ads", "ADS near-far enemy (pp)", "{:.1f}"),
    ("context", "ctx_where", "state fits WHERE (log-lift)", "{:.3f}"),
    ("context", "ctx_when", "state fits WHEN in round", "{:.3f}"),
    ("context", "ctx_threat", "state fits enemy distance", "{:.3f}"),
    ("context", "trans_js", "state-change mix vs humans (JS)", "{:.3f}"),
    ("context", "trans_ent", "state entropy rate (bits)", "{:.3f}"),
    ("fight", "bursts_min", "firing bursts (/min alive)", "{:.1f}"),
    ("fight", "burst_p50", "burst length p50 (s)", "{:.2f}"),
    ("fight", "burst_p90", "burst length p90 (s)", "{:.2f}"),
    ("fight", "gap_p50", "gap between bursts p50 (s)", "{:.2f}"),
    ("fight", "flick_p50", "pre-fire swing p50 (deg)", "{:.1f}"),
    ("fight", "aim_p50", "aim err to enemy p50 (deg)", "{:.1f}"),
    ("fight", "aim_p90", "aim err to enemy p90 (deg)", "{:.1f}"),
    ("fight", "dist_p50", "fight distance p50 (u)", "{:.0f}"),
    ("fight", "speed_fire", "speed while firing p50 (u/s)", "{:.0f}"),
    ("fight", "strafe_fire", "strafing while firing (%)", "{:.0f}"),
    ("fight", "crouch_fire", "crouched while firing (%)", "{:.0f}"),
    ("fight", "ads_fire", "ADS while firing (%)", "{:.0f}"),
    ("fight", "air_fire", "airborne while firing (%)", "{:.1f}"),
    ("fight", "prefire", "bursts at no enemy (%)", "{:.0f}"),
    ("fight", "ads_lead", "ADS -> first shot p50 (s)", "{:.2f}"),
    ("fight", "swap_fire", "weapon swap <1.5s after burst (%)", "{:.0f}"),
    ("life", "kills_min", "kills (/min, scoreboard)", "{:.2f}"),
    ("life", "deaths_min", "deaths (/min, scoreboard)", "{:.2f}"),
    ("life", "assists_min", "assists (/min, scoreboard)", "{:.2f}"),
    ("life", "kd", "K/D (scoreboard)", "{:.2f}"),
    ("life", "surv_p50", "death time into round p50 (s)", "{:.0f}"),
    ("life", "exit_p50", "round-start exit p50 (s)", "{:.1f}"),
    ("life", "exit_iqr", "round-start exit IQR (s)", "{:.1f}"),
    ("life", "route_rep", "same spot 8s into round (%)", "{:.0f}"),
    ("life", "mate_p50", "nearest-mate dist p50 (u)", "{:.0f}"),
    ("life", "alone", "no mate within 1000u (%)", "{:.0f}"),
    ("ordnance", "nades_min", "throws (/min)", "{:.2f}"),
    ("ordnance", "frag_share", "frag share of throws (%)", "{:.0f}"),
    ("ordnance", "spawn_nade", "rounds with a spawn nade (%)", "{:.0f}"),
    ("loadout", "switches_min", "weapon switches (/min)", "{:.1f}"),
    ("loadout", "distinct", "distinct weapons", "{:.0f}"),
    ("loadout", "top_share", "time on top weapon (%)", "{:.0f}"),
    ("social", "chat_min", "chat msgs (/min, 0 if silent)", "{:.2f}"),
    ("social", "chat_len", "chat msg length p50", "{:.0f}"),
    ("social", "chat_dead", "chat sent while dead (%)", "{:.0f}"),
    ("social", "chat_lower", "chat all-lowercase (%)", "{:.0f}"),
    ("social", "ping", "scoreboard ping p50 (ms)", "{:.0f}"),
    ("social", "ping_jit", "ping jitter p10-p90 (ms)", "{:.0f}"),
    ("social", "score_min", "score (/min)", "{:.1f}"),
]


def kde_bw(vals):
    n = len(vals)
    if n < 2:
        return 1e-3 * (1 + abs(sum(vals) / n)) if n else 1e-3
    m = sum(vals) / n
    sd = math.sqrt(sum((x - m) ** 2 for x in vals) / max(n - 1, 1))
    iqr = pct(vals, .75) - pct(vals, .25)
    s = min(sd, iqr / 1.34) if iqr > 0 else sd
    bw = 0.9 * s * n ** -0.2
    return bw if bw > 0 else 1e-3 * (1 + abs(m))


def log_kde(v, vals, bw):
    s = sum(math.exp(-0.5 * ((v - x) / bw) ** 2) for x in vals)
    return math.log(s / (len(vals) * bw * math.sqrt(2 * math.pi)) + 1e-300)


def detector(sess, keys):
    """Leave-one-out naive Bayes over all metrics -> (AUC, [(score, group, name)])."""
    cls = {g: {k: [r["v"][k] for r in sess[g] if k in r["v"]] for k in keys}
           for g in ("humans", "bots")}
    bws = {k: kde_bw(cls["humans"][k] + cls["bots"][k]) for k in keys}
    scored = []
    for g in ("humans", "bots"):
        for r in sess[g]:
            s = 0.0
            for k in keys:
                if k not in r["v"]:
                    continue
                x = r["v"][k]
                h, b = cls["humans"][k], cls["bots"][k]
                if g == "humans":
                    h = list(h)
                    h.remove(x)
                else:
                    b = list(b)
                    b.remove(x)
                if len(h) < 2 or len(b) < 2:
                    continue
                s += max(-3.0, min(3.0, log_kde(x, b, bws[k]) - log_kde(x, h, bws[k])))
            scored.append((s, g, r["name"]))
    return auc_of(scored), scored


def auc_of(scored):
    """P(bot scores above human) over all pairs; ties count a half."""
    hs = [s for s, g, _ in scored if g == "humans"]
    bs = [s for s, g, _ in scored if g == "bots"]
    if not hs or not bs:
        return None
    wins = sum((b > h) + 0.5 * (b == h) for b in bs for h in hs)
    return wins / (len(hs) * len(bs))


def detector_cv(sess, keys):
    """Leave-one-MATCH-out AUC: a session is scored by a KDE that never saw its match.

    detector() is leave-one-SESSION-out, so each KDE is still fitted on the other
    sessions of the same match. Every session of a match shares one human's
    habits, so that is optimistic, and tuning decisions are made in exactly the
    AUC range where the optimism matters. Both numbers get reported.

    Each fold trains on every match but `hold` and scores that match's sessions.
    The reference class is the fold's TRAINING humans: when all humans come from
    a single match there is no human match left to hold out, and in-train human
    scores are optimistic, so the number comes out conservative (human_kind says
    which case this run is).

    Returns (auc, folds, {"bots": [...], "humans": [...], "human_kind": str}).
    """
    demos = sorted({r.get("demo") for g in ("humans", "bots") for r in sess[g]} - {None})
    bots, humans = [], []
    folds = 0
    for hold in demos:
        train = {g: [r for r in sess[g] if r.get("demo") != hold] for g in ("humans", "bots")}
        if len(train["humans"]) < 3 or len(train["bots"]) < 3:
            continue
        folds += 1
        bws = {k: kde_bw([r["v"][k] for r in train["humans"] + train["bots"] if k in r["v"]])
               for k in keys}

        def sc(r, pool):
            s = 0.0
            for k in keys:
                if k not in r["v"]:
                    continue
                h = [x["v"][k] for x in train["humans"] if k in x["v"]]
                b = [x["v"][k] for x in train["bots"] if k in x["v"]]
                if len(h) < 2 or len(b) < 2:
                    continue
                s += max(-3.0, min(3.0, log_kde(r["v"][k], b, bws[k])
                                   - log_kde(r["v"][k], h, bws[k])))
            pool.append(s)

        for r in (x for x in sess["humans"] if x.get("demo") == hold):
            sc(r, humans)
        for r in (x for x in sess["bots"] if x.get("demo") == hold):
            sc(r, bots)
        for r in train["humans"]:
            sc(r, humans)  # in-fold reference class
    if not bots or not humans:
        return None, folds, {"bots": bots, "humans": humans,
                             "human_kind": "n/a" if not folds else "train"}
    wins = sum((b > h) + 0.5 * (b == h) for b in bots for h in humans)
    kind = ("held-out + train"
            if len({r.get("demo") for r in sess["humans"]}) > 1
            and len({r.get("demo") for r in sess["bots"]}) > 1 else "train")
    return wins / (len(bots) * len(humans)), folds, {"bots": bots, "humans": humans,
                                                    "human_kind": kind}


def iqr(v):
    return pct(v, .75) - pct(v, .25)


def seed_for(name):
    """Stable per-metric bootstrap seed (crc32, not hash(): salted per process)."""
    return zlib.crc32(name.encode()) & 0xffff


def score(sess, top, show_sessions, ignore=(), reps=300, metrics=None):
    """Per-metric human-vs-bot comparison plus the detector, with resolution data.

    Besides KS and p every metric gets:
      q      BH q-value -- with ~110 metrics, raw p<.05 flags ~5 by chance
      ci     bootstrap 90% CI on KS -- the sampling noise at these session counts
      ovl    overlap coefficient -- KS saturates at 1.00 on a single tail value,
             OVL shows how much of the distribution is actually shared
      rank   where the bot median sits inside the human distribution (percent)
      hself  human-vs-human KS across matches -- match-to-match variation is the
             yardstick; a tell smaller than that is not visible while playing
      bdemo  KS of each bot demo on its own -- a tell that holds in one match
             only is not a tell
    """
    dist = {g: collections.defaultdict(list) for g in ("humans", "bots")}
    ddist = {g: collections.defaultdict(lambda: collections.defaultdict(list))
             for g in ("humans", "bots")}
    for g in ("humans", "bots"):
        for r in sess[g]:
            for k, x in r["v"].items():
                dist[g][k].append(x)
                ddist[g][k][r.get("demo", "?")].append(x)

    rows = []
    metrics = metrics or METRICS
    nh, nb = len(sess["humans"]), len(sess["bots"])
    res_noise = 1.36 * math.sqrt((nh + nb) / (nh * nb)) if nh and nb else float("nan")
    for sec, key, label, fmt in metrics:
        name = f"{sec}.{key}"
        h, b = dist["humans"][(sec, key)], dist["bots"][(sec, key)]
        r = {"name": name, "sec": sec, "key": key, "label": label, "fmt": fmt, "h": h, "b": b,
             "thin": len(h) < 3 or len(b) < 3,
             "skip": any(fnmatch.fnmatch(name, g) for g in ignore)}
        if not r["thin"]:
            r["ks"] = ks_dist(h, b)
            r["p"] = ks_p(r["ks"], len(h), len(b))
            lo, hi = pct(h, .1), pct(h, .9)
            r["in"] = 100 * sum(lo <= x <= hi for x in b) / len(b)
            r["spread"] = iqr(b) / iqr(h) if iqr(h) > 0 else float("nan")
            r["score"] = 100 * (1 - r["ks"])
            r["ovl"] = ovl(h, b)
            r["ci"] = ks_ci(h, b, reps=reps, seed=seed_for(name))
            r["rank"] = pct_rank(median(b), h)
            # humans vs humans, one match held out at a time
            selfk = []
            for demo, vals in ddist["humans"][(sec, key)].items():
                if len(vals) < 3:
                    continue
                rest = [x for dd, vs in ddist["humans"][(sec, key)].items() if dd != demo
                        for x in vs]
                if len(rest) >= 3:
                    selfk.append(ks_dist(vals, rest))
            r["hself"] = (median(selfk), max(selfk), len(selfk)) if selfk else (None, None, 0)
            # each bot match against all humans
            r["bdemo"] = sorted((demo, ks_dist(vals, h))
                                for demo, vals in ddist["bots"][(sec, key)].items()
                                if len(vals) >= 3)
        rows.append(r)

    tested = [r for r in rows if not r["thin"] and not r["skip"]]
    for r, q in zip(tested, fdr_bh([r["p"] for r in tested])):
        r["q"] = q
    for r in rows:  # ignored metrics are printed but not tested, so they get no q
        r.setdefault("q", None)

    print(f"\n{'':36s} {'human p10/p50/p90 (n)':>26s}  {'bot p10/p50/p90 (n)':>26s}"
          f"   KS     p     q  in-rng spread score")
    cur = None
    for r in rows:
        if r["sec"] != cur:
            cur = r["sec"]
            print(f"[{cur}]")
        if r["thin"]:
            print(f"  {r['label']:34s} not enough data (humans {len(r['h'])}, bots {len(r['b'])})")
            continue
        f = r["fmt"].format
        hs = f"{f(pct(r['h'], .1))}/{f(pct(r['h'], .5))}/{f(pct(r['h'], .9))} ({len(r['h'])})"
        bs = f"{f(pct(r['b'], .1))}/{f(pct(r['b'], .5))}/{f(pct(r['b'], .9))} ({len(r['b'])})"
        qc = "    - " if r["q"] is None else f"{r['q']:5.3f}"
        print(f"  {r['label']:34s} {hs:>26s}  {bs:>26s}  {r['ks']:4.2f} {r['p']:5.3f}"
              f" {qc} {r['in']:4.0f}% {r['spread']:5.2f} {r['score']:4.0f}"
              f"{'  (ignored)' if r['skip'] else ''}")

    for g in ("humans", "bots"):
        msgs = [m for r in sess[g] for m in r.get("chat", ())]
        if msgs:
            lens = sorted(len(m[1]) for m in msgs)
            print(f"  chat {g}: {len(msgs)} msgs, dead {100 * sum(m[2] for m in msgs) / len(msgs):.0f}%, "
                  f"median len {lens[len(lens) // 2]}, lowercase "
                  f"{100 * sum(m[1] == m[1].lower() for m in msgs) / len(msgs):.0f}%")

    ranked = sorted(tested, key=lambda r: -r["ks"])
    print(f"\nTOP TELLS (largest KS first; * = survives FDR 5%)"
          + (f"  ignoring {' '.join(ignore)}" if ignore else ""))
    for i, r in enumerate(ranked[:top]):
        hm, bm = pct(r["h"], .5), pct(r["b"], .5)
        way = "HIGHER" if bm > hm else "LOWER" if bm < hm else "SPREAD"
        note = ""
        if r["spread"] == r["spread"] and r["spread"] < 0.5:
            note = f", bots too uniform (spread x{r['spread']:.2f})"
        elif r["spread"] == r["spread"] and r["spread"] > 2:
            note = f", bots too varied (spread x{r['spread']:.1f})"
        print(f"  {r['ks']:4.2f}{'*' if r['q'] < .05 else ' '} {r['sec']:8s} {r['label']:34s} "
              f"bots {way:6s} {r['fmt'].format(bm)} vs {r['fmt'].format(hm)}"
              f"  ({r['in']:.0f}% in human band{note})")
        if i < 12:  # detail lines for the worst of it only
            bits = []
            if r["ci"]:
                bits.append(f"KS 90% CI {r['ci'][0]:.2f}-{r['ci'][1]:.2f}")
            if r["ovl"] == r["ovl"]:
                bits.append(f"overlap {100 * r['ovl']:.0f}%")
            if r["rank"] == r["rank"]:
                bits.append(f"bot median = human p{r['rank']:.0f}")
            if r["hself"][2]:
                bits.append(f"human-vs-human KS {r['hself'][0]:.2f} (max {r['hself'][1]:.2f}"
                            f" over {r['hself'][2]} matches)")
            if len(r["bdemo"]) > 1:
                ks_d = [k for _d, k in r["bdemo"]]
                bits.append(f"per bot match {min(ks_d):.2f}-{max(ks_d):.2f}"
                            f" over {len(ks_d)} matches")
            if bits:
                print(f"        {'; '.join(bits)}")

    print("\nRESOLUTION (what this many sessions can actually see)")
    if tested:
        selfmed = [r["hself"][0] for r in tested if r["hself"][2]]
        widths = [(r["ci"][1] - r["ci"][0]) / 2 for r in tested if r["ci"]]
        ovls = sorted(r["ovl"] for r in tested if r["ovl"] == r["ovl"])
        sig_raw = sum(1 for r in tested if r["p"] < .05)
        sig_q = sum(1 for r in tested if r["q"] < .05)
        if selfmed:
            beyond = sum(1 for r in tested if r["hself"][1] and r["ks"] > r["hself"][1])
            print(f"  human-vs-human KS across matches: median {median(selfmed):.2f}, "
                  f"max {max(r['hself'][1] for r in tested if r['hself'][1]):.2f} "
                  f"({len(selfmed)}/{len(tested)} metrics have 2+ human matches)"
                  f" <- a tell below this is invisible in play")
            print(f"  significant: raw p<.05 {sig_raw}/{len(tested)}, after FDR {sig_q}/{len(tested)}"
                  f", beyond human match-to-match variation {beyond}/{len(tested)}")
        else:
            print(f"  significant: raw p<.05 {sig_raw}/{len(tested)}, after FDR {sig_q}/{len(tested)}"
                  f"  (need 2+ human matches for the match-to-match yardstick)")
        if widths:
            print(f"  KS bootstrap 90% half-width: median +/-{median(widths):.2f} "
                  f"({reps} resamples) <- sampling noise at these session counts")
        if ovls:
            print(f"  overlap (smoothed): median {median(ovls):.2f}, {sum(1 for o in ovls if o > .9)}"
                  f"/{len(ovls)} above 0.90 (same distribution to the eye)")
        multi = [r for r in tested if len(r["bdemo"]) > 1 and r["hself"][0]]
        if multi:
            every = sum(1 for r in multi if all(k >= r["hself"][0] for _d, k in r["bdemo"]))
            print(f"  consistent in every bot match: {every}/{len(multi)} metrics "
                  f"({len(multi)} have 2+ bot matches with >=3 sessions)")

    keys = [(r["sec"], r["key"]) for r in tested]
    auc, scored = detector(sess, keys)
    auc_cv, folds, cv = detector_cv(sess, keys)
    sec_scores = collections.defaultdict(list)
    for r in tested:
        sec_scores[r["sec"]].append(r["score"])
    print("\nSECTIONS")
    overall = 0
    for sec, scores in sec_scores.items():
        m = sum(scores) / len(scores)
        overall += m
        nsig = sum(1 for r in tested if r["sec"] == sec and r["p"] < .05)
        nq = sum(1 for r in tested if r["sec"] == sec and r["q"] < .05)
        sauc, _ = detector(sess, [k for k in keys if k[0] == sec])
        sa = f"AUC {sauc:.2f}" if sauc is not None else ""
        print(f"  {sec:10s} {m:5.0f}/100  {sa:8s}  ({len(scores)} metrics, {nsig} p<.05, {nq} q<.05)")
    overall /= max(len(sec_scores), 1)
    if tested:
        print(f"  {'OVERALL':10s} {overall:5.0f}/100")
        print(f"  indistinct {100 * (len(tested) - sig_q) / len(tested):5.0f}%    "
              f"({len(tested) - sig_q}/{len(tested)} metrics not different after FDR control)")
    else:
        # an empty metric set must never read as "0/100, nothing wrong"
        print(f"  {'OVERALL':10s} n/a    (no metric had 3+ sessions on both sides -- "
              f"not a result; longer matches or lower --min-minutes)")
    flagged, flagged_cv = {}, {}
    if auc is not None and tested:
        verdict = ("indistinguishable" if auc < .6 else "weak tells" if auc < .75
                   else "noticeable" if auc < .9 else "obvious bots")
        print(f"  detector   AUC {auc:.2f}   (0.50 = indistinguishable, 1.00 = trivially caught: {verdict})")
        if auc_cv is not None:
            print(f"             leave-one-MATCH-out AUC {auc_cv:.2f} over {folds} folds, "
                  f"human reference = {cv['human_kind']} (the honest number; the one above "
                  f"fits each KDE on the same match)")
        hsc = sorted(s for s, g, _ in scored if g == "humans")
        thr = hsc[int(0.9 * (len(hsc) - 1))]
        caught = sum(1 for s, g, _ in scored if g == "bots" and s > thr)
        nb = sum(1 for _s, g, _ in scored if g == "bots")
        flagged = {"fa": .10, "threshold": thr, "caught": caught, "bot_sessions": nb}
        print(f"             at 10% false alarms on humans it flags {caught}/{nb} bot sessions")
        if auc_cv is not None:
            hc = sorted(cv["humans"])
            bc = sum(1 for s in cv["bots"] if s > hc[int(0.9 * (len(hc) - 1))])
            flagged_cv = {"fa": .10, "caught": bc, "bot_sessions": len(cv["bots"]),
                          "folds": folds}
            print(f"             cross-validated it flags {bc}/{len(cv['bots'])} bot sessions "
                  f"(each match scored by a KDE that never saw it)")

    if show_sessions:
        print("\nPER SESSION (detector score > 0 looks like a bot; the per-metric column"
              " is comparable across metric counts)")
        by_name = {(g, r["name"]): r for g in ("humans", "bots") for r in sess[g]}
        nk = max(len(keys), 1)
        for s, g, name in sorted(scored, reverse=True):
            r = by_name[(g, name)]
            tells = []
            for row in ranked:
                x = r["v"].get((row["sec"], row["key"]))
                if x is None:
                    continue
                h = row["h"]
                q = (sum(v < x for v in h) + 0.5 * sum(v == x for v in h)) / len(h)
                ext = abs(q - 0.5) * 2
                if ext >= 0.9:
                    tells.append((ext * row["ks"], f"{row['label']}={row['fmt'].format(x)}"))
            tells.sort(reverse=True)
            print(f"  {s:+6.1f} ({s / nk:+.2f}/metric) {g[:-1]:5s} {name[:30]:30s} "
                  + "; ".join(t for _, t in tells[:3]))

    out = {}
    for r in rows:
        if r["thin"]:
            continue
        ci = r["ci"] or (None, None)
        bd = [k for _d, k in r["bdemo"]]
        out[r["name"]] = {"human": r["h"], "bots": r["b"], "ks": r["ks"], "p": r["p"],
                          "q": r["q"], "ignored": r["skip"],
                          "score": r["score"], "in_range": r["in"],
                          "spread": r["spread"], "ovl": r["ovl"],
                          "label": r["label"], "section": r["sec"],
                          "h_n": len(r["h"]), "h_p10": pct(r["h"], .1),
                          "h_p50": pct(r["h"], .5), "h_p90": pct(r["h"], .9),
                          "b_n": len(r["b"]), "b_p10": pct(r["b"], .1),
                          "b_p50": pct(r["b"], .5), "b_p90": pct(r["b"], .9),
                          "b_p50_rank": r["rank"], "ci_lo": ci[0], "ci_hi": ci[1],
                          "hself_med": r["hself"][0], "hself_max": r["hself"][1],
                          "hself_demos": r["hself"][2],
                          "bdemo_min": min(bd) if bd else None,
                          "bdemo_med": median(bd) if bd else None,
                          "bdemo_max": max(bd) if bd else None,
                          "bdemo_demos": len(bd)}

    sig = sum(1 for r in tested if r["p"] < .05)
    resolution = {"noise_floor": res_noise, "reps": reps, "tested": len(tested)}
    return {"overall": overall, "auc": auc, "auc_cv": auc_cv, "auc_cv_folds": folds,
            "resolution": resolution,
            "flagged": flagged, "flagged_cv": flagged_cv,
            "fdr": {"tested": len(tested), "raw_p05": sig, "q05": sum(1 for r in tested if r["q"] < .05)},
            "sections": {s: sum(v) / len(v) for s, v in sec_scores.items()},
            "metrics": out,
            "tells": [{"metric": r["name"], "label": r["label"], "ks": r["ks"], "p": r["p"],
                       "q": r["q"], "ovl": r["ovl"], "human_p50": pct(r["h"], .5),
                       "bot_p50": pct(r["b"], .5), "bot_p50_rank": r["rank"],
                       "hself_med": r["hself"][0]} for r in ranked],
            "sessions": [{"score": s, "per_metric": s / max(len(keys), 1), "group": g, "name": n}
                         for s, g, n in scored]}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--humans", nargs="+", required=True)
    ap.add_argument("--bots", nargs="+", required=True)
    ap.add_argument("--map", default="mp_backlot")
    ap.add_argument("--min-minutes", type=float, default=1.0)
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--sessions", action="store_true", help="per-session detector scores + worst tells")
    ap.add_argument("--ignore", nargs="*", default=["social.ping*"], metavar="GLOB",
                    help="leave metrics out of scores/detector (still printed); default ignores ping, "
                         "which is not play behaviour. '--ignore' alone scores everything")
    ap.add_argument("--json", default=None)
    ap.add_argument("--save", nargs="?", const="run", default=None, metavar="LABEL",
                    help="store this run under scores/LABEL.json for later diffing "
                         "(default label 'run'); see tools/scorecmp.py")
    ap.add_argument("--scores-dir", default=scorecmp.DEFAULT_DIR)
    ap.add_argument("--note", default=None,
                    help="store this text with the run (which build made the demos, "
                         "what the batch changed); not shown by --diff unless set")
    ap.add_argument("--diff", action="store_true",
                    help="after scoring, print the delta against the previous stored run")
    ap.add_argument("--reps", type=int, default=300, metavar="N",
                    help="bootstrap resamples for the KS confidence intervals (default 300, 0 = off)")
    ap.add_argument("--html", default=None, metavar="FILE",
                    help="write a self-contained HTML report: every metric as a human/bot "
                         "distribution overlay with KS, CI, overlap and per-match spread")
    args = ap.parse_args(argv)

    sess = {"humans": [], "bots": []}
    for grp, bases in (("humans", args.humans), ("bots", args.bots)):
        for base in bases:
            print(f"[{base}] loading...", file=sys.stderr, flush=True)
            got = load_demo(base, args.map, grp, args.min_minutes)
            print(f"[{base}] {len(got)} {grp[:-1]} sessions", file=sys.stderr, flush=True)
            sess[grp].extend(got)
    if not sess["humans"] or not sess["bots"]:
        print("need at least one human and one bot session on this map")
        return 1
    ncells, nhome = apply_priors(sess)

    nh, nb = len(sess["humans"]), len(sess["bots"])
    mh = sum(r["minutes"] for r in sess["humans"])
    mb = sum(r["minutes"] for r in sess["bots"])
    print(f"map {args.map}: humans {nh} sessions, {mh:.0f} alive player-min | "
          f"bots {nb} sessions, {mb:.0f} alive player-min")
    print(f"human gaze prior: {ncells} cells | home turf: {nhome} cells cover 50% of human time")
    noise = 1.36 * math.sqrt((nh + nb) / (nh * nb))
    print(f"KS noise floor at these sample sizes: ~{noise:.2f} (p=.05)")
    res = score(sess, args.top, args.sessions, args.ignore, reps=max(args.reps, 0))
    res["map"] = args.map
    res["source"] = "demo snapshots"
    res["noise_floor"] = noise
    res["bootstrap_reps"] = args.reps
    res["sample"] = {"human_sessions": nh, "bot_sessions": nb,
                     "human_player_min": round(mh, 1), "bot_player_min": round(mb, 1)}
    print("NOT covered (no demo signal): hit accuracy, hit locations, reloads, pain reactions "
          "(need games_mp.log / entity events).")
    if args.json:
        with open(args.json, "w") as f:
            json.dump(res, f, indent=1)
        print(f"wrote {args.json}")
    if args.html:
        import report_html
        report_html.write_report(args.html, res)
        print(f"wrote {args.html}")

    if args.save or args.diff:
        rec = scorecmp.run_record(
            res, {"humans": args.humans, "bots": args.bots, "min_minutes": args.min_minutes,
                  "ignore": args.ignore, "note": args.note,
                  "argv": " ".join(argv or sys.argv[1:])},
            label=args.save or "run")
        path = scorecmp.next_run_path(rec, args.scores_dir)
        prev = [p for p in scorecmp.list_runs(args.scores_dir) if p != path]
        if args.save:
            print(f"saved run -> {scorecmp.save_run(rec, args.scores_dir, path)}")
        if args.diff:
            if not prev:
                print(f"no previous run in {args.scores_dir}/ -- nothing to diff against",
                      file=sys.stderr)
            else:
                scorecmp.diff(scorecmp.load_run(prev[-1]), rec)
                if args.html:
                    import report_html
                    report_html.write_report(args.html, res,
                                             prev_run=scorecmp.load_run(prev[-1]))
                    print(f"wrote {args.html} (with delta vs {prev[-1]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
