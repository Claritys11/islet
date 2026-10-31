import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets
import "due/due.mjs" as Due
import "due"

// Hari ini: the lesson about to start, today's lessons and Google events,
// close deadlines, all open tasks or the day's daily tasks (tick one to mark
// it done), a field for a new task and one for its due date. Drawn with DMS's widgets, fed by Islet over its socket
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
    // The right column: close deadlines ("due"), every open task ("all") or
    // today's daily tasks ("daily", from their own list in Notion).
    property string list: "due"
    readonly property var openTasks: (IsletClient.tasks?.items ?? []).filter(t => !t.done)
    readonly property bool canDue: root.day?.canDue ?? false
    readonly property var daily: root.day?.daily ?? []
    readonly property int dailyDone: root.daily.filter(d => d.done).length
    property bool makingDaily: false
    function makeDaily() {
        root.makingDaily = true;
        root.addError = "";
        requester.request("daily-setup", {}, (ok, data, err) => {
            root.makingDaily = false;
            if (!ok)
                root.addError = err;
        }, 60000);
    }
    property string addError: ""
    // The calendar for the due date, shown where the lists are.
    property bool picking: false
    // The due date as typed or picked ("6/11 14.00"), "" for none.
    property string dueText: ""
    readonly property var dueParsed: Due.parseDue(root.dueText, new Date())
    // Days that already have a task due, dotted on the calendar.
    readonly property var dueDays: root.openTasks.filter(t => t.due).map(t => String(t.due).slice(0, 10))

    // Keeps what was typed until Notion has the task; a due date that isn't
    // one stops it there.
    function submit() {
        const text = taskField.text.trim();
        if (text === "")
            return;
        const due = root.canDue ? root.dueParsed : { due: "" };
        if (!due) {
            root.addError = IsletClient.t("The due date isn't a date: try “besok”, “jum 14.00” or “5/11”.", "Tenggatnya bukan tanggal: coba “besok”, “jum 14.00” atau “5/11”.");
            root.picking = true;
            return;
        }
        root.addError = "";
        root.picking = false;
        taskField.text = "";
        root.dueText = "";
        requester.request("task-add", due.due ? { text, due: due.due } : { text }, (ok, data, err) => {
            if (ok)
                return;
            taskField.text = text;
            root.addError = err;
        }, 60000);
    }

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
        text: !(root.day?.enabled ?? false) ? IsletClient.t("Today is off in Islet Settings.", "Hari ini dimatikan di Islet Settings.") : (root.day?.error || IsletClient.t("Set up Notion in Islet Settings → Calendar & Notion.", "Siapkan Notion di Islet Settings → Calendar & Notion."))
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
                text: root.day?.soon ? IsletClient.t(`${root.day.soon.title} · in ${Math.max(1, Math.ceil((root.day.soon.startAt - Date.now()) / 60000))} min`, `${root.day.soon.title} · mulai ${Math.max(1, Math.ceil((root.day.soon.startAt - Date.now()) / 60000))} mnt lagi`) : ""
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
        visible: (root.day?.enabled ?? false) && !root.picking
        // Lessons and Google events.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            spacing: Theme.spacingXS
            StyledText {
                text: IsletClient.t("SCHEDULE", "JADWAL")
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
                    text: IsletClient.t("Nothing on today", "Tidak ada jadwal")
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
                            text: slot.modelData.clash ? IsletClient.t("clash", "bentrok") : slot.modelData.until.replace(/ \d\d[.:]\d\d$/, "")
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
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingM
                Repeater {
                    model: [
                        { key: "due", text: IsletClient.t("DUE SOON", "TENGGAT") },
                        { key: "all", text: IsletClient.t(`ALL · ${root.openTasks.length}`, `SEMUA · ${root.openTasks.length}`) },
                        { key: "daily", text: IsletClient.t("DAILY", "HARIAN") + (root.daily.length ? ` · ${root.dailyDone}/${root.daily.length}` : "") }
                    ]
                    StyledText {
                        id: tab
                        required property var modelData
                        text: modelData.text
                        color: root.list === modelData.key ? Theme.primary : tabMouse.containsMouse ? Theme.surfaceText : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
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
                Item {
                    Layout.fillWidth: true
                }
                // Daily tasks are arranged in Notion.
                DIcon {
                    visible: root.list === "daily" && (root.day?.canDaily ?? false)
                    name: "open_in_new"
                    size: 14
                    color: notionMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText
                    MouseArea {
                        id: notionMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally(root.day.dailyUrl)
                    }
                }
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.list === "due"
                clip: true
                spacing: 2
                model: root.day?.deadlines ?? []
                StyledText {
                    anchors.centerIn: parent
                    visible: parent.count === 0
                    text: IsletClient.t("Nothing due soon ✨", "Tidak ada tenggat dekat ✨")
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
            // Today's daily tasks: tick one for today, it's back on its next day.
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.list === "daily"
                clip: true
                spacing: 2
                model: root.daily
                Column {
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacingM
                    visible: parent.count === 0
                    spacing: Theme.spacingS
                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.day?.canDaily ? IsletClient.t("Nothing for today. Add some in Notion: Hari is which days, none is every day.", "Tidak ada untuk hari ini. Tambahkan di Notion: Hari untuk harinya, kosong berarti setiap hari.") : IsletClient.t("Daily tasks live in a list of their own in Notion.", "Tugas harian ada di daftarnya sendiri di Notion.")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    DButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !(root.day?.canDaily ?? false)
                        enabled: !root.makingDaily
                        iconName: "add"
                        text: root.makingDaily ? IsletClient.t("Making…", "Membuat…") : IsletClient.t("Make it in Notion", "Buat di Notion")
                        onClicked: root.makeDaily()
                    }
                }
                delegate: Rectangle {
                    id: chore
                    required property var modelData
                    width: ListView.view.width
                    height: 30
                    radius: Theme.cornerRadius
                    color: choreMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent"
                    MouseArea {
                        id: choreMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cmd("daily-done", { id: chore.modelData.id, done: !chore.modelData.done })
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingXS
                        anchors.rightMargin: Theme.spacingXS
                        spacing: Theme.spacingS
                        DIcon {
                            name: chore.modelData.done ? "check_box" : "check_box_outline_blank"
                            size: Theme.iconSizeSmall ?? 16
                            color: chore.modelData.done ? Theme.primary : Theme.surfaceVariantText
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: chore.modelData.title
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            opacity: chore.modelData.done ? 0.5 : 1
                            font.strikeout: chore.modelData.done
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        StyledText {
                            visible: text !== ""
                            text: chore.modelData.time
                            color: chore.modelData.late ? Theme.error : Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            font.features: ({ tnum: 1 })
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
                StyledText {
                    anchors.centerIn: parent
                    visible: parent.count === 0
                    text: IsletClient.tasks?.status === "loading" ? IsletClient.t("Loading tasks…", "Memuat tugas…") : IsletClient.t("Nothing to do 🎉", "Tidak ada tugas 🎉")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }
                delegate: Rectangle {
                    id: task
                    required property var modelData
                    readonly property var chip: Due.dueChip(modelData.due, new Date(), IsletClient.lang)
                    width: ListView.view.width
                    height: 30
                    radius: Theme.cornerRadius
                    color: taskMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent"
                    MouseArea {
                        id: taskMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cmd("task-done", { id: task.modelData.id, done: true })
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingXS
                        anchors.rightMargin: Theme.spacingXS
                        spacing: Theme.spacingS
                        DIcon {
                            name: taskMouse.containsMouse ? "check_circle" : "radio_button_unchecked"
                            size: Theme.iconSizeSmall ?? 16
                            color: /tinggi|high/i.test(task.modelData.priority) ? Theme.error : Theme.surfaceVariantText
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: task.modelData.title
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        StyledText {
                            visible: text !== ""
                            text: task.chip.text
                            color: task.chip.late ? Theme.error : Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }
        }
    }
    DuePicker {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 130
        visible: root.picking && !root.compact
        value: root.dueText
        marks: root.dueDays
        lang: IsletClient.lang
        textColor: Theme.surfaceText
        subColor: Theme.surfaceVariantText
        accentColor: Theme.primary
        accentTextColor: Theme.onPrimary
        hoverColor: Theme.surfaceContainerHighest
        tileColor: Theme.surfaceContainerHigh
        errorColor: Theme.error
        fontFamily: Theme.fontFamily
        fontSize: Theme.fontSizeMedium
        onChosen: (text, done) => {
            root.dueText = text;
            root.addError = "";
            if (done) {
                root.picking = false;
                taskField.forceActiveFocus();
            }
        }
    }
    // [＋ New task……] [📅 due] [Add]
    RowLayout {
        Layout.fillWidth: true
        visible: (root.day?.enabled ?? false) && !root.compact
        spacing: Theme.spacingS
        DTextField {
            id: taskField
            Layout.fillWidth: true
            Layout.minimumWidth: 80
            enabled: root.day?.canAdd ?? false
            placeholderText: IsletClient.t("＋ New task", "＋ Tugas baru")
            onAccepted: root.submit()
        }
        // The due date picked, or "Due"; opens the calendar.
        DButton {
            visible: root.canDue
            enabled: root.day?.canAdd ?? false
            iconName: root.picking ? "expand_more" : "event"
            text: root.dueText.trim() === "" ? IsletClient.t("Due", "Tenggat")
                : root.dueParsed ? Due.dueChip(root.dueParsed.due, new Date(new Date().setHours(0, 0, 0, 0)), IsletClient.lang).text
                : "?"
            backgroundColor: root.picking || root.dueText.trim() !== "" ? Theme.primaryContainer : Theme.surfaceContainerHigh
            textColor: root.picking || root.dueText.trim() !== "" ? Theme.onPrimaryContainer : Theme.surfaceText
            tooltipText: IsletClient.t("Pick a due date", "Pilih tenggat")
            onClicked: root.picking = !root.picking
        }
        DButton {
            enabled: (root.day?.canAdd ?? false) && taskField.text.trim() !== ""
            iconName: "add"
            text: IsletClient.t("Add", "Tambah")
            backgroundColor: Theme.primary
            textColor: Theme.onPrimary
            onClicked: root.submit()
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: root.addError !== "" && !root.compact
        wrapMode: Text.WordWrap
        text: root.addError
        color: Theme.error
        font.pixelSize: Theme.fontSizeSmall
    }
    // "Synced 3 min ago ⟳": click to load again.
    RowLayout {
        Layout.fillWidth: true
        visible: (root.day?.enabled ?? false) && !root.compact && !root.picking
        spacing: Theme.spacingXS
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            text: root.day?.sync ?? ""
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }
        DIcon {
            name: "refresh"
            size: 16
            color: refreshMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText
            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cmd("today-refresh")
            }
        }
    }
}
