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
    readonly property alias away: island.away
    readonly property alias vizWanted: island.vizWanted
    readonly property alias hotkey: island.hotkey
    readonly property alias closesOnClickOutside: island.closesOnClickOutside
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
    function find(prefill) {
        island.find(prefill);
    }
    function summon() {
        island.summon();
    }
    function toggle() {
        island.toggle();
    }
    function toggleViz() {
        island.toggleViz();
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
    // Above its click-catcher (shell.qml), which is on Top.
    WlrLayershell.layer: island.island && !island.closesOnClickOutside && !island.hotkey ? WlrLayer.Top : WlrLayer.Overlay
    // Finder, the Finder key and a notch opened by a click take the keyboard
    // at once, so you can type (or ← → through the tabs) straight away. A
    // pinned notch doesn't: you keep typing elsewhere.
    WlrLayershell.keyboardFocus: island.mode === "find" || (island.mode === "open" && (island.hotkey || island.closesOnClickOutside)) ? WlrKeyboardFocus.Exclusive : island.mode === "open" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

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
