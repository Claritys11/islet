import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets
import "pomo.mjs" as Pomo

// Islet's focus timer, as the notch's Focus tab has it: modes, the ring,
// play/pause, reset, skip, continuous (focus and breaks roll on by
// themselves), how long it's been paused, the rounds to the long break, a
// tip on breaks, and this sitting. Drawn with DMS's widgets, fed by Islet
// over its socket (IsletClient); the DMS dashboard's Islet tab and the
// Focus card both show it.
ColumnLayout {
    id: root

    // Fewer details for a small card; one row for a card one cell tall.
    property bool compact: false
    property bool strip: false
    readonly property var pomo: IsletClient.pomodoro
    readonly property color accent: (root.pomo?.mode ?? "focus") === "focus" ? Theme.primary : Theme.tertiary

    // The pause and the sitting count here, a second at a time.
    property real now: Date.now()
    readonly property var sit: Pomo.sitting(root.pomo, root.now)
    readonly property string status: Pomo.status(root.pomo, root.now, IsletClient.lang)
    Timer {
        interval: 1000
        repeat: true
        running: root.visible && ((root.pomo?.paused ?? false) || (root.pomo?.sessionStart ?? 0) > 0)
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    function cmd(name, args) {
        IsletClient.send(Object.assign({ cmd: name }, args ?? {}));
    }

    spacing: root.compact ? Theme.spacingS : Theme.spacingM

    // ── One row: the time and what it's timing, the buttons ──────────
    RowLayout {
        visible: root.strip
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Theme.spacingS
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                text: root.pomo?.clock ?? "25:00"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeXLarge
                font.weight: Theme.fontWeightMedium
                font.features: ({ tnum: 1 })
            }
            StyledText {
                Layout.fillWidth: true
                text: root.status
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                color: root.pomo?.paused ? Theme.error : root.accent
                font.pixelSize: Theme.fontSizeSmall
                font.features: ({ tnum: 1 })
            }
        }
        Controls {
            Layout.alignment: Qt.AlignVCenter
            big: false
        }
    }

    // ── Focus · Short · Long ──────────────────────────────────────────
    Row {
        visible: !root.compact && !root.strip
        Layout.alignment: Qt.AlignHCenter
        spacing: Theme.spacingXS
        Repeater {
            model: [{ id: "focus", text: IsletClient.t("Focus", "Fokus") }, { id: "short", text: IsletClient.t("Short", "Pendek") }, { id: "long", text: IsletClient.t("Long", "Panjang") }]
            Rectangle {
                id: modeChip
                required property var modelData
                readonly property bool current: (root.pomo?.mode ?? "focus") === modelData.id
                width: modeText.implicitWidth + Theme.spacingL * 2
                height: Theme.buttonHeightS ?? 32
                radius: height / 2
                color: current ? root.accent : modeMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                StyledText {
                    id: modeText
                    anchors.centerIn: parent
                    text: modeChip.modelData.text
                    color: modeChip.current ? Theme.primaryText : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                }
                MouseArea {
                    id: modeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cmd("timer-mode", { mode: modeChip.modelData.id })
                }
            }
        }
    }

    // ── The ring: what's left of the session, the clock inside ───────
    Item {
        visible: !root.strip
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 90
        Canvas {
            id: ring
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            readonly property real remaining: 1 - (root.pomo?.progress ?? 0)
            readonly property color tint: root.accent
            readonly property color track: Theme.surfaceContainerHighest
            onRemainingChanged: requestPaint()
            onTintChanged: requestPaint()
            onTrackChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const r = width / 2 - 6;
                ctx.lineWidth = 8;
                ctx.lineCap = "round";
                ctx.strokeStyle = track;
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2);
                ctx.stroke();
                ctx.strokeStyle = tint;
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.001, remaining));
                ctx.stroke();
            }
        }
        Column {
            anchors.centerIn: ring
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.pomo?.clock ?? "25:00"
                color: Theme.surfaceText
                font.pixelSize: Math.max(Theme.fontSizeLarge, Math.min(Theme.fontSizeXXLarge, ring.width * 0.22))
                font.weight: Theme.fontWeightMedium
                font.features: ({ tnum: 1 })
            }
            // While paused, how long you've been away instead.
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.status
                color: root.pomo?.paused ? Theme.error : root.accent
                font.pixelSize: Theme.fontSizeSmall
                font.features: ({ tnum: 1 })
            }
        }
    }

    Controls {
        visible: !root.strip
        Layout.alignment: Qt.AlignHCenter
        big: true
    }

    // ── On a break: something good to do with it ─────────────────────
    Row {
        visible: !root.compact && !root.strip && !!root.pomo?.tip
        Layout.alignment: Qt.AlignHCenter
        spacing: Theme.spacingS
        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.pomo?.tip?.icon ?? "self_improvement"
            size: Theme.iconSize
            color: root.accent
            SequentialAnimation on scale {
                running: parent.visible
                loops: Animation.Infinite
                NumberAnimation {
                    from: 0.9
                    to: 1.12
                    duration: 2000
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: 1.12
                    to: 0.9
                    duration: 2000
                    easing.type: Easing.InOutSine
                }
            }
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.width - Theme.iconSize - Theme.spacingS)
            text: root.pomo?.tip?.text ?? ""
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // ── Rounds to the long break, and today's total ──────────────────
    Row {
        visible: !root.strip && (!root.pomo?.tip || root.compact)
        Layout.alignment: Qt.AlignHCenter
        spacing: 5
        Repeater {
            model: Pomo.rounds(root.pomo)
            Rectangle {
                required property bool modelData
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: modelData ? root.accent : Theme.surfaceContainerHighest
            }
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 6
            text: IsletClient.t(`${root.pomo?.todayCount ?? 0} session${root.pomo?.todayCount === 1 ? "" : "s"} · ${Pomo.short((root.pomo?.todayFocused ?? 0) * 60)} today`, `${root.pomo?.todayCount ?? 0} sesi · ${Pomo.short((root.pomo?.todayFocused ?? 0) * 60)} hari ini`)
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // ── This sitting: since the first start, focus, pauses ───────────
    Row {
        visible: !root.compact && !root.strip && (root.pomo?.sessionStart ?? 0) > 0
        Layout.alignment: Qt.AlignHCenter
        spacing: Theme.spacingXS
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: IsletClient.t(`${Pomo.clock(root.sit.elapsed)} elapsed · ${Pomo.short(root.sit.focused)} focus · ${Pomo.short(root.sit.pausedTotal)} paused`, `${Pomo.clock(root.sit.elapsed)} berlalu · ${Pomo.short(root.sit.focused)} fokus · ${Pomo.short(root.sit.pausedTotal)} jeda`)
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            font.features: ({ tnum: 1 })
        }
        // Forget the pause time only.
        DIcon {
            visible: root.sit.pausedTotal >= 1
            anchors.verticalCenter: parent.verticalCenter
            name: "restart_alt"
            size: 16
            color: resetPauseMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText
            MouseArea {
                id: resetPauseMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cmd("timer-reset-pause")
            }
        }
    }

    // ⟳ reset · ▶/⏸ · ⏭ skip · ∞ continuous
    component Controls: Row {
        property bool big: false
        spacing: big ? Theme.spacingS : 0
        DIconButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: "restart_alt"
            onClicked: root.cmd("timer-reset")
        }
        DIconButton {
            anchors.verticalCenter: parent.verticalCenter
            size: parent.big ? "m" : "s"
            variant: "filled"
            iconName: root.pomo?.running ? "pause" : "play_arrow"
            onClicked: root.cmd("timer-toggle")
        }
        DIconButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: "skip_next"
            onClicked: root.cmd("timer-skip")
        }
        // Continuous: focus and breaks roll on by themselves.
        DIconButton {
            anchors.verticalCenter: parent.verticalCenter
            variant: root.pomo?.continuous ? "tonal" : "standard"
            iconName: "all_inclusive"
            onClicked: root.cmd("timer-continuous", { on: !root.pomo?.continuous })
        }
    }
}
