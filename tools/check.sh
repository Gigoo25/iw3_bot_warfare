#!/bin/bash
# Offline validation: gsc-tool syntax parse + tools/gsc_lint.py + the tool tests.
# No game files needed. Runtime behavior still needs a CoD4x server (tools/botmatch.sh
# runs one unattended).
#
#   tools/check.sh              gsc parse + lint + fast tool tests
#   tools/check.sh --full       ...plus the slow end-to-end suites (a few minutes)
#   tools/check.sh --no-tests   gsc only (lint args pass through, e.g. --baseline-ref)
set -e
cd "$(dirname "$0")/.."

FULL=0
RUN_TESTS=1
GSC_ARGS=()
for arg in "$@"; do
	case "$arg" in
		--full) FULL=1 ;;
		--no-tests) RUN_TESTS=0 ;;
		*) GSC_ARGS+=("$arg") ;;
	esac
done

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
python3 tools/gsc_lint.py ${GSC_ARGS+"${GSC_ARGS[@]}"}

if [ $RUN_TESTS -eq 0 ]; then
	echo "== tool tests: skipped (--no-tests) =="
	exit 0
fi

echo
echo "== tool tests =="
if [ $FULL -ne 0 ]; then
	# the synthetic end-to-end suites build fake demos/logs and score them
	python3 tools/test_scorecmp.py
	python3 tools/test_btlog.py
	python3 tools/test_awarescore.py
else
	python3 tools/test_scorecmp.py 2>&1 | tail -3
	python3 tools/test_btlog.py Parser Metrics CsvSource 2>&1 | tail -3
fi
