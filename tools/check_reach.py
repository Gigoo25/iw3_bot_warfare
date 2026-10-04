#!/usr/bin/env python3
"""
Check whether a CoD4 dedicated server is reachable over UDP from this machine.

    python3 tools/check_reach.py <server-ip> [port] [password]

Prints one of:
    REACHABLE   the server answered with a status reply
    NO REPLY    the UDP packet went out but nothing came back
    NO ROUTE    this host cannot even route to that address

Only the standard library, so it can be copy-pasted onto another machine or run
as `python3 - <<'EOF'` there. It speaks CoD4's rcon-over-UDP (the same thing
tools/rcon.py uses), so a REACHABLE answer proves the server is reachable and
answering -- exactly what a game client needs.

A NO REPLY is ambiguous between "firewall dropped it" and "wrong address"; this
script cannot tell those apart, because UDP gives no error. To separate them, run
it against the loopback of the server host itself: if that answers and the LAN
address does not, it is the firewall or the network, not the server.
"""
import socket
import sys


def status_query(host, port, password, timeout=2.0, linger=0.4):
	"""Same framing as tools/rcon.py: PREFIX + "rcon <pw> status", read until quiet."""
	prefix = b"\xff\xff\xff\xff"
	sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
	sock.settimeout(timeout)
	chunks = []
	try:
		sock.sendto(prefix + f"rcon {password} status".encode(), (host, port))
		while True:
			data, _ = sock.recvfrom(65535)
			chunks.append(data.removeprefix(prefix).removeprefix(b"print\n"))
			sock.settimeout(linger)  # multi-packet replies arrive back to back
	except socket.timeout:
		pass
	finally:
		sock.close()
	return b"".join(chunks).decode(errors="replace") if chunks else None


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    host = argv[1]
    port = int(argv[2]) if len(argv) > 2 else 28960
    password = argv[3] if len(argv) > 3 else "botdev123"
    try:
        socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_DGRAM)
    except socket.gaierror as e:
        print(f"NO ROUTE  cannot resolve {host}: {e}")
        return 1
    reply = status_query(host, port, password)
    if reply:
        import re
        clean = re.sub(r"\^.", "", reply)
        first = [l for l in clean.split("\n") if l.strip()][:3]
        print(f"REACHABLE  {host}:{port} answered:")
        for l in first:
            print("   ", l.strip()[:90])
        return 0
    print(f"NO REPLY   {host}:{port} sent, nothing came back.")
    print("  UDP cannot tell you why. If it works on the server host itself, the")
    print("  block is a firewall or the network path, not the server:")
    print("    - the nftables service is active on the server host (nixos-firewall is not)")
    print("    - or the address is not routable from here (240.248.x is CGNAT space)")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
