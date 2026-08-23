pragma Singleton

import QtQuick
import Quickshell

// Which compositor this shell process is running under, detected the same
// way the rest of the fork does: $NIRI_SOCKET is only ever set by niri.
QtObject {
  readonly property bool isNiri: Quickshell.env("NIRI_SOCKET") !== "" && Quickshell.env("NIRI_SOCKET") !== undefined
}
