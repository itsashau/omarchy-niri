import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  readonly property var niriService: root.bar && root.bar.shell ? root.bar.shell.firstPartyServiceFor("omarchy.niri") : null
  readonly property bool niriActive: !!(niriService && niriService.active)

  function workspaceById(id) {
    if (niriActive) {
      var list = niriService.workspaces
      for (var n = 0; n < list.length; n++) {
        if (list[n].id === id) return list[n]
      }
      return null
    }
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceIds() {
    if (niriActive) {
      var ids = []
      var list = niriService.workspaces
      for (var n = 0; n < list.length; n++) ids.push(list[n].id)
      return ids
    }
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    if (niriActive) { niriService.focusWorkspace(id); return }
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: root.niriActive
          ? (workspace !== null && workspace.occupied === true)
          : (workspace !== null && workspace.toplevels.values.length > 0)
        readonly property bool focused: root.niriActive
          ? (workspace !== null && workspace.isFocused === true)
          : (Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData)

        bar: root.bar
        text: focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
