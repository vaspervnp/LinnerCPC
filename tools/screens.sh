#!/usr/bin/env bash
# Screenshots for the README and the manuals (make screens).
#
#   tools/screens.sh [outdir] [name...]
#
# Each shot is a scripted demo build (TEST_FRAMES, no DEBUG border) run in
# tools/cpcsim.py up to its frame (Caprice32 can miss the &0000 breakpoint
# when it comes this early); the loading screen is a disk boot in Caprice32.
# The frame numbers count main loops from the title screen (the demo presses
# FIRE there at loop 25, then the level's READY takes 90 loops).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-docs/screenshots}"; shift || true
B=build/screens
mkdir -p "$OUT" "$B"

# name  frames  defines
SHOTS=(
  "title     20   -DDIFF_DEFAULT=1"
  "ready     105  "
  "level1    300  "
  "swells    520  -DTEST_LEVEL=2"
  "water     420  -DTEST_LEVEL=3 -DTEST_SOAK=1"
  "bureau    700  -DTEST_LEVEL=4"
  "ghost     480  -DTEST_LEVEL=6 -DTEST_GHOST=1 -DTEST_GEAR5=1"
  "entry     1600 -DTEST_HISCORE=1 -DTEST_SOAK=2"
  "newhigh   1640 -DTEST_HISCORE=1 -DTEST_SOAK=2"
  "chasm     610  -DTEST_LEVEL=5 -DTEST_GEAR5=1"
)

shot() {
  local name=$1 frames=$2; shift 2
  mkdir -p "$B/$name"
  (cd "$B/$name" && rasm -amper -v2 -I../../../src -I../.. -DTEST_FRAMES="$frames" "$@" \
     ../../../src/main.asm -oi linner.sna -os linner.sym -s -sl 2>&1 \
     | sed 's/\x1b\[[0-9;]*m//g' > rasm.log)
  if grep -qiE "error|warning" "$B/$name/rasm.log"; then cat "$B/$name/rasm.log"; exit 1; fi
  python3 tools/cpcsim.py "$B/$name/linner.sna" --frames $((frames + 100)) \
    --screen "$OUT/$name.png" | grep "stopped_at_0=True" >/dev/null \
    || { echo "$name: the demo didn't reach frame $frames" >&2; exit 1; }
  echo "$OUT/$name.png"
}

loading() {
  # The DISC.BAS loading screen: boot the disc and shoot while LINNER.BIN loads.
  local pad; pad=$(printf 'z%.0s' $(seq 1 ${LOADING_PAD:-140}))
  tools/cpcemu -nowait -timeout 60 -keys "run\"disc
$pad" -shot "$OUT/loading.png" build/linner.dsk >/dev/null
  echo "$OUT/loading.png"
}

want() { [[ $# -eq 0 ]] && return 0; local n=$1; shift; for w in "${WANT[@]}"; do [[ $w == "$n" ]] && return 0; done; return 1; }
WANT=("$@")

for s in "${SHOTS[@]}"; do
  read -r name frames defs <<<"$s"
  if [[ ${#WANT[@]} -eq 0 ]] || want "$name" "${WANT[@]}"; then
    # shellcheck disable=SC2086
    shot "$name" "$frames" $defs
  fi
done
if [[ ${#WANT[@]} -eq 0 ]] || want loading "${WANT[@]}"; then loading; fi
