import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property color borderColor: Color.popups.border
  property var borderSpec: Border.localOrSurfaceSpec("popups", "border", borderColor, Color.popups.border, Math.max(1, Style.space(2)))
  property bool open: false
  property bool centerOnBar: false
  // "click" — uses HyprlandFocusGrab (Hyprland) or a same-surface dismiss
  // overlay (Niri) so clicking outside dismisses the popup.
  // "hover" — passive overlay; the owning widget controls open via hover.
  property string triggerMode: "click"

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property bool containsMouse: Compositor.isNiri ? niriCardHover.hovered : cardHover.hovered
  readonly property real screenW: popupScreen ? popupScreen.width : 0
  readonly property real screenH: popupScreen ? popupScreen.height : 0
  readonly property real barW: anchorWindow ? anchorWindow.width : 0
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((bar && (bar.position === "left" || bar.position === "right")) ? barW : 0) - root.margin * 2)
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((bar && (bar.position === "top" || bar.position === "bottom")) ? barH : 0) - root.margin * 2)
    : 0
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  // Mirrors whichever surface is actually active so a consumer's
  // `onVisibleChanged` (e.g. Tray.qml's trayMenuPopup, which waits for the
  // fade-out to finish before resetting submenu state) keeps working the
  // same way it did when PopupCard's root was the PopupWindow/PanelWindow
  // itself and this property was that window's real visibility.
  visible: Compositor.isNiri ? niriPopup.visible : hyprPopup.visible

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    return Math.round(Math.min(desired, maxHeight))
  }

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  // The consumer's child content is declared once and reparented, at
  // startup only, into whichever card is actually active. Safe because
  // Compositor.isNiri is fixed for the process lifetime — it never
  // toggles at runtime, so this is a one-time decision, not a dynamic one.
  default property alias contentItem: contentEnvelope.children
  Item { id: contentEnvelope }

  Component.onCompleted: {
    var target = Compositor.isNiri ? niriContentHolder : hyprContentHolder
    contentEnvelope.parent = target
    contentEnvelope.anchors.fill = target
  }

  onOpenChanged: {
    if (!bar) return
    if (open) bar.requestPopout(coordinatorKey)
    else if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
  }

  // ---------------------------------------------------------- Hyprland path

  PopupWindow {
    id: hyprPopup
    visible: !Compositor.isNiri && (root.open || hyprCard.opacity > 0)
    color: "transparent"
    implicitWidth: root.contentWidth
    implicitHeight: root.contentHeight

    // Outside-click dismissal via Hyprland's focus grab. While `active`, input
    // is routed only to the listed windows; clicking anywhere else clears the
    // grab and we close the popup. Skipped for hover-mode popups so the cursor
    // can move freely between the trigger and the popup.
    HyprlandFocusGrab {
      active: root.open && root.triggerMode === "click" && !Compositor.isNiri
      windows: root.anchorWindow ? [hyprPopup, root.anchorWindow] : [hyprPopup]
      onCleared: root.close()
    }

    anchor {
      id: popupAnchor
      window: root.anchorItem ? root.anchorItem.QsWindow.window : null
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        if (!root.anchorItem || !root.bar) return

        var target = root.anchorItem
        var popupWidth = hyprPopup.implicitWidth
        var popupHeight = hyprPopup.implicitHeight
        var localX = target.width / 2 - popupWidth / 2
        var localY = target.height + root.margin

        if (root.bar.position === "bottom") {
          localY = -popupHeight - root.margin
        } else if (root.bar.position === "left") {
          localX = target.width + root.margin
          localY = target.height / 2 - popupHeight / 2
        } else if (root.bar.position === "right") {
          localX = -popupWidth - root.margin
          localY = target.height / 2 - popupHeight / 2
        }

        var window = target.QsWindow.window
        if (!window) return

        if (root.centerOnBar) {
          var cx = 0;
          var cy = 0;
          if (root.bar.position === "top" || root.bar.position === "bottom") {
            cx = window.width / 2 - popupWidth / 2
            cy = root.bar.position === "bottom" ? -popupHeight - root.margin : window.height + root.margin
            cx = Math.max(root.margin, Math.min(cx, window.width - popupWidth - root.margin))
          } else {
            cx = root.bar.position === "left" ? window.width + root.margin : -popupWidth - root.margin
            cy = window.height / 2 - popupHeight / 2
            cy = Math.max(root.margin, Math.min(cy, window.height - popupHeight - root.margin))
          }

          popupAnchor.rect.x = Math.round(cx)
          popupAnchor.rect.y = Math.round(cy)
          return
        }

        var point = window.contentItem.mapFromItem(target, localX, localY)

        if (root.bar.position === "top" || root.bar.position === "bottom") {
          point.x = Math.max(root.margin, Math.min(point.x, window.width - popupWidth - root.margin))
        } else {
          point.y = Math.max(root.margin, Math.min(point.y, window.height - popupHeight - root.margin))
        }

        popupAnchor.rect.x = Math.round(point.x)
        popupAnchor.rect.y = Math.round(point.y)
      }
    }

    BorderSurface {
      id: hyprCard
      anchors.fill: parent
      color: Color.popups.background
      borderSpec: root.borderSpec
      padding: root.padding
      radius: Style.cornerRadius
      opacity: root.open ? 1.0 : 0

      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }

      Item {
        id: hyprContentHolder
        anchors.fill: parent
        anchors.topMargin: hyprCard.contentTopInset
        anchors.rightMargin: hyprCard.contentRightInset
        anchors.bottomMargin: hyprCard.contentBottomInset
        anchors.leftMargin: hyprCard.contentLeftInset
      }

      HoverHandler {
        id: cardHover
      }
    }
  }

  // -------------------------------------------------------------- Niri path
  //
  // Niri has no HyprlandFocusGrab equivalent. Rather than a separate
  // click-catching surface (which stacks below/above the popup ambiguously
  // depending on layer-shell rules), the card and the dismiss overlay are
  // the SAME surface here — the same principle shell/Ui/KeyboardPanel.qml
  // already relies on. This sidesteps any stacking-order question entirely:
  // a click on the card is caught by the card's own MouseArea (swallowed
  // before it reaches the full-screen dismiss MouseArea behind it), and a
  // click anywhere else in this same surface closes the popup. No manual
  // click-forwarding is needed for the bar strip: a real Region/Subtract
  // mask punches a genuine Wayland click-through hole there, safe because
  // this never requests Exclusive keyboard focus (the thing that makes
  // Hyprland hijack compositor-wide pointer routing, which is what forces
  // KeyboardPanel.qml to forward clicks manually instead).

  PanelWindow {
    id: niriPopup
    visible: Compositor.isNiri && (root.open || niriCard.opacity > 0)
    screen: root.popupScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

    readonly property string barPos: root.bar ? root.bar.position : "top"
    readonly property int barSize: root.bar ? root.bar.barSize : 0
    readonly property bool barVertical: barPos === "left" || barPos === "right"

    mask: Region {
      width: niriPopup.width
      height: niriPopup.height

      Region {
        intersection: Intersection.Subtract
        x: niriPopup.barPos === "right" ? niriPopup.width - niriPopup.barSize : 0
        y: niriPopup.barPos === "bottom" ? niriPopup.height - niriPopup.barSize : 0
        width: niriPopup.barVertical ? niriPopup.barSize : niriPopup.width
        height: niriPopup.barVertical ? niriPopup.height : niriPopup.barSize
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      enabled: root.open
      onClicked: root.close()
    }

    // Reactive to the anchor moving along the bar (e.g. a widget's drawer
    // reveal, a neighbouring widget resizing) — mapToItem alone is a
    // one-shot and wouldn't re-fire on its own. Same technique
    // KeyboardPanel.qml uses for its own full-screen-surface positioning.
    TransformWatcher {
      id: anchorWatcher
      a: root.anchorWindow ? root.anchorWindow.contentItem : null
      b: root.anchorItem
    }

    readonly property point anchorScreenPos: {
      anchorWatcher.transform // reactive dependency
      if (!root.anchorItem || !root.anchorWindow) return Qt.point(0, 0)
      return root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0)
    }
    readonly property real anchorW: root.anchorItem ? root.anchorItem.width : 0
    readonly property real anchorH: root.anchorItem ? root.anchorItem.height : 0

    readonly property point cardOrigin: {
      if (!root.anchorItem || !root.bar || !root.anchorWindow) return Qt.point(root.margin, root.margin)

      var popupWidth = root.contentWidth
      var popupHeight = root.contentHeight
      var barPos = root.bar.position
      var x = 0, y = 0

      if (root.centerOnBar && (barPos === "top" || barPos === "bottom")) {
        x = root.screenW / 2 - popupWidth / 2
        y = barPos === "bottom" ? root.screenH - root.barH - popupHeight - root.margin : root.barH + root.margin
      } else if (root.centerOnBar) {
        x = barPos === "left" ? root.barW + root.margin : root.screenW - root.barW - popupWidth - root.margin
        y = root.screenH / 2 - popupHeight / 2
      } else if (barPos === "bottom") {
        x = niriPopup.anchorScreenPos.x + niriPopup.anchorW / 2 - popupWidth / 2
        y = root.screenH - root.barH - popupHeight - root.margin
      } else if (barPos === "left") {
        x = root.barW + root.margin
        y = niriPopup.anchorScreenPos.y + niriPopup.anchorH / 2 - popupHeight / 2
      } else if (barPos === "right") {
        x = root.screenW - root.barW - popupWidth - root.margin
        y = niriPopup.anchorScreenPos.y + niriPopup.anchorH / 2 - popupHeight / 2
      } else { // "top" (default)
        x = niriPopup.anchorScreenPos.x + niriPopup.anchorW / 2 - popupWidth / 2
        y = root.barH + root.margin
      }

      x = Math.max(root.margin, Math.min(x, root.screenW - popupWidth - root.margin))
      y = Math.max(root.margin, Math.min(y, root.screenH - popupHeight - root.margin))
      return Qt.point(Math.round(x), Math.round(y))
    }

    BorderSurface {
      id: niriCard
      x: niriPopup.cardOrigin.x
      y: niriPopup.cardOrigin.y
      width: root.contentWidth
      height: root.contentHeight
      color: Color.popups.background
      borderSpec: root.borderSpec
      padding: root.padding
      radius: Style.cornerRadius
      opacity: root.open ? 1.0 : 0

      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }

      // Swallow clicks on the card so they don't fall through to the
      // full-screen dismiss MouseArea behind it.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }

      Item {
        id: niriContentHolder
        anchors.fill: parent
        anchors.topMargin: niriCard.contentTopInset
        anchors.rightMargin: niriCard.contentRightInset
        anchors.bottomMargin: niriCard.contentBottomInset
        anchors.leftMargin: niriCard.contentLeftInset
      }

      HoverHandler {
        id: niriCardHover
      }
    }
  }

  // Other-output twins (Niri only): plain click-catchers, no bar-strip
  // exclusion needed since there's no card to protect on these screens, and
  // today's Hyprland behavior (HyprlandFocusGrab) also treats a click on a
  // different monitor's bar as an "outside" click that dismisses.
  Variants {
    model: (root.open && root.triggerMode === "click" && Compositor.isNiri && root.popupScreen)
      ? Quickshell.screens.filter(function(s) { return s.name !== root.popupScreen.name })
      : []

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        visible: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-popup-dismiss-twin"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors { top: true; bottom: true; left: true; right: true }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onClicked: root.close()
        }
      }
    }
  }
}
