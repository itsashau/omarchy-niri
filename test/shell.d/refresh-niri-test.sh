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

reset_home
run_refresh OMARCHY_PATH="/fake/checkout"
generated=$(<"$test_home/.config/niri/config.kdl")
run_refresh OMARCHY_PATH="/fake/checkout"
[[ $(<"$test_home/.config/niri/config.kdl") == "$generated" ]] ||
  fail "refresh-niri run twice with the same OMARCHY_PATH must not disturb config.kdl"
[[ ! -e "$test_home/.config/niri/config.kdl".bak.* ]] ||
  fail "refresh-niri run twice with the same OMARCHY_PATH must not create a .bak file"
pass "refresh-niri run twice with an unchanged OMARCHY_PATH leaves config.kdl alone"

reset_home
mkdir -p "$test_home/.config/niri"
printf 'real hand-edited niri config\n' >"$test_home/.config/niri/config.kdl"
run_refresh OMARCHY_PATH="/fake/checkout"
[[ $(<"$test_home/.config/niri/config.kdl") == 'include "/fake/checkout/default/niri/config.kdl"' ]] ||
  fail "refresh-niri regenerates config.kdl after preserving pre-existing content"
grep -qF "real hand-edited niri config" "$test_home/.config/niri/overrides.kdl" ||
  fail "refresh-niri moves pre-existing config.kdl content into overrides.kdl when it doesn't exist yet"
pass "refresh-niri moves pre-existing config.kdl content into overrides.kdl when missing"

reset_home
mkdir -p "$test_home/.config/niri"
printf 'existing overrides content\n' >"$test_home/.config/niri/overrides.kdl"
printf 'real hand-edited niri config\n' >"$test_home/.config/niri/config.kdl"
run_refresh OMARCHY_PATH="/fake/checkout"
[[ $(<"$test_home/.config/niri/config.kdl") == 'include "/fake/checkout/default/niri/config.kdl"' ]] ||
  fail "refresh-niri regenerates config.kdl after backing up pre-existing content"
grep -qF "existing overrides content" "$test_home/.config/niri/overrides.kdl" ||
  fail "refresh-niri must not clobber an already-customized overrides.kdl"
! grep -qF "real hand-edited niri config" "$test_home/.config/niri/overrides.kdl" ||
  fail "refresh-niri must not merge pre-existing config.kdl content into an already-customized overrides.kdl"
bak_file=("$test_home"/.config/niri/config.kdl.bak.*)
[[ -f ${bak_file[0]:-} ]] ||
  fail "refresh-niri backs up pre-existing config.kdl content to a .bak file when overrides.kdl already exists"
grep -qF "real hand-edited niri config" "${bak_file[0]}" ||
  fail "refresh-niri .bak file must contain the pre-existing config.kdl content"
pass "refresh-niri backs up pre-existing config.kdl content to .bak when overrides.kdl already exists"
