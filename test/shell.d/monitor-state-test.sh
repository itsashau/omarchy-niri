#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_bin=$(mktemp -d)
monitors_file=$(mktemp)

cleanup() {
  rm -rf "$test_bin"
  rm -f "$monitors_file"
}
trap cleanup EXIT

cat >"$test_bin/hyprctl" <<'EOF'
#!/bin/bash
[[ $* == "monitors all -j" ]] || exit 1
cat "$FAKE_MONITORS"
EOF

cat >"$test_bin/omarchy-brightness-display" <<'EOF'
#!/bin/bash
echo 42
EOF

cat >"$test_bin/omarchy-hyprland-monitor-scaling" <<'EOF'
#!/bin/bash
echo 1.5
EOF

chmod +x "$test_bin"/*

# The panel reads this output by line index, so every case has to answer with
# the same number of lines. A helper that dies mid-script drops its line and
# silently shifts every field below it into the wrong property.
state_lines=()
monitor_state() {
  printf '%s\n' "$1" >"$monitors_file"

  mapfile -t state_lines < <(
    FAKE_MONITORS="$monitors_file" PATH="$test_bin:$PATH" \
      bash "$ROOT/bin/omarchy-monitor-state" 2>/dev/null
  )
}

assert_line() {
  local index="$1" expected="$2" description="$3"

  [[ ${state_lines[index]-} == "$expected" ]] ||
    fail "$description" "line $index expected: $expected"$'\n'"line $index actual:   ${state_lines[index]-<missing>}"
}

assert_line_count() {
  local description="$1"

  (( ${#state_lines[@]} == 8 )) ||
    fail "$description" "expected 8 lines, got ${#state_lines[@]}"
}

extended='[
  { "name": "eDP-1", "mirrorOf": "none", "disabled": false, "focused": false, "width": 1920, "height": 1080 },
  { "name": "DP-1", "mirrorOf": "none", "disabled": false, "focused": true, "width": 2560, "height": 1440 }
]'

# Omarchy mirrors by pointing the external at the internal, so `mirrorOf` lands
# on the external and the internal keeps saying "none".
mirrored='[
  { "name": "eDP-1", "mirrorOf": "none", "disabled": false, "focused": true, "width": 1920, "height": 1080 },
  { "name": "DP-1", "mirrorOf": "eDP-1", "disabled": false, "focused": false, "width": 1920, "height": 1080 }
]'

# A monitors.lua of the user's own can mirror the other way instead.
reverse_mirrored='[
  { "name": "eDP-1", "mirrorOf": "DP-1", "disabled": false, "focused": false, "width": 2560, "height": 1440 },
  { "name": "DP-1", "mirrorOf": "none", "disabled": false, "focused": true, "width": 2560, "height": 1440 }
]'

clamshell='[
  { "name": "eDP-1", "mirrorOf": "none", "disabled": true, "focused": false, "width": 0, "height": 0 },
  { "name": "DP-1", "mirrorOf": "none", "disabled": false, "focused": true, "width": 2560, "height": 1440 }
]'

monitor_state "$extended"
assert_line_count "monitor state answers every line while extended"
assert_line 0 42 "monitor state reports brightness"
assert_line 1 eDP-1 "monitor state names the internal monitor"
assert_line 2 DP-1 "monitor state names the external monitor"
assert_line 3 eDP-1 "monitor state reports the internal monitor enabled"
assert_line 4 "" "monitor state reports no mirror while extended"
assert_line 5 DP-1 "monitor state reports the focused monitor"
assert_line 6 1.5 "monitor state reports the scale"
pass "monitor state keeps its lines aligned when nothing is mirrored"

monitor_state "$mirrored"
assert_line_count "monitor state answers every line while mirroring"
assert_line 4 DP-1 "monitor state names the mirroring external monitor"
assert_line 5 eDP-1 "monitor state still reports the focused monitor while mirroring"
pass "monitor state reports the external monitor when it mirrors the internal"

monitor_state "$reverse_mirrored"
assert_line_count "monitor state answers every line while mirroring in reverse"
assert_line 4 DP-1 "monitor state names the external monitor either way round"
pass "monitor state reports the external monitor when the internal mirrors it"

monitor_state "$clamshell"
assert_line_count "monitor state answers every line while clamshelled"
assert_line 1 eDP-1 "monitor state still names a disabled internal monitor"
assert_line 3 "" "monitor state reports the internal monitor disabled"
assert_line 4 "" "monitor state reports no mirror while clamshelled"
pass "monitor state separates a disabled internal monitor from a missing one"

monitor_state "$extended"
[[ ${state_lines[7]-} == '[{"name":"eDP-1","enabled":true,"focused":false,"width":1920,"height":1080},{"name":"DP-1","enabled":true,"focused":true,"width":2560,"height":1440}]' ]] ||
  fail "monitor state lists every display for the panel" "actual: ${state_lines[7]-<missing>}"
monitor_state "$clamshell"
[[ ${state_lines[7]-} == '[{"name":"eDP-1","enabled":false,"focused":false,"width":0,"height":0},{"name":"DP-1","enabled":true,"focused":true,"width":2560,"height":1440}]' ]] ||
  fail "monitor state lists every display for the panel" "actual: ${state_lines[7]-<missing>}"
pass "monitor state lists every display with its enabled and focused state"

niri_test_bin=$(mktemp -d)
niri_monitors_file=$(mktemp)

niri_cleanup() {
  rm -rf "$niri_test_bin"
  rm -f "$niri_monitors_file"
}
trap niri_cleanup EXIT

cat >"$niri_test_bin/niri" <<'EOF'
#!/bin/bash
if [[ $1 == "msg" && $2 == "-j" && $3 == "outputs" ]]; then
  cat "$FAKE_NIRI_OUTPUTS"
elif [[ $1 == "msg" && $2 == "-j" && $3 == "focused-output" ]]; then
  cat "$FAKE_NIRI_FOCUSED"
fi
EOF

cat >"$niri_test_bin/omarchy-brightness-display" <<'EOF'
#!/bin/bash
echo 42
EOF

chmod +x "$niri_test_bin"/*

niri_state_lines=()
niri_monitor_state() {
  local outputs="$1" focused="$2"

  mapfile -t niri_state_lines < <(
    FAKE_NIRI_OUTPUTS=<(printf '%s' "$outputs") \
      FAKE_NIRI_FOCUSED=<(printf '%s' "$focused") \
      NIRI_SOCKET=/tmp/fake-niri.sock \
      PATH="$niri_test_bin:$PATH" \
      bash "$ROOT/bin/omarchy-monitor-state" 2>/dev/null
  )
}

niri_assert_line() {
  local index="$1" expected="$2" description="$3"

  [[ ${niri_state_lines[index]-} == "$expected" ]] ||
    fail "$description" "line $index expected: $expected"$'\n'"line $index actual:   ${niri_state_lines[index]-<missing>}"
}

niri_assert_line_count() {
  local description="$1"

  (( ${#niri_state_lines[@]} == 8 )) ||
    fail "$description" "expected 8 lines, got ${#niri_state_lines[@]}"
}

niri_extended='{
  "eDP-1": { "name": "eDP-1", "current_mode": 0, "modes": [{"width": 1920, "height": 1080, "refresh_rate": 60000, "is_preferred": true}], "logical": {"x": 0, "y": 0, "width": 1920, "height": 1080, "scale": 1.0, "transform": "Normal"} },
  "DP-1": { "name": "DP-1", "current_mode": 0, "modes": [{"width": 2560, "height": 1440, "refresh_rate": 60000, "is_preferred": true}], "logical": {"x": 1920, "y": 0, "width": 2560, "height": 1440, "scale": 1.5, "transform": "Normal"} }
}'
niri_extended_focused='{ "name": "DP-1", "current_mode": 0, "modes": [{"width": 2560, "height": 1440, "refresh_rate": 60000, "is_preferred": true}], "logical": {"x": 1920, "y": 0, "width": 2560, "height": 1440, "scale": 1.5, "transform": "Normal"} }'

niri_monitor_state "$niri_extended" "$niri_extended_focused"
niri_assert_line_count "niri monitor state answers every line while extended"
niri_assert_line 0 42 "niri monitor state reports brightness"
niri_assert_line 1 eDP-1 "niri monitor state names the internal monitor"
niri_assert_line 2 DP-1 "niri monitor state names the external monitor"
niri_assert_line 3 eDP-1 "niri monitor state reports the internal monitor enabled"
niri_assert_line 4 "" "niri monitor state always reports no mirror"
niri_assert_line 5 DP-1 "niri monitor state reports the focused monitor"
niri_assert_line 6 1.5 "niri monitor state reports the scale"
pass "niri monitor state keeps its lines aligned when extended"

niri_clamshell='{
  "eDP-1": { "name": "eDP-1", "current_mode": null, "modes": [{"width": 1920, "height": 1080, "refresh_rate": 60000, "is_preferred": true}], "logical": null },
  "DP-1": { "name": "DP-1", "current_mode": 0, "modes": [{"width": 2560, "height": 1440, "refresh_rate": 60000, "is_preferred": true}], "logical": {"x": 0, "y": 0, "width": 2560, "height": 1440, "scale": 1.0, "transform": "Normal"} }
}'
niri_clamshell_focused='{ "name": "DP-1", "current_mode": 0, "modes": [{"width": 2560, "height": 1440, "refresh_rate": 60000, "is_preferred": true}], "logical": {"x": 0, "y": 0, "width": 2560, "height": 1440, "scale": 1.0, "transform": "Normal"} }'

niri_monitor_state "$niri_clamshell" "$niri_clamshell_focused"
niri_assert_line_count "niri monitor state answers every line while clamshelled"
niri_assert_line 1 eDP-1 "niri monitor state still names a disabled internal monitor"
niri_assert_line 3 "" "niri monitor state reports the internal monitor disabled"
niri_assert_line 4 "" "niri monitor state always reports no mirror while clamshelled"
pass "niri monitor state separates a disabled internal monitor from a missing one"

niri_monitor_state "$niri_extended" "$niri_extended_focused"
[[ ${niri_state_lines[7]-} == '[{"name":"eDP-1","enabled":true,"focused":false,"width":1920,"height":1080},{"name":"DP-1","enabled":true,"focused":true,"width":2560,"height":1440}]' ]] ||
  fail "niri monitor state lists every display for the panel" "actual: ${niri_state_lines[7]-<missing>}"
niri_monitor_state "$niri_clamshell" "$niri_clamshell_focused"
[[ ${niri_state_lines[7]-} == '[{"name":"eDP-1","enabled":false,"focused":false,"width":0,"height":0},{"name":"DP-1","enabled":true,"focused":true,"width":2560,"height":1440}]' ]] ||
  fail "niri monitor state lists every display for the panel" "actual: ${niri_state_lines[7]-<missing>}"
pass "niri monitor state lists every display with its enabled and focused state"

niri_no_focus='{ "eDP-1": { "name": "eDP-1", "current_mode": null, "modes": [], "logical": null } }'
niri_monitor_state "$niri_no_focus" "null"
niri_assert_line_count "niri monitor state answers every line with no focused output"
niri_assert_line 5 "" "niri monitor state reports no focused monitor when none exists"
niri_assert_line 6 "" "niri monitor state reports no scale when nothing is focused"
pass "niri monitor state degrades cleanly when no output is focused"
