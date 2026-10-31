import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "link/desk.mjs" as Desk
import "integrations/dms/desk/common/due/due.mjs" as Due
import "integrations/dms/desk/common/due" as Picker

// "Hari ini" tab: today's lessons on the left, close deadlines, all open
// tasks or the day's daily tasks on the right (tick one to mark it done in
// Notion), fields to add a task and its due date, and the sync state with
// Google Calendar.
Item {
    id: root

    readonly property var t: TodayService
    readonly property bool inputFocused: input.activeFocus || picker.typing
    readonly property string draft: input.text + dueText
    // The right column: close deadlines ("due"), every open task ("all") or
    // today's daily tasks ("daily", from their own list in Notion).
    property string list: "due"
    readonly property var openTasks: Desk.openTasks(t.tasks, 200).filter(x => !x.done)
    readonly property bool canDue: t.tasksDb !== "" && !!t.tasksMap.due
    property string addError: ""
    // The calendar for the due date, shown where the lists are.
    property bool picking: false
    // The due date as typed or picked ("6/11 14.00"), "" for none.
    property string dueText: ""
    readonly property var dueParsed: Due.parseDue(dueText, new Date(t.now))

    // A due date that isn't one keeps both fields as they are.
    function submit() {
        const text = input.text.trim();
        if (text === "")
            return;
        const due = canDue ? root.dueParsed : { due: "" };
        if (!due) {
            addError = Lang.t("The due date isn't a date: try “besok”, “jum 14.00” or “5/11”.", "Tenggatnya bukan tanggal: coba “besok”, “jum 14.00” atau “5/11”.");
            picking = true;
            return;
        }
        addError = "";
        picking = false;
        t.add(text, due.due);
        input.text = "";
        dueText = "";
        input.forceActiveFocus();
    }
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
        return m < 1 ? Lang.t("just now", "baru saja") : Lang.t(`${m} min ago`, `${m} mnt lalu`);
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
            text: !t.o.todayEnabled ? Lang.t("Lessons & tasks are off.", "Jadwal & tugas mati.") : t.error || Lang.t("Connect your Notion timetable and tasks.", "Sambungkan jadwal dan tugas Notion-mu.")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
        }
        Button {
            Layout.alignment: Qt.AlignHCenter
            text: Lang.t("Open settings", "Buka pengaturan")
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
                text: !t.o.todaySync ? Lang.t("Google Calendar sync is off", "Sinkron Google Calendar mati")
                    : t.syncStatus === "waiting" ? Lang.t(`First sync waits for you · ${t.previewText}`, `Sinkron pertama menunggu konfirmasi · ${t.previewText}`)
                    : t.syncStatus === "error" || t.syncStatus === "held" ? t.syncError
                    : t.syncStatus === "syncing" ? Lang.t("Syncing…", "Menyinkronkan…")
                    : t.lastSync ? Lang.t(`Synced ${root.ago(t.lastSync)}`, `Tersinkron ${root.ago(t.lastSync)}`) : ""
                color: t.syncStatus === "error" || t.syncStatus === "held" ? Theme.danger : Theme.subtext
                font.family: Theme.font
                font.pixelSize: 11
            }
            Button {
                visible: t.syncStatus === "waiting"
                text: Lang.t("Review and confirm", "Lihat dan konfirmasi")
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
                        text: Lang.t(`Clash: ${conflict.modelData.title} — Google's version kept`, `Tabrakan: ${conflict.modelData.title} — dipakai versi Google`)
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    Button {
                        text: Lang.t("Use Notion's version", "Pakai versi Notion")
                        font.pixelSize: 11
                        onClicked: t.useOther(t.conflicts.length - Math.min(2, t.conflicts.length) + conflict.index)
                    }
                }
            }
        }

        Picker.DuePicker {
            id: picker
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.picking
            value: root.dueText
            marks: root.openTasks.filter(x => x.due).map(x => String(x.due).slice(0, 10))
            lang: Lang.code
            textColor: Theme.text
            subColor: Theme.subtext
            accentColor: Theme.primary
            accentTextColor: Theme.onPrimary
            hoverColor: Qt.rgba(1, 1, 1, 0.08)
            fontFamily: Theme.font
            tileColor: Qt.rgba(1, 1, 1, 0.04)
            errorColor: Theme.danger
            fontSize: 13
            onChosen: (text, done) => {
                root.dueText = text;
                root.addError = "";
                if (done) {
                    root.picking = false;
                    input.forceActiveFocus();
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.picking
            spacing: 16

            // ── Lessons and Google events ─────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                spacing: 4
                RowLayout {
                    Text {
                        text: `${Lang.t("SCHEDULE", "JADWAL")} · ${(Lang.id ? ["MINGGU", "SENIN", "SELASA", "RABU", "KAMIS", "JUMAT", "SABTU"] : ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"])[new Date(t.now).getDay()]}`
                        color: Theme.subtext
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.letterSpacing: 0.6
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Text {
                        text: t.scheduleToday.length ? Lang.t(`${t.scheduleToday.filter(l => !l.past).length} left`, `${t.scheduleToday.filter(l => !l.past).length} sisa`) : ""
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
                        text: Lang.t("Nothing on today", "Tidak ada jadwal hari ini")
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
                                text: Lang.t("clash", "bentrok")
                                tint: Theme.danger
                            }
                            Chip {
                                visible: lesson.modelData.until !== "" && !lesson.modelData.now
                                text: lesson.modelData.until.replace(/ \d\d[.:]\d\d$/, "")
                                tint: Theme.subtext
                            }
                            Chip {
                                visible: lesson.modelData.now
                                text: Lang.t("now", "sekarang")
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
                    spacing: 12
                    Repeater {
                        model: [
                            { key: "due", text: Lang.t("DUE SOON", "TENGGAT DEKAT"), n: t.deadlines.length },
                            { key: "all", text: Lang.t("ALL TASKS", "SEMUA TUGAS"), n: root.openTasks.length },
                            { key: "daily", text: Lang.t("DAILY", "HARIAN"), n: t.dailyToday.length ? `${t.dailyToday.filter(d => d.done).length}/${t.dailyToday.length}` : 0 }
                        ]
                        Text {
                            id: tab
                            required property var modelData
                            text: modelData.n ? `${modelData.text} · ${modelData.n}` : modelData.text
                            color: root.list === modelData.key ? Theme.primary : tabMouse.containsMouse ? Theme.text : Theme.subtext
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.letterSpacing: 0.6
                            font.weight: root.list === modelData.key ? Font.DemiBold : Font.Normal
                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.list = tab.modelData.key
                            }
                        }
                    }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.list === "due"
                    clip: true
                    spacing: 2
                    model: t.deadlines
                    boundsBehavior: Flickable.StopAtBounds
                    Text {
                        anchors.centerIn: parent
                        visible: parent.count === 0
                        text: Lang.t("Nothing due soon ✨", "Tidak ada tenggat dekat ✨")
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
                                text: Lang.t("clash", "bentrok")
                                tint: Theme.danger
                            }
                            Chip {
                                text: due.modelData.label
                                tint: root.urgencyColor(due.modelData.urgency)
                            }
                        }
                    }
                }
                // Today's daily tasks: tick one for today, it's back on its next day.
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.list === "daily"
                    clip: true
                    spacing: 2
                    model: t.dailyToday
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 16
                        visible: parent.count === 0
                        spacing: 8
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: t.dailyDb !== "" ? Lang.t("Nothing for today. Add some in Notion: Hari is which days, none is every day.", "Tidak ada untuk hari ini. Tambahkan di Notion: Hari untuk harinya, kosong berarti setiap hari.") : Lang.t("Daily tasks live in a list of their own in Notion.", "Tugas harian ada di daftarnya sendiri di Notion.")
                            color: Theme.subtext
                            font.family: Theme.font
                            font.pixelSize: 12
                        }
                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: t.dailyDb === ""
                            text: Lang.t("Make it in Notion", "Buat di Notion")
                            onClicked: t.makeDaily()
                        }
                    }
                    delegate: Rectangle {
                        id: chore
                        required property var modelData
                        width: ListView.view.width
                        height: 30
                        radius: 10
                        color: choreMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        MouseArea {
                            id: choreMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: t.tickDaily(chore.modelData.id, !chore.modelData.done)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 2
                            anchors.rightMargin: 6
                            spacing: 8
                            Rectangle {
                                width: 16
                                height: 16
                                radius: 4
                                color: chore.modelData.done ? Theme.primary : "transparent"
                                border.width: 2
                                border.color: chore.modelData.done || choreMouse.containsMouse ? Theme.primary : Theme.subtext
                                Text {
                                    anchors.centerIn: parent
                                    visible: chore.modelData.done
                                    text: "check"
                                    color: Theme.onPrimary
                                    font.family: Theme.iconFont
                                    font.pixelSize: 13
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: chore.modelData.title
                                elide: Text.ElideRight
                                opacity: chore.modelData.done ? 0.5 : 1
                                font.strikeout: chore.modelData.done
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 13
                            }
                            Chip {
                                visible: chore.modelData.time !== ""
                                text: chore.modelData.time
                                tint: chore.modelData.late ? Theme.danger : Theme.subtext
                            }
                        }
                    }
                }
                // Every open Notion task, soonest due first, undated last.
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.list === "all"
                    clip: true
                    spacing: 2
                    model: root.openTasks
                    boundsBehavior: Flickable.StopAtBounds
                    Text {
                        anchors.centerIn: parent
                        visible: parent.count === 0
                        text: Lang.t("Nothing to do 🎉", "Tidak ada tugas 🎉")
                        color: Theme.subtext
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    delegate: Rectangle {
                        id: task
                        required property var modelData
                        readonly property var chip: Due.dueChip(modelData.due, new Date(t.now), Lang.code)
                        width: ListView.view.width
                        height: 30
                        radius: 10
                        color: taskMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        MouseArea {
                            id: taskMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: t.tick(task.modelData.id, true)
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
                                color: root.priorityColor(task.modelData.priority)
                            }
                            Rectangle {
                                width: 16
                                height: 16
                                radius: 8
                                color: "transparent"
                                border.width: 2
                                border.color: taskMouse.containsMouse ? Theme.primary : Theme.subtext
                            }
                            Text {
                                Layout.fillWidth: true
                                text: task.modelData.title
                                elide: Text.ElideRight
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 13
                            }
                            Chip {
                                visible: task.chip.text !== ""
                                text: task.chip.text
                                tint: task.chip.late ? Theme.danger : Theme.subtext
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            TextField {
                id: input
                Layout.fillWidth: true
                enabled: t.tasksDb !== ""
                placeholderText: Lang.t("＋ New task", "＋ Tugas baru")
                Keys.onEscapePressed: event => {
                    event.accepted = root.picking;
                    root.picking = false;
                }
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
                onAccepted: root.submit()
            }
            // The due date picked, or "Tenggat"; opens the calendar.
            Rectangle {
                id: dueButton
                readonly property bool set: root.dueText.trim() !== ""
                visible: root.canDue
                implicitWidth: dueRow.implicitWidth + 24
                implicitHeight: input.implicitHeight
                radius: 12
                color: root.picking || set ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, dueMouse.containsMouse ? 0.3 : 0.2) : dueMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Theme.raised
                Row {
                    id: dueRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.picking ? "expand_more" : "event"
                        color: dueButton.set || root.picking ? Theme.primary : Theme.subtext
                        font.family: Theme.iconFont
                        font.pixelSize: 17
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: !dueButton.set ? Lang.t("Due", "Tenggat") : root.dueParsed ? Due.dueChip(root.dueParsed.due, new Date(new Date(t.now).setHours(0, 0, 0, 0)), Lang.code).text : "?"
                        color: dueButton.set ? Theme.text : Theme.subtext
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                }
                MouseArea {
                    id: dueMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picking = !root.picking
                }
            }
            Rectangle {
                readonly property bool ready: t.tasksDb !== "" && input.text.trim() !== ""
                implicitWidth: addRow.implicitWidth + 24
                implicitHeight: input.implicitHeight
                radius: 12
                opacity: ready ? 1 : 0.4
                color: Theme.primary
                Row {
                    id: addRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "add"
                        color: Theme.onPrimary
                        font.family: Theme.iconFont
                        font.pixelSize: 17
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Lang.t("Add", "Tambah")
                        color: Theme.onPrimary
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: parent.ready
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.submit()
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.addError !== "" || t.message !== ""
            text: root.addError || t.message
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
