function normalizeWorkspace(ws, occupiedWorkspaceIds) {
  return {
    id: ws.id,
    idx: ws.idx,
    output: ws.output || "",
    isActive: ws.is_active === true,
    isFocused: ws.is_focused === true,
    occupied: occupiedWorkspaceIds[ws.id] === true
  }
}

function applyWorkspaceList(list, occupiedWorkspaceIds) {
  var next = []
  var focusedId = -1
  var focusedOutput = ""
  for (var i = 0; i < list.length; i++) {
    var normalized = normalizeWorkspace(list[i], occupiedWorkspaceIds)
    next.push(normalized)
    if (normalized.isFocused) {
      focusedId = normalized.id
      focusedOutput = normalized.output
    }
  }
  next.sort(function(a, b) { return a.idx - b.idx })
  return { workspaces: next, focusedWorkspaceId: focusedId, focusedOutputName: focusedOutput }
}

// WorkspaceActivated does not resend the full list — patch is_active
// (scoped to the affected output) and is_focused (global) locally.
// Returns the input workspaces/focus unchanged if data.id names a workspace
// we don't know about (a stale event should never clobber known-good state).
function patchWorkspaceActivated(workspaces, data, focusedWorkspaceId, focusedOutputName) {
  var activatedId = data.id
  var affectedOutput = ""
  var found = false
  for (var i = 0; i < workspaces.length; i++) {
    if (workspaces[i].id === activatedId) { affectedOutput = workspaces[i].output; found = true; break }
  }
  if (!found) return { workspaces: workspaces, focusedWorkspaceId: focusedWorkspaceId, focusedOutputName: focusedOutputName }

  var next = []
  var focusedId = data.focused ? -1 : focusedWorkspaceId
  var focusedOutput = data.focused ? "" : focusedOutputName
  for (var j = 0; j < workspaces.length; j++) {
    var ws = workspaces[j]
    var copy = {
      id: ws.id, idx: ws.idx, output: ws.output,
      isActive: ws.output === affectedOutput ? ws.id === activatedId : ws.isActive,
      isFocused: data.focused ? ws.id === activatedId : ws.isFocused,
      occupied: ws.occupied
    }
    if (copy.isFocused) { focusedId = copy.id; focusedOutput = copy.output }
    next.push(copy)
  }
  return { workspaces: next, focusedWorkspaceId: focusedId, focusedOutputName: focusedOutput }
}

function occupiedIdsFromWindows(windowsById) {
  var next = {}
  for (var id in windowsById) {
    var w = windowsById[id]
    if (w && w.workspace_id !== null && w.workspace_id !== undefined) next[w.workspace_id] = true
  }
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeWorkspace: normalizeWorkspace,
    applyWorkspaceList: applyWorkspaceList,
    patchWorkspaceActivated: patchWorkspaceActivated,
    occupiedIdsFromWindows: occupiedIdsFromWindows
  }
}
