import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "today/agenda.mjs" as Agenda
import "today/timetable.mjs" as Timetable

// "Kalender" tab: a month on the left (dots in each calendar's colour, red
// Sundays, today filled), the chosen day's agenda on the right: Google
// events, Classroom assignments, Notion deadlines and the day's lessons.
Item {
    id: root

    readonly property var t: TodayService
    property alias inputFocused: input.activeFocus
    property alias draft: input.text
    // Shown on screen: load the month's events.
    property bool active: false

    readonly property var monthNames: Lang.months
    readonly property var dayNames: Lang.days

    property int year: new Date().getFullYear()
    property int month: new Date().getMonth()
    property var selected: new Date()
    readonly property var grid: Agenda.monthGrid(year, month)
    readonly property var today: new Date(t.now)

    // Events of the six weeks on screen; `req` drops answers to months
    // already left.
    property var events: []
    property int req: 0
    property bool loading: false

    function load() {
        const n = ++req;
        loading = true;
        const from = grid[0], to = new Date(grid[41].getFullYear(), grid[41].getMonth(), grid[41].getDate() + 1);
        DcalService.listEvents(from, to, "", (ok, evs) => {
            if (n !== req)
                return;
            loading = false;
            if (ok)
                events = evs;
        });
    }
    function show(y, m) {
        const d = new Date(y, m, 1);
        year = d.getFullYear();
        month = d.getMonth();
    }
    function goToday() {
        selected = new Date();
        show(selected.getFullYear(), selected.getMonth());
    }
    function pick(d) {
        selected = d;
        if (d.getMonth() !== month)
            show(d.getFullYear(), d.getMonth());
    }

    onGridChanged: if (active)
        load()
    onActiveChanged: if (active)
        load()
    Connections {
        target: TodayService
        function onEventsLoaded() {
            if (root.active)
                root.load();
        }
    }

    function key(d) {
        return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
    }
    // Up to three dots a day: a Notion deadline, then events' colours.
    readonly property var marks: {
        const out = {};
        for (const d of grid) {
            const c = Agenda.eventsOn(events, d, today, DcalService.calendars, Lang.code).map(e => e.color);
            if (Agenda.tasksOn(t.tasks, d).length)
                c.unshift(Theme.primary);
            if (c.length)
                out[key(d)] = c.slice(0, 3);
        }
        return out;
    }

    function priorityColor(p) {
        return /tinggi|high/i.test(p) ? Theme.danger : /sedang|medium/i.test(p) ? "#ffd58a" : /rendah|low/i.test(p) ? "#9de6b5" : Theme.primary;
    }
    // The chosen day: events and deadlines by time, all-day ones first.
    readonly property var dayItems: {
        const evs = Agenda.eventsOn(events, selected, today, DcalService.calendars, Lang.code).map(e => ({
            key: e.key,
            kind: e.readOnly ? "classroom" : "event",
            title: e.title,
            time: e.readOnly && !e.allDay ? Lang.t(`due ${e.time.slice(0, 5)}`, `tenggat ${e.time.slice(0, 5)}`) : e.time,
            sub: e.calendar.includes("@") ? "Google" : e.calendar,
            until: e.until,
            color: e.color,
            now: e.now,
            past: e.past,
            sortAt: e.start.getTime() - (e.allDay ? 1 : 0)
        }));
        const tasks = Agenda.tasksOn(t.tasks, selected, Lang.code).map(x => ({
            key: x.key,
            kind: "task",
            title: x.title,
            time: x.time,
            sub: "Notion",
            until: "",
            color: root.priorityColor(x.priority),
            now: false,
            past: x.due < today,
            sortAt: x.due.getTime()
        }));
        return evs.concat(tasks).sort((a, b) => a.sortAt - b.sortAt);
    }
    readonly property var dayLessons: t.o.todayEnabled ? Timetable.lessonsOn(t.allLessons, selected) : []

    RowLayout {
        anchors.fill: parent
        spacing: 18

        // ── The month ─────────────────────────────────────────────
        ColumnLayout {
            Layout.preferredWidth: 7 * 38
            Layout.maximumWidth: 7 * 38
            Layout.fillHeight: true
            spacing: 4

            // The wheel turns the months.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                // A touchpad sends many small steps: one month per notch's worth.
                property real acc: 0
                onWheel: event => {
                    acc += event.angleDelta.y;
                    if (Math.abs(acc) < 120)
                        return;
                    root.show(root.year, root.month + (acc < 0 ? 1 : -1));
                    acc = 0;
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    elide: Text.ElideRight
                    text: `${root.monthNames[root.month]} <font color="${Theme.subtext}">${root.year}</font>`
                    textFormat: Text.StyledText
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
                NotchIconButton {
                    icon: "chevron_left"
                    size: 26
                    tint: Theme.subtext
                    onClicked: root.show(root.year, root.month - 1)
                }
                Rectangle {
                    readonly property bool here: root.year === root.today.getFullYear() && root.month === root.today.getMonth() && Agenda.sameDay(root.selected, root.today)
                    implicitWidth: todayText.implicitWidth + 16
                    implicitHeight: 24
                    radius: 12
                    color: here ? "transparent" : todayMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)
                    border.width: here ? 1 : 0
                    border.color: Theme.outline
                    Text {
                        id: todayText
                        anchors.centerIn: parent
                        text: Lang.t("Today", "Hari ini")
                        color: parent.here ? Theme.subtext : Theme.text
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: todayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.goToday()
                    }
                }
                NotchIconButton {
                    icon: "chevron_right"
                    size: 26
                    tint: Theme.subtext
                    onClicked: root.show(root.year, root.month + 1)
                }
            }

            // Monday first; Sunday in red, as on Indonesian calendars.
            Row {
                Repeater {
                    model: Lang.id ? ["S", "S", "R", "K", "J", "S", "M"] : ["M", "T", "W", "T", "F", "S", "S"]
                    Text {
                        required property string modelData
                        required property int index
                        width: 38
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: index === 6 ? Theme.danger : Theme.subtext
                        opacity: 0.8
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            Grid {
                id: cells
                columns: 7
                Layout.fillHeight: true

                Repeater {
                    model: root.grid
                    Item {
                        id: cell
                        required property var modelData
                        readonly property bool inMonth: modelData.getMonth() === root.month
                        readonly property bool isToday: Agenda.sameDay(modelData, root.today)
                        readonly property bool isSelected: Agenda.sameDay(modelData, root.selected)
                        readonly property var dots: root.marks[root.key(modelData)] ?? []
                        width: 38
                        height: Math.min(38, (cells.parent.height - 50) / 6)

                        Rectangle {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -3
                            width: 30
                            height: 30
                            radius: 15
                            color: cell.isToday ? Theme.primary : cellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                            border.width: cell.isSelected && !cell.isToday ? 1.5 : 0
                            border.color: Theme.primary
                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: cell.modelData.getDate()
                                color: cell.isToday ? Theme.onPrimary : cell.modelData.getDay() === 0 ? Theme.danger : Theme.text
                                opacity: cell.inMonth || cell.isToday ? 1 : 0.3
                                font.family: Theme.font
                                font.pixelSize: 13
                                font.weight: cell.isToday || cell.isSelected ? Font.Bold : Font.Normal
                                font.features: ({ tnum: 1 })
                            }
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 1
                            spacing: 2
                            opacity: cell.inMonth ? 1 : 0.4
                            Repeater {
                                model: cell.dots
                                Rectangle {
                                    required property var modelData
                                    width: 4
                                    height: 4
                                    radius: 2
                                    color: modelData
                                }
                            }
                        }
                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pick(cell.modelData)
                        }
                    }
                }
            }
        }

        // ── The chosen day ────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: `${root.dayNames[root.selected.getDay()]}, ${root.selected.getDate()} ${root.monthNames[root.selected.getMonth()].toUpperCase()}`
                    color: Theme.subtext
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.letterSpacing: 0.6
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    visible: root.loading
                    text: "sync"
                    color: Theme.subtext
                    font.family: Theme.iconFont
                    font.pixelSize: 14
                    RotationAnimation on rotation {
                        running: root.loading
                        from: 360
                        to: 0
                        duration: 1000
                        loops: Animation.Infinite
                    }
                }
                NotchIconButton {
                    icon: "open_in_new"
                    size: 24
                    tint: Theme.subtext
                    onClicked: DcalService.show()
                }
            }

            // The day's lessons in one line; the Hari ini tab lists them.
            RowLayout {
                visible: root.dayLessons.length > 0
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "school"
                    color: Theme.subtext
                    font.family: Theme.iconFont
                    font.pixelSize: 15
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: {
                        const l = root.dayLessons;
                        if (!l.length)
                            return "";
                        const span = `${l[0].start}–${l[l.length - 1].end}`;
                        return Lang.t(`${l.length} lessons · ${span}`, `${l.length} pelajaran · ${span.replace(/:/g, ".")}`);
                    }
                    color: Theme.subtext
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: root.dayItems
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: list.count === 0 && !root.loading
                    spacing: 4
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "event_available"
                        color: Theme.subtext
                        opacity: 0.6
                        font.family: Theme.iconFont
                        font.pixelSize: 28
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: DcalService.available ? Lang.t("No events", "Tidak ada acara") : Lang.t("Dank Calendar isn't running", "Dank Calendar tidak berjalan")
                        color: Theme.subtext
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }

                delegate: Rectangle {
                    id: item
                    required property var modelData
                    width: ListView.view.width
                    height: 42
                    radius: 10
                    color: modelData.now ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : itemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.03)
                    opacity: modelData.past ? 0.45 : 1

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: item.modelData.kind === "task" ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: if (item.modelData.kind !== "task")
                            DcalService.show()
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 9
                        Rectangle {
                            width: 3
                            Layout.preferredHeight: 26
                            radius: 2
                            color: item.modelData.color
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: item.modelData.title
                                elide: Text.ElideRight
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 13
                            }
                            Text {
                                Layout.fillWidth: true
                                text: [item.modelData.time, item.modelData.until, item.modelData.sub].filter(x => x).join(" · ")
                                elide: Text.ElideRight
                                color: item.modelData.now ? Theme.primary : Theme.subtext
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.features: ({ tnum: 1 })
                            }
                        }
                        Text {
                            visible: item.modelData.kind !== "event"
                            text: item.modelData.kind === "task" ? "flag" : "school"
                            color: Theme.subtext
                            font.family: Theme.iconFont
                            font.pixelSize: 15
                        }
                    }
                }
            }

            // ＋ a new event on the chosen day, typed in one line.
            TextField {
                id: input
                readonly property var parsed: Agenda.parseEvent(text, root.selected, root.t.o.todayEventMinutes, Lang.code)
                property bool saving: false
                property string problem: ""
                Layout.fillWidth: true
                enabled: DcalService.available && root.t.targetCalendar !== "" && !saving
                placeholderText: Lang.t("＋ New event — e.g. Meeting 19:00-20:30", "＋ Acara baru — mis. Rapat 19.00-20.30")
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
                onTextChanged: problem = ""
                onAccepted: {
                    if (!parsed)
                        return;
                    saving = true;
                    root.t.addEvent(text, root.selected, (ok, err) => {
                        saving = false;
                        if (!ok)
                            return problem = err;
                        text = "";
                        root.load();
                    });
                }
            }
            // What Enter will save, or why it couldn't.
            Text {
                Layout.fillWidth: true
                visible: input.text !== "" || input.problem !== "" || input.saving
                elide: Text.ElideRight
                text: input.problem ? input.problem : input.saving ? Lang.t("Saving…", "Menyimpan…") : input.parsed ? Lang.t(`${input.parsed.label} · Enter to save`, `${input.parsed.label} · Enter untuk simpan`) : Lang.t("Give the event a name", "Tulis nama acaranya")
                color: input.problem ? Theme.danger : Theme.subtext
                font.family: Theme.font
                font.pixelSize: 11
            }
        }
    }
}
