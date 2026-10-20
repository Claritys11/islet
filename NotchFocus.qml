import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// Pomodoro tab: progress ring, mode switcher, controls and today's tally.
Item {
    id: root

    readonly property var pomo: PomodoroService
    readonly property color accent: pomo.mode === "focus" ? Theme.focus : Theme.primary

    RowLayout {
        anchors.fill: parent
        spacing: 26

        // Progress ring with the countdown inside.
        Item {
            Layout.preferredWidth: 150
            Layout.preferredHeight: 150
            Layout.alignment: Qt.AlignVCenter

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: Qt.rgba(1, 1, 1, 0.1)
                    strokeWidth: 8
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 75
                        centerY: 75
                        radiusX: 69
                        radiusY: 69
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
                ShapePath {
                    strokeColor: root.accent
                    strokeWidth: 8
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 75
                        centerY: 75
                        radiusX: 69
                        radiusY: 69
                        startAngle: -90
                        sweepAngle: 360 * Math.max(0.001, 1 - root.pomo.progress)
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.pomo.clock
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 34
                    font.weight: Font.DemiBold
                    font.features: ({ tnum: 1 })
                }
                // While paused, how long you've been away instead.
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.pomo.paused ? `Paused ${root.pomo.format(root.pomo.pausedFor)}` : root.pomo.label
                    color: root.pomo.paused ? Theme.danger : root.accent
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.features: ({ tnum: 1 })
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 14

            // Mode switcher
            Row {
                spacing: 6
                Repeater {
                    model: [
                        { mode: "focus", text: "Focus" },
                        { mode: "short", text: "Short" },
                        { mode: "long", text: "Long" }
                    ]
                    Rectangle {
                        required property var modelData
                        readonly property bool current: root.pomo.mode === modelData.mode
                        width: modeLabel.implicitWidth + 24
                        height: 30
                        radius: 15
                        color: current ? Qt.rgba(1, 1, 1, 0.14) : modeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        Text {
                            id: modeLabel
                            anchors.centerIn: parent
                            text: modelData.text
                            color: parent.current ? Theme.text : Theme.subtext
                            font.family: Theme.font
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: modeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pomo.setMode(modelData.mode)
                        }
                    }
                }
            }

            Row {
                spacing: 10
                NotchIconButton {
                    icon: "restart_alt"
                    onClicked: root.pomo.reset()
                }
                NotchIconButton {
                    icon: root.pomo.running ? "pause" : "play_arrow"
                    filled: true
                    highlighted: true
                    size: 46
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.pomo.toggle()
                }
                NotchIconButton {
                    icon: "skip_next"
                    onClicked: root.pomo.skip()
                }
                // Continuous: focus and breaks roll on by themselves.
                NotchIconButton {
                    icon: "all_inclusive"
                    filled: root.pomo.continuous
                    tint: root.pomo.continuous ? root.accent : Theme.subtext
                    onClicked: root.pomo.setContinuous(!root.pomo.continuous)
                }
            }

            // Round progress towards the long break, and today's total.
            Row {
                spacing: 6
                Repeater {
                    model: Config.opts.longBreakEvery
                    Rectangle {
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: index < root.pomo.round - (root.pomo.mode === "focus" ? 1 : 0) || (root.pomo.mode === "long") ? root.accent : Qt.rgba(1, 1, 1, 0.18)
                    }
                }
                Text {
                    leftPadding: 8
                    text: `${root.pomo.todayCount} session${root.pomo.todayCount === 1 ? "" : "s"} · ${root.pomo.formatShort(root.pomo.todayFocused)} focused today`
                    color: Theme.subtext
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }

            // This sitting: time since the first start, focus and pauses.
            Row {
                visible: root.pomo.sessionStart > 0
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${root.pomo.format(root.pomo.elapsed)} elapsed  ·  ${root.pomo.formatShort(root.pomo.focused)} focus  ·  ${root.pomo.formatShort(root.pomo.pausedTotal)} paused`
                    color: Theme.subtext
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.features: ({ tnum: 1 })
                }
                // Reset just the pause time.
                NotchIconButton {
                    visible: root.pomo.pausedTotal >= 1
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "restart_alt"
                    size: 22
                    tint: Theme.subtext
                    onClicked: root.pomo.resetPause()
                }
            }
        }
    }
}
