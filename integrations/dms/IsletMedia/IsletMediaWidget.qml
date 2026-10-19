import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Islet in the DankMaterialShell bar. Islet runs separately and streams its
// state over $XDG_RUNTIME_DIR/islet.sock; this pill only displays it and
// sends clicks back. Left click opens Islet's island under the pill, right
// click plays/pauses.
PluginComponent {
    id: root

    layerNamespacePlugin: "islet-media"

    // Latest state from Islet (see IsletLink.qml in the Islet repo).
    property var st: null
    readonly property bool linked: link.connected && st !== null
    readonly property bool hasTrack: linked && st.hasTrack
    readonly property bool hasTimer: linked && st.timer !== null && (st.bar?.timer ?? true)
    readonly property string text: !hasTrack ? "" : st.line !== "" && st.bar?.text !== "title" ? st.line : `${st.title}  ·  ${st.artist}`
    readonly property bool isLyric: hasTrack && st.line !== "" && st.bar?.text !== "title"

    function send(msg) {
        if (!link.connected)
            return;
        link.write(JSON.stringify(msg) + "\n");
        link.flush();
    }

    pillClickAction: (x, y, width, section, screen) => send({ cmd: "toggle", tab: hasTrack ? "media" : "focus", x, y, width })
    pillRightClickAction: () => send({ cmd: "play-pause" })

    Socket {
        id: link
        path: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/islet.sock`
        connected: true
        parser: SplitParser {
            onRead: line => {
                try {
                    root.st = JSON.parse(line);
                } catch (e) {}
            }
        }
        onConnectedChanged: if (!connected)
            root.st = null
    }

    // Islet not running (yet)? Keep knocking.
    Timer {
        running: !link.connected
        repeat: true
        interval: 2000
        onTriggered: link.connected = true
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            // Islet isn't running: a quiet hint instead of an empty gap.
            DankIcon {
                visible: !root.linked
                anchors.verticalCenter: parent.verticalCenter
                name: "lyrics"
                size: Theme.iconSize - 4
                color: Theme.surfaceVariantText
            }

            ClippingRectangle {
                visible: root.hasTrack
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(root.widgetThickness * 0.62)
                height: width
                radius: width / 2
                color: Theme.surfaceContainerHigh

                Image {
                    anchors.fill: parent
                    source: root.st?.art ?? ""
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }
            }

            // The lyric with its karaoke fill: a dim copy, and a bright copy
            // revealed as the line is sung. Long lines are cut off and slide
            // along with the singer instead of ending in "…".
            Item {
                id: lyric
                visible: root.hasTrack
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(base.implicitWidth, root.st?.bar?.width ?? 300)
                height: base.implicitHeight
                clip: true

                readonly property real overflow: Math.max(0, base.implicitWidth - width)
                readonly property real progress: root.isLyric ? (root.st?.progress ?? 0) : 1
                property real shift: root.isLyric ? overflow * Math.max(0, Math.min(1, (progress - 0.2) / 0.6)) : 0

                Behavior on shift {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.OutCubic
                    }
                }

                StyledText {
                    id: base
                    x: -lyric.shift
                    text: root.text
                    color: Theme.surfaceText
                    opacity: root.isLyric ? 0.5 : 0.9
                    font.pixelSize: Theme.fontSizeMedium
                }

                Item {
                    visible: root.isLyric
                    x: -lyric.shift
                    width: base.implicitWidth * lyric.progress
                    height: base.height
                    clip: true

                    Behavior on width {
                        NumberAnimation {
                            duration: 60
                        }
                    }

                    StyledText {
                        text: root.text
                        color: Theme.primary
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                    }
                }
            }

            Row {
                visible: root.hasTrack && (root.st?.bar?.viz ?? true)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: root.st?.viz ?? []
                    Rectangle {
                        required property real modelData
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: Math.max(3, modelData * root.widgetThickness * 0.5)
                        radius: 1.5
                        color: Theme.primary
                        Behavior on height {
                            NumberAnimation {
                                duration: 80
                            }
                        }
                    }
                }
            }

            Row {
                visible: root.hasTimer
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.st?.timer?.paused ? "pause_circle" : "timer"
                    size: Theme.iconSize - 6
                    color: root.st?.timer?.mode === "focus" ? Theme.primary : Theme.surfaceText
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.st?.timer?.clock ?? ""
                    color: Theme.surfaceText
                    opacity: root.st?.timer?.running ? 1 : 0.55
                    font.pixelSize: Theme.fontSizeSmall
                    font.features: ({ tnum: 1 })
                }
            }

            // Nothing playing and no timer: a small icon to open Islet.
            DankIcon {
                visible: root.linked && !root.hasTrack && !root.hasTimer
                anchors.verticalCenter: parent.verticalCenter
                name: "music_note"
                size: Theme.iconSize - 4
                color: Theme.surfaceVariantText
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            ClippingRectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(root.widgetThickness * 0.62)
                height: width
                radius: width / 2
                color: Theme.surfaceContainerHigh
                Image {
                    anchors.fill: parent
                    visible: root.hasTrack
                    source: root.st?.art ?? ""
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                DankIcon {
                    anchors.centerIn: parent
                    visible: !root.hasTrack
                    name: "lyrics"
                    size: Theme.iconSize - 6
                    color: Theme.surfaceVariantText
                }
            }
            StyledText {
                visible: root.hasTimer
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.st?.timer?.clock ?? ""
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
