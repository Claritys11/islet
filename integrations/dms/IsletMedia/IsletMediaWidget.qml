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
    readonly property bool hasWeather: linked && !hasTrack && !hasTimer && !!st.weather
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
        Item {
            id: pill
            implicitWidth: pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight

            // Files dragged onto the pill open Islet's shelf right below it,
            // and dropping them here parks them on the shelf.
            DropArea {
                anchors.fill: parent
                anchors.margins: -6
                onEntered: drag => {
                    if (!drag.hasUrls)
                        return;
                    drag.accept(Qt.CopyAction);
                    const p = pill.mapToGlobal(0, 0);
                    root.send({ cmd: "open", tab: "shelf", x: p.x, y: -1, width: pill.width });
                }
                onDropped: drop => {
                    if (!drop.hasUrls)
                        return;
                    root.send({ cmd: "shelf-add", urls: drop.urls.map(u => u.toString()) });
                    drop.accept(Qt.CopyAction);
                }
            }

            Row {
                id: pillRow
                anchors.verticalCenter: parent.verticalCenter
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
                    // No Behaviors in this pill: Islet sends 30 updates a second,
                    // and an animation restarted on each one would keep the whole
                    // bar redrawing at the monitor's refresh rate.
                    readonly property real shift: root.isLyric ? overflow * Math.max(0, Math.min(1, (progress - 0.2) / 0.6)) : 0

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
                        // A count, not the array: each update would rebuild the bars.
                        model: root.st?.viz?.length ?? 0
                        Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: Math.max(3, (root.st?.viz?.[index] ?? 0) * root.widgetThickness * 0.5)
                            radius: 1.5
                            color: Theme.primary
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

                // Nothing playing and no timer: the weather, if Islet has it.
                Row {
                    visible: root.hasWeather
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.st?.weather?.icon ?? "cloud"
                        size: Theme.iconSize - 4
                        color: Theme.primary
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.st?.weather?.temp ?? ""
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }

                // …or just a small icon to open Islet.
                DankIcon {
                    visible: root.linked && !root.hasTrack && !root.hasTimer && !root.hasWeather
                    anchors.verticalCenter: parent.verticalCenter
                    name: "music_note"
                    size: Theme.iconSize - 4
                    color: Theme.surfaceVariantText
                }
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
