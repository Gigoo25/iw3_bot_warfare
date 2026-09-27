#!/usr/bin/env python3
"""
Minimal Quake3/CoD4 rcon client for the local test server.

Usage: tools/rcon.py [--host 127.0.0.1] [--port 28960] [--password botdev123] <command...>
  tools/rcon.py status
  tools/rcon.py map mp_crash
  tools/rcon.py set bots_skill 7
"""
import argparse
import socket
import sys

PREFIX = b"\xff\xff\xff\xff"


def rcon(host, port, password, command, timeout=2.0, linger=0.3):
	sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
	sock.settimeout(timeout)
	sock.sendto(PREFIX + f"rcon {password} {command}".encode(), (host, port))
	chunks = []
	try:
		while True:
			data, _ = sock.recvfrom(65535)
			chunks.append(data.removeprefix(PREFIX).removeprefix(b"print\n"))
			sock.settimeout(linger)  # multi-packet replies arrive back to back
	except socket.timeout:
		pass
	finally:
		sock.close()
	if not chunks:
		return None  # no packet at all: server down / wrong port or password
	return b"".join(chunks).decode(errors="replace")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--host", default="127.0.0.1")
	ap.add_argument("--port", type=int, default=28960)
	ap.add_argument("--password", default="botdev123")
	ap.add_argument("--wait", type=float, default=0.0, help="listen this long for slow replies (e.g. map loads)")
	ap.add_argument("command", nargs="+")
	args = ap.parse_args()
	if args.wait:
		out = rcon(args.host, args.port, args.password, " ".join(args.command), timeout=args.wait, linger=3.0)
	else:
		out = rcon(args.host, args.port, args.password, " ".join(args.command))
	if out is None:
		print("no reply (server down or wrong port/password)", file=sys.stderr)
		return 1
	print(out, end="")
	return 0


if __name__ == "__main__":
	sys.exit(main())
