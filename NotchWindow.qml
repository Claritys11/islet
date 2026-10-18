import QtQuick
import Quickshell
import Quickshell.Wayland

// Puts the NotchIsland at the top of a screen. Only the island takes input;
// the rest of the window is click-through.
PanelWindow {
    id: win

    required property var modelData
    screen: modelData

    readonly property alias mode: island.mode
    signal settingsRequested

    // Where to hang the island: centre x and top y on this screen, or -1 for
    // the default (centred, notchMarginTop). Bar widgets pass their position
    // so the island drops down right under them.
    property real popX: -1
    property real popY: -1

    function open(t) {
        island.open(t);
    }

    function openAt(t, x, y) {
        popX = x;
        popY = y;
        island.open(t);
    }
    function close() {
        island.close();
    }
    function toggle() {
        island.toggle();
    }

    anchors.top: true
    anchors.left: popX >= 0
    margins.top: popY >= 0 ? popY : Config.opts.notchMarginTop
    margins.left: popX >= 0 ? Math.max(0, Math.min(screen.width - implicitWidth, popX - implicitWidth / 2)) : 0
    implicitWidth: island.implicitWidth
    implicitHeight: island.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "islet-notch"
    WlrLayershell.layer: island.island ? WlrLayer.Top : WlrLayer.Overlay
    WlrLayershell.keyboardFocus: island.mode === "open" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // In bar mode a closed island is invisible and must not catch clicks.
    mask: island.barMode && island.mode === "closed" ? noInput : islandRegion
    Region {
        id: islandRegion
        item: island.shapeItem
    }
    Region {
        id: noInput
    }

    NotchIsland {
        id: island
        anchors.fill: parent
        onSettingsRequested: win.settingsRequested()
    }
}
