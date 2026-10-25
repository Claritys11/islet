import QtQuick
import Quickshell
import Quickshell.Wayland

// Blurs what is behind its parent (rounded by `radius`) through the
// compositor's background effect (ext-background-effect-v1: niri, KDE,
// Hyprland). Only a request: a compositor without it just doesn't blur.
Item {
    id: root

    property bool active: false
    property real radius: 0
    readonly property var win: QsWindow.window

    anchors.fill: parent
    visible: false

    Region {
        id: region
        item: root
        radius: root.radius
    }

    function apply(): void {
        if (!root.win || !root.win.BackgroundEffect)
            return;
        // Cleared first: the compositor only reads a region it's sent anew.
        root.win.BackgroundEffect.blurRegion = null;
        if (root.active && root.win.visible)
            root.win.BackgroundEffect.blurRegion = region;
    }

    onActiveChanged: settle.restart()
    onWinChanged: settle.restart()
    onWidthChanged: settle.restart()
    onHeightChanged: settle.restart()
    onRadiusChanged: settle.restart()

    Connections {
        target: root.win
        ignoreUnknownSignals: true
        function onVisibleChanged() {
            settle.restart();
        }
        function onWidthChanged() {
            settle.restart();
        }
        function onHeightChanged() {
            settle.restart();
        }
        function onWindowConnected() {
            settle.restart();
        }
    }

    Timer {
        id: settle
        interval: 50
        onTriggered: root.apply()
    }

    Component.onCompleted: settle.restart()
    // The window may already be going too.
    Component.onDestruction: {
        if (root.win && root.win.BackgroundEffect)
            root.win.BackgroundEffect.blurRegion = null;
    }
}
