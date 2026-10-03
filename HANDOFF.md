# Handoff — humanlike-bots branch (2026-09-27 session)

Goal: bots indistinguishable from humans. Measure with `tools/awarescore.py`, fix GSC,
user reviews in-game (see memory: fix → restart → user review loop). Nothing committed yet.

## State right now
- Server: Docker `server/`, host networking, `192.168.80.254:28960`, rcon `botdev123`.
  Last left on hardcore S&D `mp_backlot` with latest build. User reported "awaiting
  connection" hang → restarted; user had not yet confirmed join works.
- `tools/check.sh` clean (gsc parse + lint). `python3 tools/test_awarescore.py` 13/13 OK.
- GSC files are CRLF. Edit with CRLF-preserving tooling or lint fails ("LF-only lines").

## Open issues (do first)
1. **Server hang at map change.** Log: all bots `EXE_DISCONNECTED` (lobby carry-over,
   `bots_lobby_carry`), `-----` separator, then nothing; rcon dead, client stuck
   "awaiting connection". Unknown if new batch or pre-existing (TODO.md lists carry-over
   as unverified). Reproduce: let a map end / `rcon map_rotate`, watch
   `docker compose logs -f cod4x | grep -v "Bot movement done"`.
2. Fixed but unverified live: `botWantsPickup` read `level.bombzones[i].origin`
   (undefined on gameobjects → runtime error). Now uses `curorigin` / `trigger.origin`.
3. Server boots into `mp_crash` war (server.cfg `g_gametype war`, rotation). Switch via
   `tools/rcon.py set g_gametype sd; tools/rcon.py map mp_backlot`.

## awarescore.py (rewritten)
- Old: OOM (2.3 GB, killed), deaths counted per snapshot (corpses.csv repeats), throws
  attributed to client 0 (owner not decoded), bot chat never matched (realistic names),
  human priors not leave-one-out, team fixed at first row.
- New: tuples, ~19 s / 185 MB for 5 demos. Per-session points; KS + p + in-range +
  spread; sections aim/feel/move/context/fight/life/ordnance/loadout/social; per-section
  and overall leave-one-out naive-Bayes detector AUC; `--sessions`, `--json`,
  `--ignore GLOB` (default ignores `social.ping*` — user doesn't care about ping).
- `context` section = anti "match the share" trap: bout lengths, state given map
  area/round phase/enemy distance (log-lift vs human LOO prior, hierarchical backoff),
  transition JS + entropy rate, minute-to-minute variance.
- Tests: null bots (same generator) → low AUC; planted level-pitch → caught; crouch in
  wrong place with right share → caught by `ctx_where`.
- Limits: angles quantized ~1°; scoreboard only when recorder holds TAB; no reloads/pain/
  hit locs in demos (`ev*` columns always 0); throws = nearest player ≤100u at first sight.

Baseline (old bot demos ours_1..4, recorded 00:21–00:46 Sep 27, predate most code):
AUC 1.00, 28% metrics indistinct. Top tells: flick peak/mean 1.52 vs 1.75, state-for-place
lift −0.91 vs +0.11, transition mix 3x off, burst p90 0.05 vs 1.15 s, 0% crouched firing,
2 vs 6 weapons, reaction p90 1.0 vs 2.6 s, turn flips 1.6 vs 1.0/s, sprint 12 vs 24%,
round-exit IQR 0.

## Bot changes this session (all untested in-game unless noted)
- Aim idle (`_bot_internal.gsc` aimControllerStep/aimFlickTicks/bot_lookat), sim-verified
  via new `idle` scenario in `tools/sim/aim_sim.py`: casual dead zone w/ hysteresis,
  idle drift 0.3x jitter decay .99, no 2.2x idle slowdown, min 3 ticks for flicks >10°,
  idle overshoot + 1 correction, episodic pitch wander (held 1.5–5 s). Sim small flips
  79→17/1000 (human 18), flick shape 1.51→1.71 (human 1.75).
- Motor model where/when: `tools/gen_motor_model.py` emits `sd_area_<map>_<x>_<y>`
  (512u) and `sd_phase_<0-5>` lifts into `_bot_motor_data.gsc`; `motorNext` multiplies
  transition weights (`motorLift`, `motorPhaseBin`).
- Movement: calm sprint 30→45%; jukes (`botStartJuke`, ~0.3%/tick while running, steered
  in `doBotMovement_loop`); S&D round-start stagger (`botWalkAfterStart`).
- Fights: `self.bot.fight_crouch` keeps botFightCrouch through stance_loop; pistol swap
  on empty mag ≤1200u 55% (`botMaybePistolSwap`/`botPistolSwap`); body pickup 35% once
  per fight spot, not near bomb sites (`botWantsPickup`); nade chance x1.6.
- Hearing: `bot_heard_shot` uses per-bot sampled delay (median ~1 s, tail 2.8 s),
  resampled per reaction (`self.bot.hear_delay`).
- Not changed: hard stops, 45° move grid.

## Next steps
1. Fix/understand map-change hang; get user in-game review of batch.
2. Record fresh 10+ min S&D Backlot bot demos on current build →
   `tools/demo/extract.sh` → `tools/awarescore.py --humans output/demos/demo0000
   --bots <new> --sessions --json out.json`. Re-baseline before more tuning.
3. Tune from new numbers; consider updating TODO.md and committing in small batches.
