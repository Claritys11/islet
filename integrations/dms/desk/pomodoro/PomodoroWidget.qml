import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.Common
import qs.Modules.Plugins
import "common"

// islet's focus timer, end4 tile style: mode chips, a ring with the clock,
// play/pause, reset and skip, and today's focus so far.
DesktopPluginComponent {
    id: root

    minWidth: 220
    minHeight: 200

    readonly property var p: IsletClient.pomodoro
    readonly property bool on: IsletClient.connected && root.p !== null

    function send(cmd, extra): void {
        IsletClient.send(Object.assign({ cmd }, extra ?? {}));
    }

    DeskCard {
        anchors.fill: parent
        cardColor: Theme.primaryContainer
        textColor: Theme.onPrimaryContainer
        accentColor: Theme.primary
        radius: Theme.cornerRadius * 1.5
        fontFamily: Theme.fontFamily

        Text {
            visible: !root.on
            anchors.centerIn: parent
            text: "islet isn't running"
            color: Qt.alpha(Theme.onPrimaryContainer, 0.7)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Item {
            visible: root.on
            anchors.fill: parent

            Row {
                id: modes
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Repeater {
                    model: [{ id: "focus", label: "Focus" }, { id: "short", label: "Short" }, { id: "long", label: "Long" }]
                    Rectangle {
                        required property var modelData
                        readonly property bool active: root.p?.mode === modelData.id
                        width: chip.implicitWidth + 18
                        height: 26
                        radius: 13
                        color: active ? Theme.primary : Qt.alpha(Theme.onPrimaryContainer, 0.1)
                        Text {
                            id: chip
                            anchors.centerIn: parent
                            text: modelData.label
                            color: parent.active ? Theme.onPrimary : Theme.onPrimaryContainer
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.send("timer-mode", { mode: modelData.id })
                        }
                    }
                }
            }

            // Ring + clock.
            Item {
                id: ring
                readonly property real size: Math.max(60, Math.min(parent.width, parent.height - modes.height - controls.height - today.height - 24))
                width: size
                height: size
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: modes.bottom
                anchors.topMargin: 8

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.alpha(Theme.onPrimaryContainer, 0.15)
                        strokeWidth: 8
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: ring.size / 2; centerY: ring.size / 2
                            radiusX: ring.size / 2 - 6; radiusY: ring.size / 2 - 6
                            startAngle: -90; sweepAngle: 360
                        }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Theme.primary
                        strokeWidth: 8
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: ring.size / 2; centerY: ring.size / 2
                            radiusX: ring.size / 2 - 6; radiusY: ring.size / 2 - 6
                            startAngle: -90; sweepAngle: 360 * (root.p?.progress ?? 0)
                        }
                    }
                }
                Column {
                    anchors.centerIn: parent
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.p?.clock ?? "--:--"
                        color: Theme.onPrimaryContainer
                        font.family: Theme.fontFamily
                        font.pixelSize: ring.size * 0.22
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.p?.paused ? "Paused" : (root.p?.label ?? "")
                        color: Qt.alpha(Theme.onPrimaryContainer, 0.7)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            Row {
                id: controls
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: ring.bottom
                anchors.topMargin: 8
                spacing: 8
                Repeater {
                    // Static, so the buttons aren't rebuilt mid-click.
                    model: [
                        { icon: "↺", cmd: "timer-reset", big: false },
                        { icon: "", cmd: "timer-toggle", big: true },
                        { icon: "⏭", cmd: "timer-skip", big: false }
                    ]
                    Rectangle {
                        required property var modelData
                        width: modelData.big ? 56 : 36
                        height: 36
                        radius: 18
                        color: modelData.big ? Theme.primary : (btn.containsMouse ? Qt.alpha(Theme.primary, 0.25) : Qt.alpha(Theme.onPrimaryContainer, 0.1))
                        Text {
                            anchors.centerIn: parent
                            text: modelData.cmd === "timer-toggle" ? (root.p?.running ? "⏸" : "▶") : modelData.icon
                            color: modelData.big ? Theme.onPrimary : Theme.onPrimaryContainer
                            font.pixelSize: 16
                        }
                        MouseArea {
                            id: btn
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.send(modelData.cmd)
                        }
                    }
                }
            }

            Text {
                id: today
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: controls.bottom
                anchors.topMargin: 6
                text: `Hari ini: ${root.p?.todayCount ?? 0} sesi · ${root.p?.todayFocused ?? 0} mnt`
                color: Qt.alpha(Theme.onPrimaryContainer, 0.7)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
