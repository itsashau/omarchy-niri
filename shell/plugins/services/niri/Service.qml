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

  function handleNiriEvent(event) {
    if (!event) return
    // Task 2 and Task 3 add real handling here.
    root.logEvent("event", Object.keys(event)[0] || "unknown")
  }

  Component.onCompleted: {
    root.logEvent("service-ready", root.active ? "niri-socket=" + root.niriSocketPath : "inactive")
  }
}
