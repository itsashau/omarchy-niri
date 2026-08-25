#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

# Test against a copy so the test controls /etc/omarchy.conf without
# mutating the host, the same pattern dev-env-path-test.sh uses: a real
# dev-linked host has an actual /etc/omarchy.conf that would otherwise
# silently override OMARCHY_PATH out from under every case below.
refresh_script="$test_dir/omarchy-refresh-niri"
sed "s#/etc/omarchy.conf#$test_dir/omarchy.conf#g" "$ROOT/bin/omarchy-refresh-niri" >"$refresh_script"
chmod +x "$refresh_script"

test_home="$test_dir/home"

run_refresh() {
  rm -rf "$test_home"
  mkdir -p "$test_home"
  env "$@" HOME="$test_home" "$refresh_script"
}

run_refresh OMARCHY_PATH="/fake/checkout"
[[ $(<"$test_home/.config/niri/config.kdl") == 'include "/fake/checkout/default/niri/config.kdl"' ]] ||
  fail "refresh-niri writes the include line with the given OMARCHY_PATH" "$(<"$test_home/.config/niri/config.kdl")"
pass "refresh-niri writes the include line with the given OMARCHY_PATH"

run_refresh -u OMARCHY_PATH
[[ $(<"$test_home/.config/niri/config.kdl") == 'include "/usr/share/omarchy/default/niri/config.kdl"' ]] ||
  fail "refresh-niri falls back to the packaged OMARCHY_PATH when unset" "$(<"$test_home/.config/niri/config.kdl")"
pass "refresh-niri falls back to the packaged OMARCHY_PATH when unset"

run_refresh OMARCHY_PATH="/fake/check out with spaces"
[[ $(<"$test_home/.config/niri/config.kdl") == 'include "/fake/check out with spaces/default/niri/config.kdl"' ]] ||
  fail "refresh-niri handles an OMARCHY_PATH containing spaces" "$(<"$test_home/.config/niri/config.kdl")"
pass "refresh-niri handles an OMARCHY_PATH containing spaces"
