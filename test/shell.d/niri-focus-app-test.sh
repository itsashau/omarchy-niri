#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/niri" <<'SH'
#!/bin/bash
if [[ $1 == "msg" && $2 == "-j" && $3 == "windows" ]]; then
  printf '%s\n' "$OMARCHY_TEST_WINDOWS_JSON"
elif [[ $1 == "msg" && $2 == "action" && $3 == "focus-window" ]]; then
  printf '%s\n' "$5" >"$OMARCHY_TEST_FOCUS_ID"
fi
SH
chmod +x "$mock_bin/niri"

focus_log="$test_tmp/focus-id"
windows_json='[{"id":1,"app_id":"chromium","title":"Inbox"}]'
PATH="$mock_bin:$PATH" OMARCHY_TEST_WINDOWS_JSON="$windows_json" \
  OMARCHY_TEST_FOCUS_ID="$focus_log" \
  bash "$ROOT/bin/omarchy-niri-focus-app" '^chromium$'

grep -F '1' "$focus_log" >/dev/null || \
  fail "app focus matches by app_id and focuses the window id"

pass "app focus matches an existing window by app_id"

windows_json='[
  {"id":2,"app_id":"com.viber.Viber","title":"Viber"},
  {"id":3,"app_id":"org.omarchy.agent","title":"kitty"}
]'
PATH="$mock_bin:$PATH" OMARCHY_TEST_WINDOWS_JSON="$windows_json" \
  OMARCHY_TEST_FOCUS_ID="$focus_log" \
  bash "$ROOT/bin/omarchy-niri-focus-app" kitty

grep -F '3' "$focus_log" >/dev/null || \
  fail "app focus falls back to the current title for agent terminals"

pass "app focus finds terminals sharing the agent app_id"

windows_json='[{"id":4,"app_id":"chromium","title":"Mail settings"}]'
rm -f "$focus_log"
if PATH="$mock_bin:$PATH" OMARCHY_TEST_WINDOWS_JSON="$windows_json" \
  OMARCHY_TEST_FOCUS_ID="$focus_log" \
  bash "$ROOT/bin/omarchy-niri-focus-app" Mail; then
  fail "app focus rejects title matches from non-agent windows"
fi

[[ ! -e $focus_log ]] || fail "app focus leaves focus unchanged for unrelated title matches"

pass "app focus restricts title matching to agent terminals"
