#!/usr/bin/env python3
"""
Offline model of the bot aim controller in maps/mp/bots/_bot_internal.gsc
(bot_lookat / aimControllerStep). Keep the two in sync: same constants,
same order of operations, 20Hz ticks.

Scenarios per skill base (1-7, matching the difficulty() tables):
  acquire  - target pops up at a random 20-120 deg offset, 800-2500u, standing
  strafe   - tracking an ADAD strafer (190 u/s, 0.4-0.9s bursts) at 1500u
  spray    - holding fire 1.5s on a still target at 1500u (recoil climb)
  idle     - no target, gaze-model look changes; view rounded to 1 deg like the
             netcode, scored with tools/awarescore.py's own view-texture code
             against the NamelessNoobs Backlot humans

Usage: tools/sim/aim_sim.py [--trials N] [--trace FILE.csv]
"""
import argparse
import csv
import math
import random

TICK = 0.05
off_amp = [0.0]  # last acquire amplitude, for the overshoot metric
UNIT_TO_DEG_W = 15.0  # half-width of a torso in units for Fitts' W

# difficulty() values: base -> (aim_time, aim_jitter, overshoot)
SKILLS = {
	1: (0.6, 0.50, 25),
	2: (0.55, 0.45, 22),
	3: (0.4, 0.40, 19),
	4: (0.3, 0.35, 16),
	5: (0.25, 0.30, 13),
	6: (0.2, 0.25, 10),
	7: (0.1, 0.20, 7),
}


def clamp180(a):
	a = (a + 180.0) % 360.0 - 180.0
	return a


def gauss3(sd):
	# GSC has no gaussian; sum of 3 uniforms, same as the script
	# sum of 3 U(-1,1) has variance 1, so this has std dev = sd
	return (random.uniform(-1, 1) + random.uniform(-1, 1) + random.uniform(-1, 1)) * sd


def aim_log2(x):
	# matches aimLog2 in GSC: exponent + linear mantissa
	n = 0
	while x >= 2:
		x /= 2
		n += 1
	return n + (x - 1)


def torso_w(dist):
	# matches GSC: small-angle approx of atan(15 / dist) in degrees
	return 859.4 / max(dist, 50.0)


def minjerk(t):
	return t * t * t * (10 - 15 * t + 6 * t * t)


class Aim:
	casual_slow = IDLE_TURN_SLOW  # mirrors dvar bots_idle_turn_slow
	casual_overshoot = True
	casual_drift = 0.3  # idle sway, fraction of aim_jitter (GSC aimControllerStep)
	casual_decay = 0.99

	def __init__(self, base, ang=(0.0, 0.0)):
		self.aim_time, self.jitter, self.overshoot = SKILLS[base]
		self.base = base
		self.ang = list(ang)          # intended angles (pitch, yaw), no noise
		self.mode = "track"
		self.fl_start = None
		self.fl_t = 0
		self.fl_n = 0
		self.fl_k = 0.0
		self.fl_perp = 0.0
		self.last_goal = None
		self.drift = [0.0, 0.0]
		self.recoil = [0.0, 0.0]
		self.comp = 0.5 + base * 0.06
		self.corrections = 0
		self.settled = False
		self.skill_err = 1.0 - (base - 1) * 0.1
		# persistent per-bot quirk: how much of a mover's lag it leads out
		self.lead_frac = random.uniform(0.35, 0.75) + base * 0.04
		# perceived target velocity: humans notice direction changes ~150-250ms late
		self.vel_seen = 0.0

	def perceive_vel(self, v):
		self.vel_seen += (v - self.vel_seen) * (0.2 + self.base * 0.02)
		return self.vel_seen

	def track_gain(self, casual):
		g = min(0.4, max(0.1, 0.05 / self.aim_time))
		if casual:
			g *= 0.45
		return g

	def lead_time(self):
		# pursuit lag of the exponential tracker, partly compensated
		g = self.track_gain(False)
		return TICK * (1 - g) / g * self.lead_frac

	def flick_ticks(self, amp, w, casual):
		a = 0.04 + self.aim_time * 0.25
		b = 0.03 + self.aim_time * 0.06
		t = a + b * aim_log2(1.0 + amp / w)
		if casual:
			t *= self.casual_slow
		else:
			t *= ACQ_SLOW     # mirrors the GSC acquisition-flick slowdown
		ticks = max(2, int(round(t / TICK)))
		# 2 ticks = two equal steps, a flat robot turn; bell shape needs >= 3
		if amp > 10 and ticks < 3:
			ticks = 3
		return ticks

	def step(self, goal, dist, casual=False, moving=False, firing=False, full_auto=True):
		ex = clamp180(goal[0] - self.ang[0])
		ey = clamp180(goal[1] - self.ang[1])
		err = math.hypot(ex, ey)
		jump = 0.0
		if self.last_goal is not None:
			jump = math.hypot(clamp180(goal[0] - self.last_goal[0]), clamp180(goal[1] - self.last_goal[1]))
		self.last_goal = list(goal)

		w = torso_w(dist)
		se = self.skill_err
		if self.mode != "flick" and err > 4.0 and (jump > 2.0 or err > 15.0):
			# primary ballistic submovement: aims at "roughly there"
			self.mode = "flick"
			self.fl_start = list(self.ang)
			self.fl_t = 0
			self.fl_n = self.flick_ticks(err, max(w, 2.5), casual)
			self.fl_k = -0.04 * se + gauss3(0.06 * se)
			if (not casual or self.casual_overshoot) and random.randint(0, 99) < self.overshoot:
				self.fl_k = abs(self.fl_k) + random.uniform(0.04, 0.12)
			self.fl_perp = gauss3(0.03 * se)
			self.corrections = 2
			if casual:
				self.corrections = 1 if self.casual_overshoot else 0
		elif self.mode != "flick" and self.corrections > 0 and err > max(w, 0.8):
			# corrective submovement: short, accurate, no deliberate overshoot
			self.corrections -= 1
			self.mode = "flick"
			self.fl_start = list(self.ang)
			self.fl_t = 0
			self.fl_n = self.flick_ticks(err, max(w, 0.5), False)
			self.fl_k = gauss3(0.08 * se)
			self.fl_perp = gauss3(0.04 * se)

		if self.mode == "flick":
			self.fl_t += 1
			s = minjerk(min(1.0, self.fl_t / self.fl_n))
			dx = clamp180(goal[0] - self.fl_start[0])
			dy = clamp180(goal[1] - self.fl_start[1])
			self.ang[0] = clamp180(self.fl_start[0] + (dx * (1 + self.fl_k) - dy * self.fl_perp) * s)
			self.ang[1] = clamp180(self.fl_start[1] + (dy * (1 + self.fl_k) + dx * self.fl_perp) * s)
			if self.fl_t >= self.fl_n:
				self.mode = "track"
		else:
			g = self.track_gain(casual)
			# casual: hands off the mouse until the look target has moved away
			if casual:
				if err > 1.5:
					self.settled = False
				elif err < 0.4:
					self.settled = True
			else:
				self.settled = False
			if not self.settled and err > 0.15:
				self.ang[0] = clamp180(self.ang[0] + ex * g)
				self.ang[1] = clamp180(self.ang[1] + ey * g)

		if casual:
			# a resting hand barely moves: slow, small sway (none at 0)
			sd = self.jitter * self.casual_drift
			d = self.casual_decay
			n = math.sqrt(1 - d * d)
			self.drift[0] = self.drift[0] * d + gauss3(sd * n)
			self.drift[1] = self.drift[1] * d + gauss3(sd * n)
		else:
			# Ornstein-Uhlenbeck drift: slow, correlated sway, not per-tick buzz
			sd = self.jitter
			if moving:
				sd *= 1.5
			decay = 0.92
			n = math.sqrt(1 - decay * decay)
			self.drift[0] = self.drift[0] * decay + gauss3(sd * n)
			self.drift[1] = self.drift[1] * decay + gauss3(sd * n)

		# recoil: kick per fired tick, partially pulled down, recovers when idle
		if firing and full_auto:
			self.recoil[0] -= random.uniform(0.2, 0.35) * (1 - self.comp)
			self.recoil[1] += random.uniform(-0.12, 0.12) * (1 - self.comp)
		else:
			self.recoil[0] *= 0.75
			self.recoil[1] *= 0.75

		return (self.ang[0] + self.drift[0] + self.recoil[0], self.ang[1] + self.drift[1] + self.recoil[1])


def ang_err(view, goal):
	return math.hypot(clamp180(view[0] - goal[0]), clamp180(view[1] - goal[1]))


def acquire(base, trace=None):
	aim = Aim(base)
	dist = random.uniform(800, 2500)
	off = random.uniform(20, 120) * random.choice([-1, 1])
	goal = (random.uniform(-5, 5), off)
	prev = (0.0, 0.0)
	peak = 0.0
	on_t = None
	max_over = 0.0
	for tick in range(60):
		view = aim.step(goal, dist)
		speed = ang_err(view, prev) / TICK
		peak = max(peak, speed)
		prev = view
		progress = view[1] / off
		max_over = max(max_over, (progress - 1) * abs(off))
		w = math.degrees(math.atan2(UNIT_TO_DEG_W, dist))
		if on_t is None and ang_err(view, goal) < w:
			on_t = (tick + 1) * TICK
		if trace:
			trace.writerow(["acquire", base, tick, view[0], view[1], goal[0], goal[1]])
	off_amp[0] = off
	return on_t, peak, max_over


def strafe(base, trace=None):
	aim = Aim(base)
	dist = 1500.0
	x = 0.0
	v = 190.0
	t_switch = random.uniform(0.4, 0.9)
	errs = []
	for tick in range(100):
		t_switch -= TICK
		if t_switch <= 0:
			v = -v
			t_switch = random.uniform(0.4, 0.9)
		x += v * TICK
		goal = (0.0, math.degrees(math.atan2(x, dist)))
		led = (0.0, math.degrees(math.atan2(x + aim.perceive_vel(v) * aim.lead_time(), dist)))
		view = aim.step(led, dist)
		if tick > 20:
			errs.append(ang_err(view, goal))
		if trace:
			trace.writerow(["strafe", base, tick, view[0], view[1], goal[0], goal[1]])
	w = math.degrees(math.atan2(UNIT_TO_DEG_W, dist))
	on = sum(1 for e in errs if e < w) / len(errs)
	return sum(errs) / len(errs), on


def spray(base, trace=None):
	aim = Aim(base)
	dist = 1500.0
	goal = (0.0, 0.0)
	worst = 0.0
	for tick in range(30):
		view = aim.step(goal, dist, firing=True)
		worst = max(worst, ang_err(view, goal))
		if trace:
			trace.writerow(["spray", base, tick, view[0], view[1], goal[0], goal[1]])
	return worst


class OldIdle(Aim):
	"""The controller before the idle-texture fix, for A/B in the idle scenario."""

	def flick_ticks(self, amp, w, casual):
		a = 0.04 + self.aim_time * 0.25
		b = 0.03 + self.aim_time * 0.06
		t = a + b * aim_log2(1.0 + amp / w)
		if casual:
			t *= 2.2
		return max(2, int(round(t / TICK)))

	def step(self, goal, dist, casual=False, moving=False, firing=False, full_auto=True):
		return self._old(goal, dist, casual, moving)

	def _old(self, goal, dist, casual, moving):
		# identical to Aim.step before the fix: pursuit down to 0.15 deg and
		# drift always on
		ex = clamp180(goal[0] - self.ang[0])
		ey = clamp180(goal[1] - self.ang[1])
		err = math.hypot(ex, ey)
		jump = 0.0
		if self.last_goal is not None:
			jump = math.hypot(clamp180(goal[0] - self.last_goal[0]), clamp180(goal[1] - self.last_goal[1]))
		self.last_goal = list(goal)
		w = torso_w(dist)
		se = self.skill_err
		if self.mode != "flick" and err > 4.0 and (jump > 2.0 or err > 15.0):
			self.mode = "flick"
			self.fl_start = list(self.ang)
			self.fl_t = 0
			self.fl_n = self.flick_ticks(err, max(w, 2.5), casual)
			self.fl_k = -0.04 * se + gauss3(0.06 * se)
			self.fl_perp = gauss3(0.03 * se)
		if self.mode == "flick":
			self.fl_t += 1
			s = minjerk(min(1.0, self.fl_t / self.fl_n))
			dx = clamp180(goal[0] - self.fl_start[0])
			dy = clamp180(goal[1] - self.fl_start[1])
			self.ang[0] = clamp180(self.fl_start[0] + (dx * (1 + self.fl_k) - dy * self.fl_perp) * s)
			self.ang[1] = clamp180(self.fl_start[1] + (dy * (1 + self.fl_k) + dx * self.fl_perp) * s)
			if self.fl_t >= self.fl_n:
				self.mode = "track"
		elif err > 0.15:
			g = self.track_gain(casual)
			self.ang[0] = clamp180(self.ang[0] + ex * g)
			self.ang[1] = clamp180(self.ang[1] + ey * g)
		sd = self.jitter * (1.5 if moving else 1.0)
		n = math.sqrt(1 - 0.92 * 0.92)
		self.drift[0] = self.drift[0] * 0.92 + gauss3(sd * n)
		self.drift[1] = self.drift[1] * 0.92 + gauss3(sd * n)
		return (self.ang[0] + self.drift[0], self.ang[1] + self.drift[1])


GLANCE_WANDER = True   # mirrors dvar bots_glance_wander
ACQ_SLOW = 1.8         # mirrors the GSC acquisition-flick slowdown (1.8)
IDLE_TURN_SLOW = 1.0   # mirrors dvar bots_idle_turn_slow (1.0 = as-is)


def idle(base, old, ticks=6000):
	"""Standing/walking with no target: gaze-model looks (bot_lookat casual path).

	Returns 20Hz rows in awarescore's tuple layout, angles rounded to 1 deg."""
	aim = (OldIdle if old else Aim)(base)
	rows = []
	look = [3.0, 0.0]
	next_look = 0
	idle_pitch = random.uniform(0.5, 5)
	wander, next_wander = 0.0, 0
	gwander, next_gwander = (0.0, 0.0), 0
	moving = False
	for tick in range(ticks):
		t = tick * 50
		if t >= next_look:
			moving = random.random() < 0.6
			# gaze picks: mostly near the dominant direction, sometimes elsewhere
			if random.random() < 0.6:
				look[1] += random.uniform(-8, 8)
			else:
				look[1] += random.choice((-1, 1)) * random.uniform(20, 120)
			look[0] = random.gauss(2, 6) + random.uniform(-3, 3)
			next_look = t + (random.randint(500, 1400) if moving else random.randint(800, 2400))
		if old:
			wander = wander * 0.97 + random.uniform(-2.5, 2.5)
		elif t >= next_wander:
			wander = max(-10.0, min(10.0, gauss3(4)))
			next_wander = t + random.randint(1500, 5000)
		# mirror of bots_glance_wander: a held gaze drifts inside the spot it is
		# looking at, +-14u at 1000u distance = +-0.8 deg, refreshed every 180-420ms
		if GLANCE_WANDER:
			if t >= next_gwander:
				next_gwander = t + random.randint(180, 420)
				gwander = (max(-0.8, min(0.8, gwander[0] + random.uniform(-0.23, 0.23))),
				           max(-0.8, min(0.8, gwander[1] + random.uniform(-0.23, 0.23))))
			goal = (look[0] + idle_pitch + wander, look[1] + gwander[0])
		else:
			goal = (look[0] + idle_pitch + wander, look[1])
		view = aim.step(goal, 1000.0, casual=True, moving=moving)
		p = max(-85, min(85, round(view[0])))
		rows.append((t, 0.0, 0.0, 0.0, float(p), float(round(view[1]) % 360), 0, 1, 1022, "1"))
	return rows


def idle_report(trials):
	import os
	import sys
	sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
	import awarescore as A
	print("\nidle view texture (1 deg rounded, per 1000 frames; humans from demo0000 Backlot):")
	print("  version  small flips  big flips  frames still  flick peak/mean  flicks/min")
	print("  humans        18.4        26.3        61.9%        1.75           37.6")
	for old in (True, False):
		small = big = still = n = 0
		shapes, fl_n, mins = [], 0, 0.0
		for i in range(trials):
			fr = A.frames(idle(random.randint(2, 6), old))
			prev = None
			for f in fr:
				if f is None:
					continue
				n += 1
				ay = abs(f[2])
				still += ay < 0.5
				if ay >= 0.5:
					sgn = f[2] > 0
					if prev is not None and sgn != prev[0]:
						if ay < 1.5 and prev[1] < 1.5:
							small += 1
						else:
							big += 1
					prev = (sgn, ay)
			fl = A.find_flicks(fr)
			shapes += [x[4] for x in fl]
			fl_n += len(fl)
			mins += len(fr) * TICK / 60
		shapes.sort()
		print(f"  {'before' if old else 'after ':7s}  {1000 * small / n:9.1f}  {1000 * big / n:9.1f}  "
			f"{100 * still / n:10.1f}%   {shapes[len(shapes) // 2]:10.2f}      {fl_n / mins:9.1f}")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--trials", type=int, default=400)
	ap.add_argument("--trace")
	ap.add_argument("--seed", type=int, default=1)
	args = ap.parse_args()
	random.seed(args.seed)

	tf = open(args.trace, "w", newline="") if args.trace else None
	tw = csv.writer(tf) if tf else None
	if tw:
		tw.writerow(["scenario", "base", "tick", "pitch", "yaw", "goal_pitch", "goal_yaw"])

	print("base | acquire: on-target s (p50/p90)  peak deg/s  overshoot%  | strafe: mean err  on-target%  | spray: max drift deg")
	for base in sorted(SKILLS):
		on, peaks, overs = [], [], []
		for i in range(args.trials):
			o, p, ov = acquire(base, tw if i == 0 else None)
			if o is not None:
				on.append(o)
			peaks.append(p)
			overs.append(ov > max(1.0, 0.03 * abs(off_amp[0])))
		on.sort()
		se, so = zip(*[strafe(base, tw if i == 0 else None) for i in range(args.trials // 4)])
		sp = [spray(base, tw if i == 0 else None) for i in range(args.trials // 4)]
		p50 = on[len(on) // 2] if on else float("nan")
		p90 = on[int(len(on) * 0.9)] if on else float("nan")
		print(f"  {base}  |   {p50:4.2f} / {p90:4.2f}   ({len(on) * 100 // args.trials:3d}% hit)   {sorted(peaks)[len(peaks)//2]:6.0f}      {sum(overs) * 100 // len(overs):3d}%     |"
			f"   {sum(se)/len(se):5.2f}      {sum(so)*100/len(so):5.1f}%   |   {sum(sp)/len(sp):4.2f}")
	if tf:
		tf.close()
	idle_report(max(4, args.trials // 50))


if __name__ == "__main__":
	main()
