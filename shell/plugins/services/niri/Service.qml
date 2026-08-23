import QtQuick
import Quickshell
import Quickshell.Io
import "NiriModel.js" as NiriModel

Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  readonly property string niriSocketPath: Quickshell.env("NIRI_SOCKET") || ""
  readonly property bool active: niriSocketPath !== ""

  property string lastEvent: "init"
  property string lastEventAt: ""

  signal windowOpened(var window)
  signal windowClosed(int id)

  function logEvent(event, details) {
    var suffix = details === undefined || details === null || details === "" ? "" : ": " + String(details)
    root.lastEventAt = new Date().toISOString()
    root.lastEvent = event + suffix
    console.log("omarchy niri " + root.lastEventAt + " " + root.lastEvent)
  }

  // niri serves one request per connection, then closes it. Both sockets
  // need to reconnect after every close (a request/response, or a dropped
  // event stream) as long as the service is still active.
  Timer {
    id: requestReconnectTimer
    interval: 200
    repeat: false
    onTriggered: if (root.active) requestSocket.connected = true
  }

  Timer {
    id: eventReconnectTimer
    interval: 500
    repeat: false
    onTriggered: if (root.active) eventSocket.connected = true
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
        eventReconnectTimer.restart()
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

    onConnectionStateChanged: {
      if (!connected && root.active) {
        root.logEvent("request-socket-disconnected")
        requestReconnectTimer.restart()
      }
    }
  }

  function sendRequest(request) {
    if (!requestSocket.connected) {
      root.logEvent("request-dropped", JSON.stringify(request))
      return
    }
    requestSocket.write(JSON.stringify(request) + "\n")
    requestSocket.flush()
  }

  property var workspaces: []
  property int focusedWorkspaceId: -1
  property string focusedOutputName: ""
  property var occupiedWorkspaceIds: ({})
  property var windowsById: ({})

  function applyWorkspaceList(list) {
    var result = NiriModel.applyWorkspaceList(list, root.occupiedWorkspaceIds)
    root.workspaces = result.workspaces
    root.focusedWorkspaceId = result.focusedWorkspaceId
    root.focusedOutputName = result.focusedOutputName
  }

  function handleWorkspacesChanged(data) {
    root.applyWorkspaceList(data.workspaces || [])
  }

  function handleWorkspaceActivated(data) {
    var result = NiriModel.patchWorkspaceActivated(root.workspaces, data, root.focusedWorkspaceId, root.focusedOutputName)
    root.workspaces = result.workspaces
    root.focusedWorkspaceId = result.focusedWorkspaceId
    root.focusedOutputName = result.focusedOutputName
  }

  function focusWorkspace(id) {
    root.sendRequest({ "Action": { "FocusWorkspace": { "reference": { "Id": id } } } })
  }

  // Workspaces' occupied flags were computed against the old map —
  // refresh them in place without waiting for the next WorkspacesChanged.
  function refreshWorkspaceOccupied() {
    var updated = []
    for (var j = 0; j < root.workspaces.length; j++) {
      var ws = root.workspaces[j]
      updated.push({
        id: ws.id, idx: ws.idx, output: ws.output,
        isActive: ws.isActive, isFocused: ws.isFocused,
        occupied: root.occupiedWorkspaceIds[ws.id] === true
      })
    }
    root.workspaces = updated
  }

  function recomputeOccupiedFromWindows() {
    root.occupiedWorkspaceIds = NiriModel.occupiedIdsFromWindows(root.windowsById)
    root.refreshWorkspaceOccupied()
  }

  // WindowsChanged is the initial snapshot only. It replaces windowsById
  // wholesale; incremental updates arrive afterwards as WindowOpenedOrChanged
  // / WindowClosed and patch windowsById in place (see below).
  function handleWindowsChanged(data) {
    var windows = data.windows || []
    var next = {}
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      if (w && w.id !== undefined) next[w.id] = w
    }
    root.windowsById = next
    root.recomputeOccupiedFromWindows()
  }

  function handleWindowOpenedOrChanged(data) {
    var w = data.window
    if (!w || w.id === undefined) return
    var next = {}
    for (var id in root.windowsById) next[id] = root.windowsById[id]
    next[w.id] = w
    root.windowsById = next
    root.recomputeOccupiedFromWindows()
    root.windowOpened(w)
  }

  function handleWindowClosed(data) {
    if (data.id === undefined) return
    var next = {}
    for (var id in root.windowsById) if (Number(id) !== data.id) next[id] = root.windowsById[id]
    root.windowsById = next
    root.recomputeOccupiedFromWindows()
    root.windowClosed(data.id)
  }

  function handleNiriEvent(event) {
    if (!event) return
    if (event.WorkspacesChanged) { root.handleWorkspacesChanged(event.WorkspacesChanged); return }
    if (event.WorkspaceActivated) { root.handleWorkspaceActivated(event.WorkspaceActivated); return }
    if (event.WindowsChanged) { root.handleWindowsChanged(event.WindowsChanged); return }
    if (event.WindowOpenedOrChanged) { root.handleWindowOpenedOrChanged(event.WindowOpenedOrChanged); return }
    if (event.WindowClosed) { root.handleWindowClosed(event.WindowClosed); return }
    root.logEvent("event", Object.keys(event)[0] || "unknown")
  }

  Component.onCompleted: {
    root.logEvent("service-ready", root.active ? "niri-socket=" + root.niriSocketPath : "inactive")
  }
}
