import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Modules.Plugins
import "common"

// end4-pC's media card with lyrics: cover, title and artist, controls, and
// a few synced lines around the one being sung — all from islet, so it
// shows the same lyrics as islet's notch and the bar pill.
DesktopPluginComponent {
    id: root

    minWidth: 300
    minHeight: 180

    property int lineCount: pluginData.lines ?? 7
    property bool showControls: pluginData.showControls ?? true

    // Stable parts of islet's state (they don't change on every 33 ms tick).
    readonly property var st: IsletClient.track
    readonly property bool hasTrack: !!root.st?.hasTrack
    readonly property var lyr: IsletClient.lyrics
    readonly property bool ready: root.lyr?.status === "ready" && (root.lyr?.lines?.length ?? 0) > 0
    readonly property string statusText: !IsletClient.connected ? "islet isn't running"
        : !root.hasTrack ? ""
        : root.lyr?.status === "loading" ? "Looking for lyrics…"
        : root.lyr?.status === "notfound" ? "No lyrics for this song"
        : root.lyr?.status === "error" ? "Couldn't load lyrics"
        : ""

    DeskCard {
        anchors.fill: parent
        cardColor: Theme.primaryContainer
        textColor: Theme.onPrimaryContainer
        accentColor: Theme.primary
        radius: Theme.cornerRadius * 1.5
        fontFamily: Theme.fontFamily

        // Nothing playing: end4's compact "Play something" card.
        Row {
            visible: !root.hasTrack
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            Rectangle {
                width: 56
                height: 56
                radius: 16
                color: Qt.alpha(Theme.onPrimaryContainer, 0.12)
                Text {
                    anchors.centerIn: parent
                    text: "♪"
                    color: Theme.onPrimaryContainer
                    font.pixelSize: 28
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: IsletClient.connected ? "Nothing playing" : "Lyrics"
                    color: Theme.onPrimaryContainer
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLarge
                }
                Text {
                    text: IsletClient.connected ? "Play something" : root.statusText
                    color: Qt.alpha(Theme.onPrimaryContainer, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        Column {
            visible: root.hasTrack
            anchors.fill: parent
            spacing: 12

            // Cover, title, artist, controls.
            Row {
                id: head
                width: parent.width
                spacing: 12

                ClippingRectangle {
                    width: 72
                    height: 72
                    radius: 18
                    color: Qt.alpha(Theme.onPrimaryContainer, 0.12)
                    Image {
                        anchors.fill: parent
                        source: root.st?.art ?? ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 144
                        sourceSize.height: 144
                    }
                }

                Column {
                    width: parent.width - 72 - 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        text: root.st?.title ?? ""
                        textFormat: Text.PlainText
                        color: Theme.onPrimaryContainer
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLarge
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.st?.artist ?? ""
                        textFormat: Text.PlainText
                        color: Qt.alpha(Theme.onPrimaryContainer, 0.75)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }
                    Row {
                        visible: root.showControls
                        spacing: 6
                        topPadding: 4
                        Repeater {
                            // Static, so the buttons aren't rebuilt mid-click.
                            model: [
                                { icon: "⏮", cmd: "previous", big: false },
                                { icon: "", cmd: "play-pause", big: true },
                                { icon: "⏭", cmd: "next", big: false }
                            ]
                            Rectangle {
                                required property var modelData
                                width: modelData.big ? 44 : 32
                                height: 32
                                radius: 16
                                color: modelData.big ? Theme.primary : (ctl.containsMouse ? Qt.alpha(Theme.primary, 0.25) : "transparent")
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.cmd === "play-pause" ? (root.st?.playing ? "⏸" : "▶") : modelData.icon
                                    color: modelData.big ? Theme.onPrimary : Theme.onPrimaryContainer
                                    font.pixelSize: 15
                                }
                                MouseArea {
                                    id: ctl
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: IsletClient.send({ cmd: modelData.cmd })
                                }
                            }
                        }
                    }
                }
            }

            // The lines: the sung one in the accent colour, the rest fading
            // with their distance from it.
            Item {
                width: parent.width
                height: parent.height - head.height - parent.spacing
                clip: true

                Text {
                    visible: !root.ready
                    anchors.centerIn: parent
                    text: root.statusText
                    color: Qt.alpha(Theme.onPrimaryContainer, 0.6)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Column {
                    id: lines
                    visible: root.ready
                    width: parent.width
                    spacing: 6
                    readonly property int current: root.lyr?.synced ? (root.lyr?.index ?? -1) : -1
                    // Keep the sung line in the upper third.
                    y: Math.min(0, parent.height / 3 - (current >= 0 ? current * 28 : 0))
                    Behavior on y {
                        NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                    }

                    Repeater {
                        model: root.ready ? root.lyr.lines.slice(0, root.lineCount) : []
                        Text {
                            required property var modelData
                            required property int index
                            readonly property int distance: lines.current < 0 ? 0 : Math.abs(index - lines.current)
                            width: lines.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: modelData.text || "♪"
                            textFormat: Text.PlainText
                            color: index === lines.current ? Theme.primary : Theme.onPrimaryContainer
                            opacity: lines.current < 0 ? 0.85 : Math.max(0.25, 1 - distance * 0.25)
                            font.family: Theme.fontFamily
                            font.pixelSize: index === lines.current ? Theme.fontSizeLarge : Theme.fontSizeMedium
                            font.bold: index === lines.current
                            Behavior on opacity {
                                NumberAnimation { duration: 300 }
                            }
                        }
                    }
                }
            }
        }
    }
}
