#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT

reset_home() {
  rm -rf "$test_home"
  mkdir -p "$test_home"
}

run_refresh() {
  env "$@" HOME="$test_home" "$ROOT/bin/omarchy-refresh-niri"
}

reset_home
run_refresh OMARCHY_PATH="/fake/checkout"
[[ $(<"$test_home/.config/niri/config.kdl") == 'include "/fake/checkout/default/niri/config.kdl"' ]] ||
  fail "refresh-niri writes the include line with the given OMARCHY_PATH" "$(<"$test_home/.config/niri/config.kdl")"
pass "refresh-niri writes the include line with the given OMARCHY_PATH"

reset_home
run_refresh -u OMARCHY_PATH
[[ $(<"$test_home/.config/niri/config.kdl") == 'include "/usr/share/omarchy/default/niri/config.kdl"' ]] ||
  fail "refresh-niri falls back to the packaged OMARCHY_PATH when unset" "$(<"$test_home/.config/niri/config.kdl")"
pass "refresh-niri falls back to the packaged OMARCHY_PATH when unset"

reset_home
run_refresh OMARCHY_PATH="/fake/check out with spaces"
[[ $(<"$test_home/.config/niri/config.kdl") == 'include "/fake/check out with spaces/default/niri/config.kdl"' ]] ||
  fail "refresh-niri handles an OMARCHY_PATH containing spaces" "$(<"$test_home/.config/niri/config.kdl")"
pass "refresh-niri handles an OMARCHY_PATH containing spaces"

reset_home
run_refresh OMARCHY_PATH='/fake/back\slash'
[[ $(<"$test_home/.config/niri/config.kdl") == 'include "/fake/back\\slash/default/niri/config.kdl"' ]] ||
  fail "refresh-niri escapes a backslash in OMARCHY_PATH" "$(<"$test_home/.config/niri/config.kdl")"
pass "refresh-niri escapes a backslash in OMARCHY_PATH"

reset_home
run_refresh OMARCHY_PATH="/fake/checkout"
[[ -f "$test_home/.config/niri/overrides.kdl" ]] ||
  fail "refresh-niri creates overrides.kdl when missing"
pass "refresh-niri creates overrides.kdl on first run"

echo "user customization" >>"$test_home/.config/niri/overrides.kdl"
run_refresh OMARCHY_PATH="/fake/checkout"
grep -qF "user customization" "$test_home/.config/niri/overrides.kdl" ||
  fail "refresh-niri must never touch an existing overrides.kdl"
pass "refresh-niri never touches an existing overrides.kdl"
