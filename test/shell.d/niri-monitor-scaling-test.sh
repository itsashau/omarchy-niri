#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
scale_out="$test_tmp/niri-output-scale"

mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-niri-monitor-focused" <<'SH'
#!/bin/bash
echo "eDP-1"
SH
chmod +x "$stub_bin/omarchy-niri-monitor-focused"

cat >"$stub_bin/niri" <<'SH'
#!/bin/bash
if [[ $1 == msg && $2 == -j && $3 == outputs ]]; then
  printf '{"eDP-1":{"logical":{"scale":%s}}}' "${OMARCHY_TEST_MONITOR_SCALE:-2}"
elif [[ $1 == msg && $2 == output && $4 == scale ]]; then
  printf '%s\n' "$5" >"$OMARCHY_TEST_NIRI_SCALE_OUT"
else
  exit 1
fi
SH
chmod +x "$stub_bin/niri"

run_scaling() {
  PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_NIRI_SCALE_OUT="$scale_out" \
    OMARCHY_TEST_MONITOR_SCALE="${OMARCHY_TEST_MONITOR_SCALE:-2}" \
    "$ROOT/bin/omarchy-niri-monitor-scaling" "$@"
}

OMARCHY_TEST_MONITOR_SCALE=1 run_scaling up
grep -Fx '1.25' "$scale_out" >/dev/null || fail "monitor scaling up steps 1x to 1.25x"
pass "monitor scaling up steps 1x to 1.25x"

OMARCHY_TEST_MONITOR_SCALE=4 run_scaling up
grep -Fx '4' "$scale_out" >/dev/null || fail "monitor scaling up clamps at the top preset"
pass "monitor scaling up clamps at the top preset"

OMARCHY_TEST_MONITOR_SCALE=1 run_scaling down
grep -Fx '1' "$scale_out" >/dev/null || fail "monitor scaling down clamps at the bottom preset"
pass "monitor scaling down clamps at the bottom preset"

# 1.5 isn't a preset; nearest is 1.6, then one step up from there is 2.
OMARCHY_TEST_MONITOR_SCALE=1.5 run_scaling up
grep -Fx '2' "$scale_out" >/dev/null || fail "monitor scaling up snaps to nearest preset before stepping"
pass "monitor scaling up snaps to nearest preset before stepping"

scale=$(OMARCHY_TEST_MONITOR_SCALE=1.6 run_scaling)
[[ $scale == "1.6" ]] || fail "monitor scaling reports the current scale" "actual: $scale"
pass "monitor scaling reports the current scale"

# --help must work without ever touching niri or a focused output (no
# session running is the common case this guards against).
help_out=$(PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-niri-monitor-scaling" --help)
[[ $help_out == "Usage: omarchy-niri-monitor-scaling [up|down|SCALE]" ]] ||
  fail "monitor scaling --help prints usage without a focused output" "actual: $help_out"
pass "monitor scaling --help prints usage without a focused output"
