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

    function open(t) {
        island.open(t);
    }
    function close() {
        island.close();
    }
    function toggle() {
        island.toggle();
    }

    anchors.top: true
    margins.top: Config.opts.notchMarginTop
    implicitWidth: island.implicitWidth
    implicitHeight: island.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "islet-notch"
    WlrLayershell.layer: island.island ? WlrLayer.Top : WlrLayer.Overlay
    WlrLayershell.keyboardFocus: island.mode === "open" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        item: island.shapeItem
    }

    NotchIsland {
        id: island
        anchors.fill: parent
        onSettingsRequested: win.settingsRequested()
    }
}
