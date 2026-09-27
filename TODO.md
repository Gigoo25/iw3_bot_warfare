# IW3 Bot Warfare — Human-Indistinguishable Bots

Goal: join a lobby and not be able to tell the bots from players, especially
in killcams, spectating, and the scoreboard.

## Validation
- `tools/check.sh` — offline, no game files: gsc-tool syntax parse + `tools/gsc_lint.py`
  (unknown functions, bad `path::func`, too many args, missing `::func` refs).
  Run after every edit batch. NOTE: `build.sh` only zips; it never validated anything.
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
