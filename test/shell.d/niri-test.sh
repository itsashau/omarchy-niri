#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const niri = requireFromRoot('shell/plugins/services/niri/NiriModel.js')

const listResult = niri.applyWorkspaceList([
  { id: 1, idx: 1, output: "eDP-1", is_active: true, is_focused: false },
  { id: 2, idx: 2, output: "eDP-1", is_active: false, is_focused: true },
  { id: 3, idx: 1, output: "HDMI-1", is_active: true, is_focused: false }
], {})
assertEqual(listResult.focusedWorkspaceId, 2, 'applyWorkspaceList picks the focused workspace id')
assertEqual(listResult.focusedOutputName, 'eDP-1', 'applyWorkspaceList picks the focused workspace output')

// Scenario B: two outputs, focus switches to a workspace on the
// non-focused output. is_active is scoped per-output; is_focused is global.
const twoOutputWorkspaces = niri.applyWorkspaceList([
  { id: 1, idx: 1, output: "eDP-1", is_active: true, is_focused: true },
  { id: 2, idx: 1, output: "HDMI-1", is_active: true, is_focused: false },
  { id: 3, idx: 2, output: "HDMI-1", is_active: false, is_focused: false }
], {}).workspaces

const activated = niri.patchWorkspaceActivated(twoOutputWorkspaces, { id: 3, focused: true }, 1, "eDP-1")
assertEqual(activated.focusedWorkspaceId, 3, 'patchWorkspaceActivated moves global focus to the activated workspace')
assertEqual(activated.focusedOutputName, 'HDMI-1', 'patchWorkspaceActivated moves global focus to the activated output')

const wsById = {}
for (const ws of activated.workspaces) wsById[ws.id] = ws
assertEqual(wsById[1].isActive, true, 'patchWorkspaceActivated leaves the unaffected output\'s active workspace alone')
assertEqual(wsById[1].isFocused, false, 'patchWorkspaceActivated clears focus on the previously-focused workspace')
assertEqual(wsById[2].isActive, false, 'patchWorkspaceActivated deactivates the old active workspace on the affected output')
assertEqual(wsById[3].isActive, true, 'patchWorkspaceActivated activates the newly-activated workspace')
assertEqual(wsById[3].isFocused, true, 'patchWorkspaceActivated focuses the newly-activated workspace')

// Regression test for the bug fixed in commit e890e8ab: a stale/unknown
// workspace id must never corrupt existing state, even with focused: true.
const staleInput = niri.applyWorkspaceList([
  { id: 1, idx: 1, output: "eDP-1", is_active: true, is_focused: true }
], {})
const staleResult = niri.patchWorkspaceActivated(staleInput.workspaces, { id: 999, focused: true }, staleInput.focusedWorkspaceId, staleInput.focusedOutputName)
assertDeepEqual(staleResult.workspaces, staleInput.workspaces, 'patchWorkspaceActivated leaves workspaces unchanged for a stale id')
assertEqual(staleResult.focusedWorkspaceId, staleInput.focusedWorkspaceId, 'patchWorkspaceActivated leaves focusedWorkspaceId unchanged for a stale id')
assertEqual(staleResult.focusedOutputName, staleInput.focusedOutputName, 'patchWorkspaceActivated leaves focusedOutputName unchanged for a stale id')

const occupied = niri.occupiedIdsFromWindows({
  10: { id: 10, workspace_id: 1 },
  11: { id: 11, workspace_id: 2 },
  12: { id: 12, workspace_id: 1 },
  13: { id: 13 }
})
assertDeepEqual(occupied, { 1: true, 2: true }, 'occupiedIdsFromWindows maps windows to their workspace ids, ignoring windows without one')
JS
