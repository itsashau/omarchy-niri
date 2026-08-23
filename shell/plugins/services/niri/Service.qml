import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  readonly property string niriSocketPath: Quickshell.env("NIRI_SOCKET") || ""
  readonly property bool active: niriSocketPath !== ""

  property string lastEvent: "init"
  property string lastEventAt: ""

  function logEvent(event, details) {
    var suffix = details === undefined || details === null || details === "" ? "" : ": " + String(details)
    root.lastEventAt = new Date().toISOString()
    root.lastEvent = event + suffix
    console.log("omarchy niri " + root.lastEventAt + " " + root.lastEvent)
  }

  Socket {
    id: eventSocket
    path: root.niriSocketPath
    connected: root.active

    onConnectionStateChanged: {
      if (connected) {
        root.logEvent("event-stream-connected")
        write("\"EventStream\"\n")
        flush()
      } else if (root.active) {
        root.logEvent("event-stream-disconnected")
      }
    }

    parser: SplitParser {
      onRead: function(line) {
        var event
        try {
          event = JSON.parse(line)
        } catch (e) {
          root.logEvent("event-parse-failed", line)
          return
        }
        root.handleNiriEvent(event)
      }
    }
  }

  Socket {
    id: requestSocket
    path: root.niriSocketPath
    connected: root.active
  }

  function sendRequest(request) {
    if (!requestSocket.connected) return
    requestSocket.write(JSON.stringify(request) + "\n")
    requestSocket.flush()
  }

  property var workspaces: []
  property int focusedWorkspaceId: -1
  property string focusedOutputName: ""
  property var occupiedWorkspaceIds: ({})

  function normalizeWorkspace(ws) {
    return {
      id: ws.id,
      idx: ws.idx,
      output: ws.output || "",
      isActive: ws.is_active === true,
      isFocused: ws.is_focused === true,
      occupied: root.occupiedWorkspaceIds[ws.id] === true
    }
  }

  function applyWorkspaceList(list) {
    var next = []
    var focusedId = -1
    var focusedOutput = ""
    for (var i = 0; i < list.length; i++) {
      var normalized = root.normalizeWorkspace(list[i])
      next.push(normalized)
      if (normalized.isFocused) {
        focusedId = normalized.id
        focusedOutput = normalized.output
      }
    }
    next.sort(function(a, b) { return a.idx - b.idx })
    root.workspaces = next
    root.focusedWorkspaceId = focusedId
    root.focusedOutputName = focusedOutput
  }

  function handleWorkspacesChanged(data) {
    root.applyWorkspaceList(data.workspaces || [])
  }

  // WorkspaceActivated does not resend the full list — patch is_active
  // (scoped to the affected output) and is_focused (global) locally.
  function handleWorkspaceActivated(data) {
    var activatedId = data.id
    var affectedOutput = ""
    var found = false
    for (var i = 0; i < root.workspaces.length; i++) {
      if (root.workspaces[i].id === activatedId) { affectedOutput = root.workspaces[i].output; found = true; break }
    }
    if (!found) return

    var next = []
    var focusedId = data.focused ? -1 : root.focusedWorkspaceId
    var focusedOutput = data.focused ? "" : root.focusedOutputName
    for (var j = 0; j < root.workspaces.length; j++) {
      var ws = root.workspaces[j]
      var copy = {
        id: ws.id, idx: ws.idx, output: ws.output,
        isActive: ws.output === affectedOutput ? ws.id === activatedId : ws.isActive,
        isFocused: data.focused ? ws.id === activatedId : ws.isFocused,
        occupied: ws.occupied
      }
      if (copy.isFocused) { focusedId = copy.id; focusedOutput = copy.output }
      next.push(copy)
    }
    root.workspaces = next
    root.focusedWorkspaceId = focusedId
    root.focusedOutputName = focusedOutput
  }

  function focusWorkspace(id) {
    root.sendRequest({ "Action": { "FocusWorkspace": { "reference": { "Id": id } } } })
  }

  function recomputeOccupied(windowList) {
    var next = {}
    for (var i = 0; i < windowList.length; i++) {
      var wsId = windowList[i].workspace_id
      if (wsId !== null && wsId !== undefined) next[wsId] = true
    }
    root.occupiedWorkspaceIds = next
    // Workspaces' occupied flags were computed against the old map —
    // refresh them in place without waiting for the next WorkspacesChanged.
    var updated = []
    for (var j = 0; j < root.workspaces.length; j++) {
      var ws = root.workspaces[j]
      updated.push({
        id: ws.id, idx: ws.idx, output: ws.output,
        isActive: ws.isActive, isFocused: ws.isFocused,
        occupied: next[ws.id] === true
      })
    }
    root.workspaces = updated
  }

  function handleWindowsChanged(data) {
    root.recomputeOccupied(data.windows || [])
  }

  function handleNiriEvent(event) {
    if (!event) return
    if (event.WorkspacesChanged) { root.handleWorkspacesChanged(event.WorkspacesChanged); return }
    if (event.WorkspaceActivated) { root.handleWorkspaceActivated(event.WorkspaceActivated); return }
    if (event.WindowsChanged) { root.handleWindowsChanged(event.WindowsChanged); return }
    root.logEvent("event", Object.keys(event)[0] || "unknown")
  }

  Component.onCompleted: {
    root.logEvent("service-ready", root.active ? "niri-socket=" + root.niriSocketPath : "inactive")
  }
}
