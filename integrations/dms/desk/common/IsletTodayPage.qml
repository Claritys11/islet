import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets

// Hari ini: the lesson about to start, today's lessons and Google events,
// close deadlines (tick a Notion one to mark it Done), a field for a new
// task. Drawn with DMS's widgets, fed by Islet over its socket
// (IsletClient); the DMS dashboard's Islet tab and the Hari ini card both
// show it.
ColumnLayout {
    id: root

    // Fewer details for a small card.
    property bool compact: false
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

    spacing: Theme.spacingS
    StyledText {
        Layout.fillWidth: true
        visible: !(root.day?.enabled ?? false) || (root.day?.status ?? "") === "setup"
        wrapMode: Text.WordWrap
        text: !(root.day?.enabled ?? false) ? "Hari ini is off in Islet Settings." : (root.day?.error || "Set up Notion in Islet Settings → Calendar & Notion.")
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeMedium
    }
    // A lesson about to start.
    Rectangle {
        Layout.fillWidth: true
        visible: !!root.day?.soon
        implicitHeight: soonRow.implicitHeight + Theme.spacingS * 2
        radius: Theme.cornerRadius
        color: Theme.primaryContainer
        RowLayout {
            id: soonRow
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            DIcon {
                name: "school"
                size: Theme.iconSize
                color: Theme.primary
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                text: root.day?.soon ? `${root.day.soon.title} · mulai ${Math.max(1, Math.ceil((root.day.soon.startAt - Date.now()) / 60000))} mnt lagi` : ""
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }
    GridLayout {
        // Side by side, or one under the other on a narrow card.
        columns: root.width < 420 ? 1 : 2
        columnSpacing: Theme.spacingM
        rowSpacing: Theme.spacingS
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.day?.enabled ?? false
        // Lessons and Google events.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            spacing: Theme.spacingXS
            StyledText {
                text: "JADWAL"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: root.day?.schedule ?? []
                StyledText {
                    anchors.centerIn: parent
                    visible: parent.count === 0
                    text: "Tidak ada jadwal"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }
                delegate: Rectangle {
                    id: slot
                    required property var modelData
                    width: ListView.view.width
                    height: 30
                    radius: Theme.cornerRadius
                    opacity: modelData.past ? 0.45 : 1
                    color: modelData.now ? Theme.primaryContainer : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingXS
                        anchors.rightMargin: Theme.spacingXS
                        spacing: Theme.spacingS
                        StyledText {
                            Layout.preferredWidth: 80
                            text: slot.modelData.time
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            color: slot.modelData.now ? Theme.primary : Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            font.features: ({ tnum: 1 })
                        }
                        Rectangle {
                            visible: slot.modelData.color !== ""
                            width: 8
                            height: 8
                            radius: 4
                            color: slot.modelData.color || "transparent"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: slot.modelData.title
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        StyledText {
                            visible: slot.modelData.until !== "" || slot.modelData.clash
                            text: slot.modelData.clash ? "bentrok" : slot.modelData.until.replace(/ \d\d\.\d\d$/, "")
                            color: slot.modelData.clash ? Theme.error : Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }
        }
        // Close deadlines: tick a Notion one to mark it Done.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            spacing: Theme.spacingXS
            StyledText {
                text: "TENGGAT DEKAT"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: root.day?.deadlines ?? []
                StyledText {
                    anchors.centerIn: parent
                    visible: parent.count === 0
                    text: "Tidak ada tenggat dekat ✨"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }
                delegate: Rectangle {
                    id: due
                    required property var modelData
                    width: ListView.view.width
                    height: 30
                    radius: Theme.cornerRadius
                    color: dueMouse.containsMouse && modelData.tickable ? Theme.surfaceContainerHigh : "transparent"
                    MouseArea {
                        id: dueMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: due.modelData.tickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (due.modelData.tickable)
                            root.cmd("task-done", { id: due.modelData.id, done: true })
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingXS
                        anchors.rightMargin: Theme.spacingXS
                        spacing: Theme.spacingS
                        DIcon {
                            name: due.modelData.tickable ? (dueMouse.containsMouse ? "check_circle" : "radio_button_unchecked") : "school"
                            size: Theme.iconSizeSmall ?? 16
                            color: /tinggi|high/i.test(due.modelData.priority) ? Theme.error : Theme.surfaceVariantText
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: due.modelData.title
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        StyledText {
                            text: due.modelData.label
                            color: due.modelData.urgency === "overdue" || due.modelData.urgency === "today" ? Theme.error : Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        visible: (root.day?.enabled ?? false) && !root.compact
        spacing: Theme.spacingS
        DTextField {
            id: taskField
            Layout.fillWidth: true
            enabled: root.day?.canAdd ?? false
            placeholderText: "＋ Tugas baru — Enter menyimpannya di Notion"
            onAccepted: {
                const text = taskField.text.trim();
                if (text === "")
                    return;
                taskField.text = "";
                requester.request("task-add", { text }, (ok, data, err) => {
                    if (!ok)
                        taskField.text = text;
                }, 60000);
            }
        }
        DIconButton {
            iconName: "refresh"
            onClicked: root.cmd("today-refresh")
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: (root.day?.sync ?? "") !== "" && !root.compact
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
        text: root.day?.sync ?? ""
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
    }
}
