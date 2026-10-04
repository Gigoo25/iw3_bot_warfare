#!/usr/bin/env python3
"""
Offline GSC sanity checks that gsc-tool's parser does not cover.

- Unresolved calls: a function called unqualified that is not defined in the
  file, its repo #includes, or the builtin/stock baseline.
- Qualified calls (path::func) into repo files that do not define func.
- Arity: calls passing more args than a repo function declares.

Builtins and stock-script functions (maps\\mp\\_utility etc.) cannot be seen
here, so the baseline is every unresolved name already called at a git ref
(default HEAD); those are assumed valid. Only NEW unknown names are errors.

Usage: tools/gsc_lint.py [--baseline-ref REF]
"""
import argparse
import os
import re
import subprocess
import sys

ROOTS = ["maps", "scripts"]
# engine builtins used by the mod that the HEAD baseline never called
# print: CoD4/IW3 console builtin (server console + rcon clients). Used by
# telemetryWatch because CoD4X throttles games_mp.log to ~5 lines a minute.
EXTRA_BUILTINS = {"takeweapon", "botweapon", "print"}

KEYWORDS = {
    "if", "while", "for", "foreach", "switch", "return", "wait", "thread",
    "childthread", "waittill", "waittillmatch", "waittillframeend", "notify",
    "endon", "case", "default", "else", "break", "continue", "isdefined",
}

FUNC_DEF = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*$", re.M)
INCLUDE = re.compile(r"^#include\s+([A-Za-z0-9_\\]+)\s*;", re.M)
CALL = re.compile(r"(?:([A-Za-z0-9_\\]+)::)?([A-Za-z_][A-Za-z0-9_]*)\s*\(")
FUNC_REF = re.compile(r"(?:([A-Za-z0-9_\\]+))?::([A-Za-z_][A-Za-z0-9_]*)")


def strip_comments_and_strings(src):
	src = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), src, flags=re.S)
	src = re.sub(r"//[^\n]*", "", src)
	src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)
	return src


def script_path(path):
	return os.path.splitext(path)[0].replace("/", "\\")


def load_tree(read_file, files):
	tree = {}
	for f in files:
		src = strip_comments_and_strings(read_file(f))
		defs = {}
		for m in FUNC_DEF.finditer(src):
			params = [p for p in m.group(2).split(",") if p.strip()]
			defs[m.group(1).lower()] = len(params)
		tree[script_path(f)] = {
			"file": f,
			"src": src,
			"defs": defs,
			"includes": [i.lower() for i in INCLUDE.findall(src)],
		}
	return tree


def count_args(src, start):
	# start points just past '('
	depth, args, seen = 1, 0, False
	i = start
	while i < len(src) and depth:
		c = src[i]
		if c in "([":
			depth += 1
		elif c in ")]":
			depth -= 1
		elif c == "," and depth == 1:
			args += 1
		if depth and not c.isspace():
			seen = True
		i += 1
	return args + 1 if seen else 0


def iter_calls(tree):
	lower_tree = {k.lower(): v for k, v in tree.items()}
	for path, info in tree.items():
		src = info["src"]
		body_starts = {m.start() for m in FUNC_DEF.finditer(src)}
		for m in CALL.finditer(src):
			if m.start() in body_starts:
				continue
			qual, name = m.group(1), m.group(2).lower()
			if name in KEYWORDS:
				continue
			line = src.count("\n", 0, m.start()) + 1
			nargs = count_args(src, m.end())
			yield path, info, lower_tree, qual, name, line, nargs


def resolve(info, lower_tree, qual, name):
	"""Returns (resolved_arity or None, in_repo_target) ."""
	if qual:
		target = lower_tree.get(qual.lower())
		if target is None:
			return None, False
		return target["defs"].get(name, -1), True
	if name in info["defs"]:
		return info["defs"][name], True
	for inc in info["includes"]:
		target = lower_tree.get(inc)
		if target and name in target["defs"]:
			return target["defs"][name], True
	return None, False


def unresolved_names(tree):
	names = set()
	for path, info, lower_tree, qual, name, line, nargs in iter_calls(tree):
		arity, in_repo = resolve(info, lower_tree, qual, name)
		if arity is None:
			names.add(name)
	return names


def git_files(ref):
	out = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", ref, "--"] + ROOTS, text=True)
	return [f for f in out.split() if f.endswith((".gsc", ".gsx"))]


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--baseline-ref", default="HEAD")
	args = ap.parse_args()

	base_files = git_files(args.baseline_ref)
	base_tree = load_tree(
		lambda f: subprocess.check_output(["git", "show", f"{args.baseline_ref}:{f}"], text=True, errors="replace"),
		base_files)
	known = unresolved_names(base_tree)

	files = []
	for root in ROOTS:
		for d, _, fs in os.walk(root):
			files += [os.path.join(d, f) for f in fs if f.endswith((".gsc", ".gsx"))]
	tree = load_tree(lambda f: open(f, errors="replace").read(), sorted(files))

	errors = 0
	for path, info, lower_tree, qual, name, line, nargs in iter_calls(tree):
		arity, in_repo = resolve(info, lower_tree, qual, name)
		loc = f"{info['file']}:{line}"
		if in_repo and arity == -1:
			print(f"{loc}: error: {qual}::{name} not defined in target script")
			errors += 1
		elif arity is None and qual and not in_repo:
			pass  # stock game script (maps\mp\gametypes\...); verified at load on the server
		elif arity is None and name not in known and name not in EXTRA_BUILTINS:
			print(f"{loc}: error: unresolved call '{name}' (not defined, not included, not in baseline)")
			errors += 1
		elif arity is not None and arity >= 0 and nargs > arity:
			print(f"{loc}: error: '{name}' called with {nargs} args, declares {arity}")
			errors += 1

	# qualified function references like ::foo (no call parens)
	for path, info in tree.items():
		for m in FUNC_REF.finditer(info["src"]):
			qual, name = m.group(1), m.group(2).lower()
			if qual:
				continue
			if name not in info["defs"] and not any(
					name in tree.get(k, {}).get("defs", {}) for k in tree if k.lower() in info["includes"]):
				line = info["src"].count("\n", 0, m.start()) + 1
				print(f"{info['file']}:{line}: error: ::{name} reference not defined in file or includes")
				errors += 1

	# CoD4x botaction only accepts these (runtime error otherwise)
	actions = {"gostand", "gocrouch", "goprone", "fire", "melee", "frag", "smoke", "reload",
		"sprint", "leanleft", "leanright", "ads", "holdbreath", "activate"}
	for path, info in tree.items():
		raw = open(info["file"], errors="replace").read()
		for m in re.finditer(r'BotBuiltinBotAction\(\s*"([+-])([^"]*)"', raw):
			if m.group(2) not in actions:
				line = raw.count("\n", 0, m.start()) + 1
				print(f"{info['file']}:{line}: error: botaction '{m.group(1)}{m.group(2)}' not supported by CoD4x")
				errors += 1

	# line endings: files that are CRLF at the baseline must stay CRLF
	for f in base_files:
		if not os.path.exists(f):
			continue
		base = subprocess.check_output(["git", "show", f"{args.baseline_ref}:{f}"])
		if base.count(b"\r\n") * 2 < base.count(b"\n"):
			continue
		cur = open(f, "rb").read()
		lf_only = cur.count(b"\n") - cur.count(b"\r\n")
		if lf_only:
			print(f"{f}: error: {lf_only} LF-only line(s); file is CRLF at {args.baseline_ref}")
			errors += 1

	print(f"gsc_lint: {len(tree)} files, {errors} error(s)")
	return 1 if errors else 0


if __name__ == "__main__":
	sys.exit(main())
