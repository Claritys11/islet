import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

// "Hari ini" tab: today's lessons on the left, close deadlines on the
// right (tick one to mark it Done in Notion), a field to add a task, and the
// sync state with Google Calendar.
Item {
    id: root

    readonly property var t: TodayService
    property alias inputFocused: input.activeFocus
    property alias draft: input.text
    signal calendarRequested

    readonly property color late: Theme.danger
    readonly property color tomorrow: "#ffd58a"

    function urgencyColor(u) {
        return u === "overdue" || u === "today" ? late : u === "tomorrow" ? tomorrow : Theme.subtext;
    }
    function priorityColor(p) {
        return /tinggi|high/i.test(p) ? late : /sedang|medium/i.test(p) ? tomorrow : /rendah|low/i.test(p) ? "#9de6b5" : "transparent";
    }
    function openSettings() {
        Quickshell.execDetached([decodeURIComponent(String(Qt.resolvedUrl("bin/islet")).replace(/^file:\/\//, "")), "settings", "calendar"]);
    }
    function ago(ms) {
        const m = Math.round((t.now - ms) / 60000);
        return m < 1 ? "baru saja" : `${m} mnt lalu`;
    }

    // Not set up (or Today turned off): one clear next step.
    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - 40
        visible: !t.o.todayEnabled || t.status === "setup" || (t.status === "error" && t.allLessons.length === 0 && t.tasks.length === 0)
        spacing: 10
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "event_note"
            color: Theme.subtext
            font.family: Theme.iconFont
            font.pixelSize: 34
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: !t.o.todayEnabled ? "Jadwal & tugas is off." : t.error || "Connect your Notion timetable and tasks."
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
        }
        Button {
            Layout.alignment: Qt.AlignHCenter
            text: "Open settings"
            onClicked: root.openSettings()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        visible: t.o.todayEnabled && (t.status === "ready" || t.allLessons.length + t.tasks.length > 0)

        // ── Sync state ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                text: t.syncStatus === "error" ? "sync_problem" : t.syncStatus === "waiting" ? "sync_lock" : "sync"
                color: t.syncStatus === "error" ? Theme.danger : Theme.subtext
                font.family: Theme.iconFont
                font.pixelSize: 15
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: !t.o.todaySync ? "Sinkron Google Calendar mati"
                    : t.syncStatus === "waiting" ? `Sinkron pertama menunggu konfirmasi · ${t.previewText}`
                    : t.syncStatus === "error" || t.syncStatus === "held" ? t.syncError
                    : t.syncStatus === "syncing" ? "Menyinkronkan…"
                    : t.lastSync ? `Tersinkron ${root.ago(t.lastSync)}` : ""
                color: t.syncStatus === "error" || t.syncStatus === "held" ? Theme.danger : Theme.subtext
                font.family: Theme.font
                font.pixelSize: 11
            }
            Button {
                visible: t.syncStatus === "waiting"
                text: "Lihat dan konfirmasi"
                font.pixelSize: 11
                onClicked: root.openSettings()
            }
            NotchIconButton {
                icon: "refresh"
                size: 26
                tint: Theme.subtext
                onClicked: t.load()
            }
            NotchIconButton {
                icon: "calendar_month"
                size: 26
                tint: Theme.subtext
                onClicked: root.calendarRequested()
            }
        }

        // A version that lost a sync conflict, to take instead.
        Repeater {
            model: t.conflicts.slice(-2)
            Rectangle {
                id: conflict
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 10
                color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.12)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: `Tabrakan: ${conflict.modelData.title} — dipakai versi Google`
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    Button {
                        text: "Pakai versi Notion"
                        font.pixelSize: 11
                        onClicked: t.useOther(t.conflicts.length - Math.min(2, t.conflicts.length) + conflict.index)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            // ── Lessons and Google events ─────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                spacing: 4
                RowLayout {
                    Text {
                        text: `JADWAL · ${["MINGGU", "SENIN", "SELASA", "RABU", "KAMIS", "JUMAT", "SABTU"][new Date(t.now).getDay()]}`
                        color: Theme.subtext
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.letterSpacing: 0.6
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Text {
                        text: t.scheduleToday.length ? `${t.scheduleToday.filter(l => !l.past).length} sisa` : ""
                        color: Theme.subtext
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: t.scheduleToday
                    boundsBehavior: Flickable.StopAtBounds
                    Text {
                        anchors.centerIn: parent
                        visible: parent.count === 0
                        text: "Tidak ada jadwal hari ini"
                        color: Theme.subtext
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    delegate: Rectangle {
                        id: lesson
                        required property var modelData
                        readonly property bool event: modelData.kind === "event"
                        width: ListView.view.width
                        height: 30
                        radius: 10
                        opacity: modelData.past ? 0.4 : 1
                        color: modelData.now ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
                            spacing: 8
                            Text {
                                Layout.preferredWidth: 80
                                text: lesson.modelData.time
                                elide: Text.ElideRight
                                color: lesson.modelData.now ? Theme.primary : Theme.subtext
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.features: ({ tnum: 1 })
                            }
                            // A Google event: its calendar's colour.
                            Rectangle {
                                visible: lesson.event
                                width: 8
                                height: 8
                                radius: 4
                                color: lesson.modelData.color ?? "transparent"
                            }
                            Text {
                                Layout.fillWidth: true
                                text: lesson.modelData.title
                                elide: Text.ElideRight
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 13
                            }
                            Chip {
                                visible: lesson.modelData.clash
                                text: "bentrok"
                                tint: Theme.danger
                            }
                            Chip {
                                visible: lesson.modelData.until !== "" && !lesson.modelData.now
                                text: lesson.modelData.until.replace(/ \d\d\.\d\d$/, "")
                                tint: Theme.subtext
                            }
                            Chip {
                                visible: lesson.modelData.now
                                text: "sekarang"
                                tint: Theme.primary
                                filled: true
                            }
                        }
                    }
                }
            }

            // ── Deadlines ─────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                spacing: 4
                RowLayout {
                    Text {
                        text: "TENGGAT DEKAT"
                        color: Theme.subtext
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.letterSpacing: 0.6
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Text {
                        text: t.deadlines.length || ""
                        color: Theme.subtext
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: t.deadlines
                    boundsBehavior: Flickable.StopAtBounds
                    Text {
                        anchors.centerIn: parent
                        visible: parent.count === 0
                        text: "Tidak ada tenggat dekat ✨"
                        color: Theme.subtext
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    delegate: Rectangle {
                        id: due
                        required property var modelData
                        readonly property bool notion: modelData.source === "notion"
                        width: ListView.view.width
                        height: 30
                        radius: 10
                        color: dueMouse.containsMouse && notion ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        MouseArea {
                            id: dueMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: due.notion ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (due.notion)
                                t.tick(due.modelData.pageId, true)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 2
                            anchors.rightMargin: 6
                            spacing: 8
                            Rectangle {
                                width: 3
                                height: 16
                                radius: 2
                                color: root.priorityColor(due.modelData.priority)
                            }
                            // Tick it (Notion tasks), or Classroom's icon.
                            Rectangle {
                                visible: due.notion
                                width: 16
                                height: 16
                                radius: 8
                                color: "transparent"
                                border.width: 2
                                border.color: dueMouse.containsMouse ? Theme.primary : Theme.subtext
                            }
                            Text {
                                visible: !due.notion
                                text: "school"
                                color: Theme.subtext
                                font.family: Theme.iconFont
                                font.pixelSize: 16
                            }
                            Text {
                                Layout.fillWidth: true
                                text: due.modelData.title
                                elide: Text.ElideRight
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 13
                            }
                            Chip {
                                visible: due.modelData.clash
                                text: "bentrok"
                                tint: Theme.danger
                            }
                            Chip {
                                text: due.modelData.label
                                tint: root.urgencyColor(due.modelData.urgency)
                            }
                        }
                    }
                }
            }
        }

        TextField {
            id: input
            Layout.fillWidth: true
            enabled: t.tasksDb !== ""
            placeholderText: "＋ Tugas baru — Enter menyimpannya di Notion"
            placeholderTextColor: Theme.subtext
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
            leftPadding: 14
            background: Rectangle {
                radius: 12
                color: Theme.raised
                border.width: input.activeFocus ? 1 : 0
                border.color: Theme.primary
            }
            onAccepted: {
                t.add(text, "");
                text = "";
            }
        }

        Text {
            Layout.fillWidth: true
            visible: t.message !== ""
            text: t.message
            color: Theme.danger
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 11
        }
    }

    component Chip: Rectangle {
        property string text
        property color tint: Theme.subtext
        property bool filled: false
        implicitWidth: chipText.implicitWidth + 12
        implicitHeight: 18
        radius: 9
        color: filled ? tint : Qt.rgba(tint.r, tint.g, tint.b, 0.18)
        Text {
            id: chipText
            anchors.centerIn: parent
            text: parent.text
            color: parent.filled ? Theme.onPrimary : parent.tint
            font.family: Theme.font
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }
    }
}
