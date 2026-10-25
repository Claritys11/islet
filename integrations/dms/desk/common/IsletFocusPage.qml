import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets

// Islet's focus timer: modes, the ring, play/pause, reset, skip. Drawn with
// DMS's widgets, fed by Islet over its socket (IsletClient); the DMS
// dashboard's Islet tab and the Focus card both show it.
ColumnLayout {
    id: root

    // Fewer details for a small card; one row for a card one cell tall.
    property bool compact: false
    property bool strip: false
    readonly property var pomo: IsletClient.pomodoro
    readonly property var day: IsletClient.day
    readonly property var shelf: IsletClient.shelf ?? []
    readonly property var checklist: IsletClient.checklist

    function cmd(name, args) {
        IsletClient.send(Object.assign({ cmd: name }, args ?? {}));
    }

    Requester {
        id: requester
    }

    spacing: Theme.spacingM
    // One row: the time, what it's timing, the buttons.
    RowLayout {
        visible: root.strip
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Theme.spacingS
        StyledText {
            text: root.pomo?.clock ?? "25:00"
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeXLarge
            font.weight: Theme.fontWeightMedium
            font.features: ({ tnum: 1 })
        }
        StyledText {
            Layout.fillWidth: true
            text: root.pomo?.paused ? "Paused" : root.pomo?.label ?? "Focus"
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }
        DIconButton {
            iconName: "restart_alt"
            onClicked: root.cmd("timer-reset")
        }
        DIconButton {
            variant: "filled"
            iconName: root.pomo?.running ? "pause" : "play_arrow"
            onClicked: root.cmd("timer-toggle")
        }
        DIconButton {
            iconName: "skip_next"
            onClicked: root.cmd("timer-skip")
        }
    }
    Row {
        visible: !root.compact
        Layout.alignment: Qt.AlignHCenter
        spacing: Theme.spacingXS
        Repeater {
            model: [{ id: "focus", text: "Focus" }, { id: "short", text: "Short" }, { id: "long", text: "Long" }]
            Rectangle {
                required property var modelData
                readonly property bool on: (root.pomo?.mode ?? "focus") === modelData.id
                width: modeText.implicitWidth + Theme.spacingL * 2
                height: Theme.buttonHeightS ?? 32
                radius: height / 2
                color: on ? Theme.primary : Theme.surfaceContainerHigh
                StyledText {
                    id: modeText
                    anchors.centerIn: parent
                    text: parent.modelData.text
                    color: parent.on ? Theme.primaryText : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cmd("timer-mode", { mode: parent.modelData.id })
                }
            }
        }
    }
    Item {
        visible: !root.strip
        Layout.fillWidth: true
        Layout.fillHeight: true
        // The ring fills as the session goes.
        Canvas {
            id: ring
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            readonly property real progress: root.pomo?.active ? root.pomo.progress : 0
            onProgressChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const r = width / 2 - 6;
                ctx.lineWidth = 8;
                ctx.lineCap = "round";
                ctx.strokeStyle = Theme.surfaceContainerHighest;
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2);
                ctx.stroke();
                if (progress > 0) {
                    ctx.strokeStyle = Theme.primary;
                    ctx.beginPath();
                    ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * progress);
                    ctx.stroke();
                }
            }
        }
        Column {
            anchors.centerIn: ring
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.pomo?.clock ?? "25:00"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeXXLarge ?? 32
                font.weight: Theme.fontWeightMedium
                font.features: ({ tnum: 1 })
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.pomo?.paused ? "Paused" : root.pomo?.label ?? "Focus"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
    Row {
        visible: !root.strip
        Layout.alignment: Qt.AlignHCenter
        spacing: Theme.spacingS
        DIconButton {
            iconName: "restart_alt"
            onClicked: root.cmd("timer-reset")
        }
        DIconButton {
            size: "m"
            variant: "filled"
            iconName: root.pomo?.running ? "pause" : "play_arrow"
            onClicked: root.cmd("timer-toggle")
        }
        DIconButton {
            iconName: "skip_next"
            onClicked: root.cmd("timer-skip")
        }
    }
    StyledText {
        visible: !root.compact
        Layout.alignment: Qt.AlignHCenter
        text: `Hari ini: ${root.pomo?.todayCount ?? 0} sesi · ${root.pomo?.todayFocused ?? 0} mnt`
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
    }
}
