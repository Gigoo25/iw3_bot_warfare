#!/bin/bash
# Extract player states + chat from CoD4/CoD4X .dm_1 demos for tools/demostats.py.
#
# Uses the reference parser github.com/Iswenzz/CoD4-DM1 at a pinned commit plus
# tools/demo/cod4dm1.patch (records every server command) and
# tools/demo/export.cpp. Decodes ~100% of snapshots on CoD4X build 1211 demos.
# Everything builds and runs in Docker (debian:trixie-slim + g++/cmake).
#
# Usage: tools/demo/extract.sh output/demos/*.dm_1
set -e
cd "$(dirname "$0")/../.."
COMMIT=19395c5ab4fa2139fc9533a43637798213e0a602
WORK=output/.cod4-dm1
IMAGE=cod4dm1-build

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
	printf 'FROM debian:trixie-slim\nRUN apt-get update -qq && apt-get install -y -qq --no-install-recommends g++ cmake make nlohmann-json3-dev && rm -rf /var/lib/apt/lists/*\n' \
		| docker build -q -t "$IMAGE" - >/dev/null
fi

if [ ! -d "$WORK/.git" ]; then
	git clone -q https://github.com/Iswenzz/CoD4-DM1.git "$WORK"
	git -C "$WORK" checkout -q "$COMMIT"
	git -C "$WORK" apply "$PWD/tools/demo/cod4dm1.patch"
fi

# always refresh the exporter; cmake only rebuilds what changed
mkdir -p "$WORK/export"
cp tools/demo/export.cpp "$WORK/export/"
# the upstream sources are MSVC-first: force the std headers GCC wants
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/$WORK:/src" -w /src "$IMAGE" sh -c \
	'cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-include cstdint -include cstring -include array" >/dev/null && cmake --build build -j8 --target export >/dev/null'

for demo in "$@"; do
	dir=$(cd "$(dirname "$demo")" && pwd)
	base=$(basename "$demo" .dm_1)
	docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/$WORK:/src:ro" -v "$dir:/demos" -w /src "$IMAGE" \
		./build/export "/demos/$base.dm_1" "/demos/$base"
	python3 tools/demostats.py "$dir/$base"
	python3 tools/nadestats.py "$dir/$base"
done
