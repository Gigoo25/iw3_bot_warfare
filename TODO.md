# IW3 Bot Warfare — Human-Indistinguishable Bots

Goal: join a lobby and not be able to tell the bots from players, especially
in killcams, spectating, and the scoreboard.

## Validation

### The loop that needs nobody in the server
- `tools/botmatch.sh [minutes] [label] [map] [gametype]` — build, check, restart the
  container, let 12 bots play on their own, then score the match and diff it against
  the previous run. Nobody joins, no demo is recorded. ~1 min of overhead plus the
  match length.
  How it works: the container fills itself with 12 bots (`server/server.cfg`), the mod's
  `telemetryWatch()` logs a 5 Hz `BT;` line per player, and `bots_telemetry_out 1` sends
  those to the server *console* — CoD4X throttles `games_mp.log` to ~5 lines a minute,
  which is why the telemetry in the old logs is useless. `docker compose logs
  --timestamps` is the dense channel; `tools/btlog.py` parses it.
- **Repeat it, don't judge one match.** `POOL=<dir> POOL_MAX=8 tools/botmatch.sh 15 label`
  pools every capture in `<dir>` and scores the pool, so the KS noise floor falls as
  1/sqrt(n): at `--min-minutes 0.5` a 15 min match yields ~25 sessions (floor ~0.40)
  where 1 min sessions yield ~13 (floor ~0.59). Same tells, twice the power. The two
  `--min-minutes` settings are NOT comparable; each run records which was used.
- **Tuning knobs without rebuilds**: `DVARS="set bots_glance_wander 1; set bots_idle_turn_slow 1.5"`.
  Semicolon-separated rcon commands, applied before the map loads and echoed into the
  run note. That is how gaze/wander/cadence variants get compared inside one build.
- Things that break a run, all handled now: the shipped map rotation walks the server
  off mp_backlot mid-match (botmatch pins it to the one map being measured), an
  in-place `docker compose restart` leaves the server wedged with rcon dead (use
  down/up), and editing a running bash script corrupts it (botmatch execs a copy).
- Human source and demo-only metrics:
  `tools/btlog.py` scores that telemetry against a human baseline using the same scorer
  as the demo path (`awarescore.score()`), so FDR, bootstrap CIs, overlap, the
  match-to-match yardstick, the detector, the HTML report and the run history all work
  the same way: `tools/btlog.py --humans <src> --bots <src> --save LABEL --diff --html out.html`
- **Human source**: `--humans output/demos/demo0000` (a demo CSV works: position, pitch,
  yaw, weapon and stance per snapshot, decimated to the same 5 Hz so the sources are
  comparable). A human *telemetry* log would also work and covers the metrics a demo
  cannot see (ADS, look target, look source, trace depth), but the existing
  `output/human*.log` files only contain ~1 s bursts, so those metrics stay uncovered
  until someone plays one match on a server with `bots_telemetry 1` + `bots_telemetry_out 2`.
- What telemetry cannot see either way: kills, deaths, fire events, reaction time, hits.
  Those need the demo stream: extract (`tools/demo/extract.sh`, needs docker), then
  `tools/awarescore.py --humans <demo...> --bots <demo...> --map mp_backlot`.
  Recording a *bot-only* demo produces no snapshots at all (bots are not network
  clients), so the demo path still needs one human in the server.

### Reading the numbers
- **Measure both sides the same way.** Speed now comes from POSITIONS, not from the
  engine's reported velocity, because the human side can only be measured from
  positions. Mixing the two manufactured the single biggest "tell" in the telemetry
  report (bots 2.1 u/s per sample vs humans 12.8); like-for-like it is 9.8 vs 12.8.
  Watch for this class of bug: the human and bot sides must go through the same
  definition or the number means nothing.
- Every metric reports KS, p, **q** (BH q-value — with ~110 metrics, raw p<.05 flags
  ~5 by chance), a **bootstrap 90% CI** on KS, **overlap** (KS saturates at 1.00 on one
  tail value; overlap shows how much is actually shared), where the **bot median sits
  in the human distribution** (p50/p90), the **human-vs-human KS across matches**
  (match-to-match variation is the yardstick: a tell below it is invisible in play) and
  **each bot match's KS on its own** (a tell that holds in one match only is not a tell).
- Two AUCs: leave-one-session-out (as fitted) and leave-one-match-out, because sessions
  of one match share one human's habits and the optimistic number flatters results
  exactly in the 0.7-0.95 range where tuning decisions get made. The match-held-out
  number needs 2+ bot matches in the run, so a single match reports none.
- When two runs score different metric sets, `scorecmp diff` prints an
  "overall, common metrics" row: plain OVERALL averages over different populations and
  is not comparable, the intersection is.
- `--html out.html` writes a self-contained report: every metric as a human/bot
  distribution overlay with all of the above, sortable, plus the per-session scatter
  and the 10% false-alarm threshold.

### What the unattended loop said BEFORE the mode fix (superseded)
> These numbers predate the gametype fix: the matches were not reliably
> S&D, so treat them as a record of what was tried, not as evidence.
- Shipped build (`223d684`), pooled unattended matches, `--min-minutes 0.5 --settle 5`:

  | pool | bot sessions | OVERALL | AUC | tells after FDR |
  |---|---|---|---|---|
  | 2 matches | 78 | 60 | 0.93 | 11/33 |
  | 3 matches | 145 | 59 | 0.91 | 14/33 |
  | 4 matches | 209 | 58 | 0.92 | 17/33 |

  OVERALL and AUC are stable; **the tell count rises with n** (11 -> 17) because more
  sessions resolve smaller differences. That is the point of the tool, but it means
  "number of tells" is only comparable between runs of the same size — compare arms
  with pooled, equally sized matches, and read the per-metric q-values rather than the
  count.
- Worst remaining tells: `yaw rate p99` 540 vs humans 410 deg/s, `yaw rate p90` 155 vs
  120, `p90 yaw snap` 570 vs 450, `speed p99` 284 vs 320. So the bots' *fastest* view
  changes are ~20% quicker than any human's, while the mid-range turn rate matches.
- **Four changes were tried; all four measured worse** (same build, dvars only,
  2 pooled matches per arm, same human baseline, uniform scoring):

  | arm | OVERALL | AUC | tells |
  |---|---|---|---|
  | shipped defaults | **60** | 0.93 | **11** |
  | idle glance dwell 800-2400 ms (was 1200-3500) | 54 | 0.99 | 20 |
  | gaze wander (bounded drift inside the look point) | 59 | 0.89 | 13 |
  | gaze wander, before an accumulation bug was fixed | 59 | 0.90 | 14 |
  | idle/casual turn slowdown 1.5 (`bots_idle_turn_slow`) | 54 | 0.99 | 19 |

  The cadence and turn-slowdown arms add ~9 tells and push the detector AUC to ~0.99:
  humans *do* move their view fast, so making the bots slower is more obvious, not
  less. An early single-match comparison also suggested the bots' view was "too smooth"
  (turn jitter 5 vs humans 10 deg/s) — that difference disappeared under pooled scoring,
  and the change aimed at it did not survive either.
- The knobs stay (`bots_glance_dwell_lo/hi`, `bots_glance_wander`, `bots_idle_turn_slow`,
  `bots_max_turn_rate`) with the shipped values as defaults, so any of these can be
  re-tested cheaply. Do not retune them without pooled evidence.
- Lesson worth keeping: **one 15 min match cannot decide this.** A single match scored
  53/0.99 where its own build pooled over three matches scored 59/0.91 — match-to-match
  variance alone is worth ~6 OVERALL points and 0.06 AUC. Two pooled matches per arm is
  the smallest unit that separated the arms above.

- **Top open item, first measured tonight: the bots barely shoot.** The telemetry now
  carries `since_fire` (ms since that player's own last shot) and the human side derives
  the same number from the demo's eflags fire bit, so both sides are defined identically.
  In the unattended S&D match: **0.2% of bot samples are within 1s of a shot against
  7.8% for humans**, KS 0.66, and every bot session sits below the human minimum. Humans
  in a 25-player lobby simply shoot far more. Whether that is bot behaviour or lobby
  composition cannot be settled from one match type per side -- a human S&D match on the
  same server, recorded once, would separate them, and that recording is the most
  valuable single piece of data still missing. (`tools/btlog.py --engaged 1` restricts
  every metric to recently-firing samples; off by default, because only ~1% of bot
  samples qualify -- too thin for stable per-session metrics.)

### What the unattended loop says — VERIFIED runs (sd = S&D, mp_backlot, mode checked)
- **Read the gametype before trusting any comparison.** `set g_gametype` over rcon is
  ignored by this engine ("will be changed upon restarting"), so matches ran in whatever
  mode the server was left in -- mostly `war`. Two pools of the *same build* differed by
  2x on turn metrics, split by time rather than by configuration. `botmatch.sh` now
  passes the mode and map into the container command and refuses to score unless
  `gametype sd, map mp_backlot` is confirmed. Every number below is from verified runs.
- Reference (2 pooled matches, 92 bot sessions, 13 human sessions from demo0000):
  **OVERALL 46.6/100, AUC 1.00, 22/37 tells after FDR**.
- `bots_max_turn_rate 450` (peak view-rate cap, `PVars`/rcon, default off): 2 pooled
  matches, 105 bot sessions. **OVERALL 49.4, and two tells resolved:**
  `turn.rate_p99` (bot median 775 -> 415 deg/s against humans' 410, 0% -> 99% in the
  human band, q 3e-11 -> 0.20) and `path.zigzag_p90`; `turn.snap_pct`, `turn.rate_p90`
  and `turn.pitch_rate_p90` all improved. Everything that moved the other way
  (`fire.gap_p50`, `ads_while_moving_pct`, `still_but_turning_pct`, `speed.sprint_pct`)
  moved *below* the noise floor of 0.40. Probable win, not conclusive: two matches per
  arm. Adopting it is one default flip; re-verify with more matches before relying on it.
- **Where the remaining separability lives** (`--ignore` is the quickest way to see it):
  AUC 0.99 with everything, 0.99 without the fire metrics, **0.81 without fire and turn**.
  So the bots are caught by two families, in this order:
  1. **they barely shoot** -- 0.0% of samples within 1s of a shot vs humans 7.8%, every
     bot session below every human session (KS 0.75, bot spread 0.05: they are
     *uniformly* silent). Humans in a lobby shoot; the bots hold fire.
  2. **they turn their view about twice as fast as humans in normal play** -- with the
     peak capped, `turn.rate_p90` is still 225 deg/s against humans' 120, and
     `turn.snap_pct` 13.3% against ~2-3%. The cap clipped the tail; the mid-range rate is
     still robotic. The next lever is the acquisition slowdown (`ticks * 1.8` in
     `aimControllerStep`) and/or the pursuit gain, measured the same way.

### Earlier arms that are NOT evidence (wrong mode, kept for the record)
| arm | OVERALL | AUC | tells | why it cannot be trusted |
|---|---|---|---|---|
| shipped defaults | 60 | 0.93 | 11/33 | gametype not verified (likely war) |
| idle glance dwell 800-2400 | 54 | 0.99 | 20/33 | idem |
| gaze wander (fixed / before a bug fix) | 59 | 0.89 | 13-14/33 | idem |
| idle/casual turn slowdown 1.5 | 54 | 0.99 | 19/33 | idem |
| peak-rate cap 450 | 54 | 0.99 | 16/33 | idem -- **re-tested and confirmed above** |
All of these ran before the mode was pinned, so they are inconclusive rather than
refuted; the knobs are still in place (`bots_glance_dwell_lo/hi`, `bots_glance_wander`,
`bots_idle_turn_slow`, `bots_max_turn_rate`) with the shipped values as defaults.

### Tuning knobs (all defaults are the adopted values; nothing needs a rebuild)
| dvar | default | what it does | evidence |
|---|---|---|---|
| `bots_max_turn_rate` | **450** | caps how far the view may move per 0.05s tick | **adopted**: resolved `turn.rate_p99` (775 -> 415 deg/s vs humans 410, 0% -> 99% in band) and `turn.snap_p90` over 2+2 verified matches |
| `bots_acq_slow` | **2.2** | how long an acquisition flick takes (was hardcoded 1.8) | **adopted**: 3 pooled matches vs a 2-match reference -- OVERALL 47.6 -> 48.9, indistinct 43% -> 46%, 1 tell resolved (`speed.sprint_pct`), none added, and a bootstrap on the difference put 4 movements on the right side of zero against 2 on the wrong |
| `bots_pursuit_gain` | 1.0 | multiplier on the smooth-pursuit gain | **worse** at 0.85: nothing resolved, 3 new (`speed.still_pct`, `speed.accel_p90`, a thin one), indistinct 43% -> 30%. Slowing the view turns fast turns into stillness |
| `bots_steady_look` | 0 | a failed glance falls back to the path look instead of a "useful" sweep | **no effect**: churn 28.0% -> 28.8%, OVERALL 47 |
| `bots_look_hold` | 0 | the gaze hold and the "useful" hold share one timer | **mixed**: +0.8 OVERALL but indistinct 43% -> 41% and both ADS tells got worse; churn only 28.0% -> 26.6% |
| `bots_glance_dwell_lo/hi` | 1200/3500 | idle glance dwell (ms) | 800-2400 measured worse (wrong mode, re-test before trusting) |
| `bots_glance_wander` | 0 | slow gaze drift inside the look point | measured worse; off |
| `bots_idle_turn_slow` | 1.0 | slows idle/casual turns | measured worse; off |
| `bots_telemetry_out` | 0 | 1 = console (unthrottled, what the loop reads), 2 = both | the loop sets it |
| `bots_settle` / `--settle` | 5 | seconds dropped at session start | spawn transient |

`tools/tune.sh <label> <matches> "<dvars>" [reference]` runs a whole experiment the way
the evidence requires: N verified matches into a pool, score the pool, diff against a
reference pool, and print the resolved/new tells. A single match swings OVERALL by ~5 and
the AUC by ~0.06 on nothing, so nothing should ever be adopted from one arm.

### Why the bots barely shoot -- answered (bot-side diagnostics, verified S&D)
Three fields were added to the telemetry for this (`since_fire`, `acq_ms` = ms since
the current target was acquired, and a shot counter; the human side derives `since_fire`
from the demo's eflags fire bit so the definition matches). One verified match, 51 bot
sessions:

| diagnostic | median | p90 |
|---|---|---|
| samples with a target (%) | **2.25** | 12.2 |
| own shots per minute WITH a target | 11.5 | 112 |
| own shots per minute alive | 1.4 | 5.5 |
| acquire -> first shot (s) | 0.50 | 1.20 |

So the trigger is *not* the problem: when a bot has a target it shoots 11.5 times a
minute and pulls the trigger within half a second of acquiring. The bots almost never
have a target -- 2.25% of samples against humans' implied >=7.8% (the share of their
samples that follow a shot). The candidates are the acquisition gates in `target()`:
a bone-trace line-of-sight requirement (`j_head`, `j_ankle_le/ri`), the smoke check,
the `no_trace_time` memory, and the switch hysteresis (`newDanger < oldDanger + 3`).
FOV is not obviously narrow (0.45-0.55 cone, widened by `periph_bonus` for moving or
firing players). **This cannot be settled without the matched human recording**: humans
are in a 25-player scrum and the bots hold angles on a cover-heavy map, so part of the
gap is lobby composition. The diagnostic is printed by `tools/btlog.py` on every run.

### Why the bots' view is too active (mechanism found, verified S&D)
The reference run's turn tells are `turn.rate_p50` 35 vs humans 5 deg/s, `turn.jitter` 60 vs
10, `turn.rate_p90` 230 vs 125 -- not the tail, the whole distribution. The look-source
mix (telemetry only) says why:

| look source | share of samples | median yaw rate |
|---|---|---|
| useful | 37% | 45 deg/s |
| gaze | 35% | 60 deg/s |
| path | 15% | 15 deg/s |
| scriptaim | 9% | 0 |
| **target** | **0.7%** | 0 |

and **the bot changes what it is looking at every 0.7 s** (28% of samples). Humans pick
a look target and hold it for seconds; these bots alternate `gaze`/`useful` several times
a second and every switch is a 45-60 deg/s move, which is exactly a "always fidgeting"
signature. Two consequences worth separating: the churn (fixable with
`bots_glance_dwell_lo/hi`, being tested at 2500-7000ms) and the `target` share at 0.7%,
which is the same problem as the firing rate -- they rarely have anyone to look at.
Neither the acquisition slowdown (2.2) nor the pursuit gain (0.85) changed `rate_p50`
or `jitter` at all, which is consistent: both act on tracking, not on look-target churn.

### How much of a verdict is the match, not the code?
Two pools in `scores/` are the **same configuration** (peak cap 450, acquisition 2.2) scored on
different match samples: `acq22` (3 matches, 114 bot sessions) and `adopted` (3 matches,
136 sessions). They disagree by one tell (`speed.sprint_pct` is a tell in one and not in
the other) and by 5 points of "indistinct". Same code, same map, same mode, same human
baseline -- only the bots' matches differ. So:

- a 1-3 tell difference between arms means nothing;
- "indistinct %" and the tell count move with sample size (more sessions resolve smaller
  differences), so only compare arms with equal pooled match counts;
- what survives is the OVERALL delta (consistent: +1.2 for the acquisition change across
  both comparisons) and the bootstrapped difference, where 6 of 13 movements had a 95%
  interval that excluded zero.

Every arm verdict in this file is quoted in those terms. `tools/tune.sh` writes
`scores/<label>-verdict.json` with the headline numbers so a decision can be re-read
later without re-running it.

### Where this stands (verified S&D, all numbers from pooled unattended matches)
- Current adopted baseline (peak cap 450, acquisition 2.2): **OVERALL 48.9/100, AUC 0.99,
  22/37 tells after FDR**, 3 matches / 136 bot sessions / 257 minutes, KS noise floor
  0.39. The previous verified reference was 47.6/21 tells at 2 matches -- so the
  session's tuning bought about +1.2 OVERALL, one tell resolved and none added. Honest
  accounting: small. The measurement harness and the diagnostics were the big wins.
- Diffing the reference against the adopted build with the bootstrap on the *difference*
  leaves one real movement (`fire.shots_per_min`, a thin metric) and five inside the
  noise, i.e. the OVERALL gain is real but small and the per-metric story is thin. Read
  `scores/*-verdict.json` (written by `tools/tune.sh`) before re-litigating any of this.
- Still open, in order of how much they would buy:
  1. **the bots rarely have a target** (1.7% of samples against humans' >=7.8%), which is
     why they barely shoot. Candidates are in `target()`: the bone-trace line-of-sight
     requirement, the smoke test, `no_trace_time`, and the switch hysteresis.
  2. **the human baseline is one 25-player lobby** compared against a 12-bot S&D match.
     A single human S&D recording would re-base every number here; until then, treat
     engagement-dependent metrics (firing, ADS, look target) as confounded.
  3. **look-target churn**: 67% of look-source changes are a `useful <-> gaze` switch,
     one every 0.7 s at 45-60 deg/s. Three interventions failed to stop it (dwell, path
     fallback, shared timer), so the cause is elsewhere -- most likely that each branch
     re-picks a *new* point on expiry rather than holding its current one.

### Run history
- **Run history** (`scores/`, committed): `--save LABEL` stores a trimmed run
  (percentiles + KS per metric, sources, filters, sample sizes, scored-with commit);
  `--diff` prints the metric-level delta against the previous run — new tells,
  resolved tells, better/worse, with deltas below the KS noise floor marked so
  sampling noise is not mistaken for progress. Standalone: `tools/scorecmp.py ls|diff|show`.
  Always pass `--note "which build made these demos"` — the commit stored in a run is
  the tree that *scored* them, not the tree that built the bots. Diffs are only valid
  against the same human baseline and the same source (the tool warns when either changed).
  Baselines: `*-handoff-baseline` (demo source, ours_1..4, pre-humanize) and
  `*-unattended-baseline` (telemetry source, current build).
- `tools/check.sh` runs the gsc parse + lint + the fast tool tests; `--full` adds the
  slow synthetic end-to-end suites, `--no-tests` skips them.
  Tooling tests: `tools/test_awarescore.py` (16, synthetic demos end-to-end),
  `tools/test_btlog.py` (18, telemetry + demo-CSV sources), `tools/test_scorecmp.py` (24, run history).
- `tools/sim/aim_sim.py` — Python mirror of the aim controller (`bot_lookat` /
  `aimControllerStep`). Prints per-skill acquire time, peak turn speed, overshoot rate,
  strafe-tracking accuracy, spray climb. `--trace out.csv` dumps angle traces for plotting.
  Keep it in sync with the GSC when tuning.
- Live: containerized CoD4x server in `server/` (see `server/docker-compose.yml` header).
  Game data in the `cod4-game` volume (steamcmd service), mod mounted from `output/`,
  waypoints from `scriptdata/`. `./build.sh && (cd server && docker compose restart cod4x)`.
  `tools/rcon.py status|map|set ...` (password botdev123). Match log with every hit:
  `docker compose exec -T cod4x cat /cod4home/mods/mp_bots/games_mp.log`
  (`D;`/`K;` lines: weapon, damage, MOD, hit location).

## P0 — Bugs in the uncommitted humanization pass
- [x] Aim motor model: `bot_lookat` is now a one-tick step of a persistent controller
      (`aimControllerStep`): Fitts'-law min-jerk flicks, up to 2 corrective submovements,
      exponential pursuit (gain from `aim_time`, capped 0.4), lead from lagged perceived
      velocity x per-bot `lead_frac`. Sim: skill 1→7 acquire p50 0.95→0.35s, peak
      245→500 deg/s, strafe on-target 21→92%.
- [x] Per-tick jitter → Ornstein-Uhlenbeck drift (std dev = `aim_jitter` deg, x1.5 moving).
- [x] Turn-rate caps removed; speed now emerges from Fitts' law.
- [x] Recoil: `burst_count` path removed; controller climbs on full-auto with skill-scaled
      pull-down (`bots_aim_recoil`). (live) If engine kick already applies to bots
      (`setplayerangles` may not clear it), set `bots_aim_recoil 0`.
- [x] Confirm gate now applies to acquiring new targets, not the current one.
- [x] Reaction floor 80ms → 180ms (150ms when target appears inside the held cone).
- [x] `targetObjUpdateNoTrace` no longer extrapolates through walls.
- [x] `updateBones` picks from configured list; long-range head picks drift to chest.
- [x] Cautious entry: ADS-walk the last 400u into 40% of danger nodes (never rushers),
      replacing the 10Hz moveto stutter.
- [x] `difficulty()`: humanization values never applied (added() pre-set `aim_jitter`, so the
      `!isdefined` gate never passed). Now follow skill base each loop. Persona nudges no
      longer compound every 5s on `bots_skill 9`.
- [ ] (live) Tune from killcams: flick feel, drift visibility, corrective-step visibility,
      idle look speed (casual flicks are 1.5x slower, gain x0.6).
- [ ] Waypoint pre-aim re-enabled (was `&& false` upstream). Waypoint angles are camp
      facings; verify or restrict to camp/danger nodes. (live)
- [ ] Turn-arc blend in `doBotMovement_loop` may cut corners off ledges/doorways. (live)
- [x] `removeAStar` back to tail-pop with guard.

## Live findings
- [x] 2026-09-26 first boot: mod compiles/loads on CoD4x 21.2, 224 waypoints on mp_crash,
      bots join and fight, no script runtime errors in the first match.
- Human baseline: stats.sexycod4.de (UltraStats, ~2.2M human kills): HS 10.2% of kills
  (12.1% of bullet kills), grenade ~6.5%, knife ~1.2%. Weapons: M4/M16 (reflex/silencer),
  G3, RPD, P90 silenced, M21/Dragunov, Deagle; silencers popular. Forum meta agrees
  (M16/AK47/M4/P90/MP5/AK74u; Stopping Power, UAV Jammer, Jugg, Bandolier, Deep Impact).
- [x] `tools/matchstats.py` (combat vs baseline), `tools/movestats.py` (movement from
      `bots_telemetry` BT;/BE; lines, bots vs humans side by side).
- [x] Bone lists: head 0%→14% by skill (was up to 100% at skill 7), ankles only skill 1-2.
      HS kills 35% → 15-18%. Legs 21% → 7%.
- [x] Meta-weighted loadouts (`bots_loadout_meta`), persona-tilted; favorite class 65%.
- [x] Spawn nades toward recent fight spots (`level.bot_fights`, now in _bot_utility).
- [x] Random crouch only on cautious approaches (crouch 23% → 2-5%).
- [x] Idle glance system (`getIdleGlance`): lanes/fight spots/behind. Strafe 7% → 13-15%.
- [x] Killstreaks: CoD4x bots can't select hardpoint items (switchtoweapon fails, botaction
      has no actionslot) — was freezing bots ~5s every few seconds (still 45%). Now backs
      off 30s and never stops moving for it. Still 45% → 20%.
- [x] Killstreaks still unusable by bots → no enemy UAV/air support from bots, a tell. Try
      calling the stock hardpoint trigger directly (maps\mp\gametypes\_hardpoints).
- [x] HS still 15-19% vs 10-12% (superseded, see below): per-skill breakdown needed; maybe aim drift biases up.
- [x] Knife kills 4-5% vs 1.2%: knife range/chance too generous.
- [x] Grenade kills swing 0-8% per match; spawn nades mostly fail the open-sky check on
      mp_crash (roofs) — use waypoint-graph lob points or relax to partial sky.
- [ ] Movement vs guesses: slow 40% / stop-go 24/min high, ADS-moving ~2% low, view-turn
      median 8 deg/s low. NEED a human baseline: play one match with bots_telemetry 1.
- [x] Killstreaks: bots call `_hardpoints::triggerHardpoint` directly (switch can't select
      them on CoD4x); 16 min test: 39 UAVs, 11 airstrikes.
- [x] Knife only when reloading/empty or per-engagement knife preference (30%, rusher 55%).
- [x] Spawn nades: clear-arc check instead of open sky (10 thrown / 16 min; 62 no-arc).
- [x] Glances narrower (35-80deg) and shorter while running; "dawdling" metric 5.9%.
- [x] Cautious ADS-walk also near recent fight spots (`bot_pick_fight_spot_near`).
- [x] Names: `tools/gen_botnames.py` -> 320 fictional handles styled on live CoD4x lobbies
      (regional nicknames, shared clan tags, .:x:., number suffixes, ^colors).
- [x] Chat: `bots_chat_human` — no intent narration; data-driven lines from
      `scriptdata/botchat.txt` (`tools/gen_botchat.py`, styled on the C4S public chatlog):
      per-bot language (en/es/pt/it/de/pl), typing delay, repeat-killer complaints,
      replies to hi/gg/lol/hack/"bots?" (evasive, never claims to be human), command typos.
- [ ] (live, needs human) verify replies fire via level "say" notify; tune rates.
- [x] Headshots rose to 21% (393 kills): full-auto 23% vs M16 burst 16%. A/B confirmed the
      recoil sim: off -> 13.7%, then 12.4% (378 kills). `bots_aim_recoil` now defaults 0.
      (live) if killcams show laser-beam sprays, engine kick isn't applied: re-enable + retune.
- [x] Fight-driven roaming (`pickRoamGoal`): persona-weighted approach to recent fight spots,
      stopping short. Idle gap between fights 10.4s -> 7.1s. Chat verified live (42 lines/14 min,
      name cleaning works). Knife 1.1%, grenades 3.4%.
- [x] Near-fight caution overshot (slow 49%, crouch 12%, sprint 13%): toned down -> crouch 7.6%,
      sprint 15%, dawdling 5.3%; headshots 10.5% (humans 10.2%).
- [x] Lobby lifecycle (`bots_lobby_human`): trickle joins (one per 4-20s), fill target drifts
      -2..+1 every 3-6 min, ~45 min sessions (leave after a death, "gtg"/"gn"), rage quits
      after 5+ deaths without a kill, ~15% leave at map change.
- [x] Persistent identity: CoD4x drops bots on map change and the lobby came back as 12 new
      names every map. Now name/persona/skill/lang/lead habit are carried in
      `bots_lobby_carry` and the same bots reconnect quickly next map.
- [ ] (live) verify carry-over across a map change + how kick "EXE_DISCONNECTED" reads to players.
- [ ] Compare several matches per change (single-match variance is large: one RPD bot
      took 48% of kills in one run).

## Human baselines (targets for per-mode profiles)
- TDM, you on the dev server (7 min, telemetry): sprint 36%, crouch 0.1%, still 17%, ADS-moving 2.6%,
  stop-go 34.5/min, jumps 2.8/min, pitch 4.7 deg down (sd 5.7), view-turn median 10 deg/s.
- S&D, 24 NamelessNoobs players (demo0000: ~22 min Backlot + 3 min Overgrown, 226 player-min, full
  decode): still 33.7%, sprint 20.0%, crouch 22.5%, prone 4.7%, ADS-moving 4.7%, stop-go 39/min,
  jumps 6.5/min, strafing 12%, look=move 43%, pitch 3.4 deg down (sd 11.3), view-turn median 6.6 deg/s.
  Chat: 180 msgs/25 min, median 10 chars, 79% lowercase, 84% from DEAD players.
- S&D, demo0001: 25 players, 350 player-min (Crossfire ~19 min + Bog ~15 min): still 38.5%, sprint 19.3%,
  crouch 19.3%, prone 6.6%, ADS-moving 6.6%, jumps 4.8/min, stop-go 36.5/min. Combined S&D (576 player-min,
  Backlot/Crossfire/Bog): still 36.6, sprint 19.6, crouch 20.6, prone 5.9, ADS-moving 5.9, jumps 5.5, stop-go 37.6.
- S&D bots (ours, Backlot, 2026-09-26): still 21.3, crouch 5.1, prone 0.4, ADS-moving 1.7, stop-go 19.7, jumps 3.0,
  sprint 18.1; score/min median 20 vs human 3.1; rounds 44-160s; killstreak kills 8.5%.
- TDM, demo0002 (Crossfire, mixed lobby: 8 [BOT]s filtered by 0-ping + name): 11 humans, 122 player-min:
  still 51.8, crouch 41.9, prone 5.4, sprint 14.2, stop-go 35, ADS-moving 5.2, view-turn 5.0, pitch 3.4.
  Campy lobby; TDM varies a lot by lobby/map -> need more TDM demos. Their bots: still 10.7, stop-go 15,
  view-turn 15.8, pitch 0.8 (same tells ours had).
- Archetypes (48 S&D sessions, k=3): mobile 42% / careful rifleman 52% / camper-prone 6%.
- [ ] demostats chat: filter bot + server announcement lines (TDM demo chat is mostly scripts).
- S&D grenades (NN demos): hand grenades 16.7-18.5/min lobby-wide (~1 per player per round), 69-79% thrown
  in the first 20s of a round (median 10-12s in), frags vs flash/stun/smoke ~50/50; claymore/C4 ~2/min,
  tubes/RPG ~1.5/min. -> `bot_sd_round_nades` (75% frag toward enemy spawn side, 45% + tactical). `tools/nadestats.py`.
- Human ADS (NN demos): 36% of time, ~6.7 ADS/min, median 1.55s, 60% start while moving, 43% end in firing.
  Quick look-arounds ~3.7/min. Direction reversals 0.9/min (ours 2.2 -> 24u movement dead zone).
- S&D score/min (GameTracker, NN S&D regulars): p10 2.0, median 3.1, p90 4.6.
- Tools: `tools/demo/extract.sh <demo.dm_1>` (Docker; reference parser Iswenzz/CoD4-DM1 pinned +
  8-line patch + export.cpp; 99.8% of snapshots decode) -> `tools/demostats.py`.
  (The TS port cod4-dm1-tools only decoded 14%: a rare field misread cascades through delta chains.)
- [ ] Per-mode profiles: respawn modes (TDM/DM/DOM/HQ) vs one-life (S&D, SAB?) vs hardcore; loadout
      mix per mode; S&D: slow/crouch/hold angles, round-start nades, dead-only chat.
- [ ] More demos (other maps/modes) to firm up baselines.
- [ ] Per-player style archetypes from demo data (cluster sprint/crouch/still/ADS/jump per player).

## Data-driven systems (2026-09-27)
- [x] Weapon bug: CoD4x 21.2 predates the Nov 2023 bot switchtoweapon fix; `botweapon()` (adapter
      builtin) now accompanies every switch + every weapon_change. Empty-handed 19-28% -> 0.8%.
- [x] Stutter: 24u movement dead zone (was 7u) + weapon fix. 6 episodes/bot-min -> 0.3.
- [x] Movement state machine from demos (`tools/gen_motor_model.py` -> `_bot_motor_data.gsc`,
      `motorController`), stops only near cover, context bias (threat: ADS/crouch; calm: sprint).
- [x] Per-map position model (`tools/gen_map_model.py` -> `_bot_map_data.gsc`, `botMapGoal`): S&D by
      side (spawn clusters) and round phase; freeze + spawn areas excluded.
- [x] Human navigation graphs (`tools/gen_human_nav.py` -> `scriptdata/waypoints_human/`,
      `bots_nav_human`): Backlot 692 nodes (hand 178), Crossfire 806, Bog 544. No hand waypoints needed
      on maps with demos.
- [x] Gunfights (`tools/fightstats.py`): human bursts, spray wander, slower acquisition flicks,
      stand-and-shoot, fight-start crouch/jump. Reaction 250-650ms, FOV +-57-66 deg, trigger delay ~0.
- [x] Awareness (`tools/whystats.py` context lifts): hear gunfire (look + go toward), teammate-down freeze,
      S&D round-start nades (`tools/nadestats.py`), claymore/C4 only at sensible spots.
- [ ] Weapon/perk mix from real lobbies: needs a local demo + telemetry weapon names to decode indices.
- [ ] Trace-based local steering (move off the graph between nodes); graphs for more maps (need demos).
- Note: output during an rcon command (incl. `map` loads) goes to the rcon reply, not the console log;
  `tools/rcon.py --wait 20 map X` shows it. Host sleep crashes the server (loop detector) -> restart policy.

## P1 — Biggest human tells
- [x] Fight-driven navigation: replace random-waypoint `walk_loop` goals with a heat map
      (recent kills/deaths, last-known enemies, radar pings, objective) weighted by lanes.
- [ ] Look-where-humans-look: while moving, check doorways/sightlines/flanks from the
      waypoint graph (most exposed neighbor, last-known enemy dir), not the next node.
- [ ] Per-bot aim quirks: persistent bias (aims low / right). Lead quirk done (`lead_frac`).
- [x] Lobby lifecycle: trickle joins, occasional mid-match leaves (esp. after bad streaks),
      partial roster turnover between maps. Hooks in `addBots/teamBots`.
- [ ] Per-bot adaptive difficulty targeting human K/D ~1.0-1.5; tilt after death streaks,
      sharpen on kill streaks.
- [ ] (live) Check scoreboard ping column for bots on CoD4x; likely engine/plugin side.

## P2 — Identity + social
- [x] Persistent identity: name ↔ persona/skill/loadout stored across maps (dvar keyed by name).
- [x] Clan tags on a subset of names; audit `bots.txt` names for era/realism.
- [x] Chat pass: 2008-era tone, lowercase, occasional typos, typing delay by length, rarer.
- [ ] Info-cheat audit: `remember_time` default (25s), footstep hearing vs Dead Silence,
      any remaining exact-position knowledge.

## P3 — Robustness (carried over, needs live server)
- [ ] Undefined guards: `bot.target.entity`, `targets[key]`, `waypoints[next_wp]`, sparse `getarraykeys`
- [ ] Targeting: stale `script_target`, `target_this_frame` consume-once, `trace_time` reset races
- [ ] Aim/fire: `pressADS/fire` thread spam, `canAds/canFire/isInRange` for `none`/`c4_mp`
- [ ] Movement: A* `waypointusage` inc/dec leak, `killWalk*` notify races
- [ ] Objectives: SD/SAB `BotPressUse` overlap, dom flag races, intermission kick counting
- [ ] Menu/editor: host-check bypass, CSV index shift on delete, `checkForWarnings` orphans
- [ ] Adapter: `level.bot_builtins` noops, `fs_fopen` path traversal, `thinkSmoke` growth
- [ ] DVAR/config: `getdvarint` defaults, `bots_skill 8/9`, fill/balance infinite-kick edge

## Done (previous pass, uncommitted, not live-tested)
- Humanization skill keys + defaults per skill; contextual reaction (`getEffectiveReaction`);
  peripheral FOV; threat scoring + hysteresis + switch penalty; trigger delay.
- Movement: patrol-biased routing, ADAD strafe bursts, stuck hesitation (no wall-knifing),
  mantle pause, sprint hops, arrival fidget.
- Tactics: dom crowding cap, follow spacing/overwatch, no follow chains, urgent SD/SAB plants.
- Personas (rusher/anchor/objective/support); low-skill panic reloads.
- No-cheats: delayed attacker awareness, cry-for-help targets teammate, fuzzy hearing/UAV goals.
- Crash guards: HQ radio, SAB/SD carrier, `lastdroppableweapon`, threat deref, editor delete,
  menu freeze. mp_brecourt_v2 legacy waypoint types fixed.
