#!/bin/bash
# Offline validation: gsc-tool syntax parse + tools/gsc_lint.py.
# No game files needed. Runtime behavior still needs a CoD4x server.
set -e
cd "$(dirname "$0")/.."

GSC_TOOL_VERSION="1.4.10"
BIN_DIR="tools/.bin"
GSC_TOOL="$BIN_DIR/gsc-tool"

if [ ! -x "$GSC_TOOL" ]; then
	echo "Fetching gsc-tool $GSC_TOOL_VERSION..."
	mkdir -p "$BIN_DIR"
	curl -sfL "https://github.com/xensik/gsc-tool/releases/download/$GSC_TOOL_VERSION/linux-amd64-release.tar.gz" | tar xz -C "$BIN_DIR"
	chmod +x "$GSC_TOOL"
fi

echo "== gsc-tool parse (iw5 grammar, closest to iw3) =="
fail=0
count=0
for dir in maps scripts; do
	if ! out=$("$GSC_TOOL" -m parse -g iw5 -s pc -y "$dir" 2>&1); then
		fail=1
	fi
	echo "$out" | grep -E "ERROR|error" || true
	count=$((count + $(echo "$out" | grep -c '^parsed ')))
done
if [ $fail -ne 0 ]; then
	echo "parse: FAILED"
	exit 1
fi
echo "parse: $count files OK"

echo "== gsc_lint =="
python3 tools/gsc_lint.py "$@"
