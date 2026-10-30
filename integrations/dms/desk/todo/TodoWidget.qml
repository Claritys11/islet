import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import "common"
import "common/due/due.mjs" as Due
import "common/due"

// end4-pC's To-Do, showing your Notion Tasks through islet: open tasks as
// coloured pills (due date chip), tick to finish, "+" to add one with an
// optional due date.
DesktopPluginComponent {
    id: root

    minWidth: 260
    minHeight: 220
    // Only while typing a task, or about to (pointer on "+"): otherwise a
    // click on the desktop would take the keyboard from the window you're
    // working in (review I3).
    property bool acceptsKeyboardFocus: root.adding || card.actionHovered

    readonly property var tasks: IsletClient.tasks
    // Open tasks, plus the ones ticked here since DMS started, so a mis-tick
    // can be undone; tasks finished elsewhere don't fill the list (review M6).
    property var tickedHere: ({})
    readonly property var items: (root.tasks?.items ?? []).filter(t => !t.done || root.tickedHere[t.id])
    readonly property string statusText: !IsletClient.connected ? IsletClient.t("islet isn't running", "islet tidak berjalan")
        : root.tasks === null ? "…"
        : root.tasks.status === "loading" && root.items.length === 0 ? IsletClient.t("Loading tasks…", "Memuat tugas…")
        : root.tasks.status === "error" || root.tasks.status === "setup" ? (root.tasks.error || "Set up Today in islet")
        : root.items.length === 0 ? IsletClient.t("Nothing to do 🎉", "Tidak ada tugas 🎉")
        : root.tasks.message || ""
    property bool adding: false
    // The calendar for the due date, in the list's place.
    property bool picking: false
    // The due date as typed or picked ("6/11 14.00"), "" for none.
    property string dueText: ""
    readonly property var dueParsed: Due.parseDue(root.dueText, new Date())
    onAddingChanged: if (!adding)
        picking = false
    property bool saving: false
    property string addError: ""
    // The task whose 🗑 was clicked once; a second click deletes it.
    property string confirmDelete: ""
    property string deleting: ""

    // The task list has a due date column (older islets don't say: assume so).
    readonly property bool canDue: root.tasks?.canDue ?? true

    // Keeps the text until islet says Notion has the task (review I2); a
    // due date that isn't one stops it there.
    function submit(): void {
        const text = field.text.trim();
        if (text === "" || root.saving)
            return;
        const due = root.canDue ? root.dueParsed : { due: "" };
        if (!due) {
            root.addError = IsletClient.t("The due date isn't a date: try “besok”, “jum 14.00” or “5/11”.", "Tenggatnya bukan tanggal: coba “besok”, “jum 14.00” atau “5/11”.");
            root.picking = true;
            return;
        }
        root.saving = true;
        root.addError = "";
        requester.request("task-add", due.due ? { text, due: due.due } : { text }, (ok, data, err) => {
            root.saving = false;
            if (!ok) {
                root.addError = err;
                return;
            }
            field.text = "";
            root.dueText = "";
            root.adding = false;
        }, 150000);
    }

    Requester {
        id: requester
    }

    // Into Notion's trash (restorable there for 30 days).
    function remove(id): void {
        if (root.confirmDelete !== id) {
            root.confirmDelete = id;
            return;
        }
        root.confirmDelete = "";
        root.deleting = id;
        root.addError = "";
        requester.request("task-delete", { id }, (ok, data, err) => {
            root.deleting = "";
            if (!ok)
                root.addError = err;
        }, 150000);
    }

    // A "Hapus?" not confirmed within 3 s goes back to 🗑.
    Timer {
        interval: 3000
        running: root.confirmDelete !== ""
        onTriggered: root.confirmDelete = ""
    }

    DeskCard {
        id: card
        anchors.fill: parent
        title: "To-Do"
        actionIcon: root.adding ? "×" : "+"
        cardColor: Theme.primaryContainer
        textColor: Theme.onPrimaryContainer
        accentColor: Theme.primary
        radius: Theme.cornerRadius * 1.5
        fontFamily: Theme.fontFamily
        onActionClicked: {
            root.adding = !root.adding;
            if (root.adding)
                Qt.callLater(() => field.forceActiveFocus());
        }

        Column {
            anchors.fill: parent
            spacing: 8

            Rectangle {
                visible: root.adding
                width: parent.width
                height: 40
                radius: 14
                color: Qt.alpha(Theme.onPrimaryContainer, 0.1)
                border.color: Theme.primary
                border.width: 1
                // Enter, or this, saves the task.
                Rectangle {
                    id: addButton
                    readonly property bool ready: field.text.trim() !== "" && !root.saving
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: addText.implicitWidth + 20
                    height: 30
                    radius: 11
                    opacity: ready ? 1 : 0.4
                    color: Theme.primary
                    Text {
                        id: addText
                        anchors.centerIn: parent
                        text: root.saving ? "…" : IsletClient.t("Add", "Tambah")
                        color: Theme.onPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: addButton.ready
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.submit()
                    }
                }
                TextInput {
                    id: field
                    anchors.left: parent.left
                    anchors.right: addButton.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.onPrimaryContainer
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    clip: true
                    readOnly: root.saving
                    onAccepted: root.submit()
                    Keys.onEscapePressed: {
                        if (root.picking)
                            root.picking = false;
                        else
                            root.adding = false;
                    }
                    Text {
                        visible: !field.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.saving ? IsletClient.t("Saving…", "Menyimpan…") : IsletClient.t("New task", "Tugas baru")
                        color: Qt.alpha(Theme.onPrimaryContainer, 0.5)
                        font: field.font
                    }
                }
            }

            // 📅 the due date picked, or "Tenggat (opsional)": opens the
            // calendar in the list's place; × takes the date away.
            Rectangle {
                id: dueChip
                readonly property bool set: root.dueText.trim() !== ""
                visible: root.adding && root.canDue
                width: parent.width
                height: 32
                radius: 12
                color: root.picking || set ? Qt.alpha(Theme.primary, dueMouse.containsMouse ? 0.3 : 0.2) : Qt.alpha(Theme.onPrimaryContainer, dueMouse.containsMouse ? 0.12 : 0.06)
                MouseArea {
                    id: dueMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picking = !root.picking
                }
                Text {
                    anchors.left: parent.left
                    anchors.right: clearDue.left
                    anchors.leftMargin: 12
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: "📅  " + (!dueChip.set ? IsletClient.t("Due date (optional)", "Tenggat (opsional)")
                        : root.dueParsed ? Due.dueChip(root.dueParsed.due, new Date(new Date().setHours(0, 0, 0, 0)), IsletClient.lang).text
                        : IsletClient.t("Not a date", "Bukan tanggal"))
                    color: dueChip.set ? (root.dueParsed ? Theme.onPrimaryContainer : Theme.error) : Qt.alpha(Theme.onPrimaryContainer, 0.6)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
                Text {
                    id: clearDue
                    visible: dueChip.set
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "×"
                    color: Theme.onPrimaryContainer
                    font.pixelSize: Theme.fontSizeMedium
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dueText = ""
                    }
                }
            }

            DuePicker {
                visible: root.adding && root.picking && root.canDue
                width: parent.width
                height: Math.max(140, parent.height - y)
                value: root.dueText
                marks: root.items.filter(t => t.due && !t.done).map(t => String(t.due).slice(0, 10))
                lang: IsletClient.lang
                textColor: Theme.onPrimaryContainer
                subColor: Qt.alpha(Theme.onPrimaryContainer, 0.6)
                accentColor: Theme.primary
                accentTextColor: Theme.onPrimary
                hoverColor: Qt.alpha(Theme.onPrimaryContainer, 0.14)
                tileColor: Qt.alpha(Theme.onPrimaryContainer, 0.06)
                errorColor: Theme.error
                fontFamily: Theme.fontFamily
                fontSize: Theme.fontSizeMedium
                onChosen: (text, done) => {
                    root.dueText = text;
                    root.addError = "";
                    if (done) {
                        root.picking = false;
                        field.forceActiveFocus();
                    }
                }
            }

            Text {
                visible: root.statusText !== "" || root.addError !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.addError !== "" ? root.addError : root.statusText
                color: Qt.alpha(Theme.onPrimaryContainer, 0.7)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            ListView {
                visible: !(root.adding && root.picking && root.canDue)
                width: parent.width
                height: parent.height - y
                clip: true
                spacing: 8
                model: root.items
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: pill
                    required property var modelData
                    required property int index
                    // end4's pills: a few container colours in turn.
                    readonly property color bg: modelData.done ? Qt.alpha(Theme.onPrimaryContainer, 0.08)
                        : [Theme.primary, Theme.secondaryContainer, Theme.surfaceContainerHigh][index % 3]
                    readonly property color fg: modelData.done ? Qt.alpha(Theme.onPrimaryContainer, 0.5)
                        : index % 3 === 0 ? Theme.onPrimary : Theme.surfaceText
                    width: ListView.view.width
                    height: 46
                    radius: 14
                    color: bg

                    Rectangle {
                        id: check
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        radius: 12
                        color: pill.modelData.done ? pill.fg : "transparent"
                        border.color: pill.fg
                        border.width: 2
                        Text {
                            visible: pill.modelData.done
                            anchors.centerIn: parent
                            text: "✓"
                            color: pill.bg
                            font.pixelSize: 14
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!pill.modelData.done)
                                    root.tickedHere = Object.assign({}, root.tickedHere, { [pill.modelData.id]: true });
                                IsletClient.send({ cmd: "task-done", id: pill.modelData.id, done: !pill.modelData.done });
                            }
                        }
                    }

                    Text {
                        anchors.left: check.right
                        anchors.leftMargin: 10
                        anchors.right: due.left
                        anchors.rightMargin: 8
                        opacity: root.deleting === pill.modelData.id ? 0.4 : 1
                        anchors.verticalCenter: parent.verticalCenter
                        text: pill.modelData.title
                        textFormat: Text.PlainText
                        color: pill.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMedium
                        font.strikeout: pill.modelData.done
                        elide: Text.ElideRight
                    }

                    HoverHandler {
                        id: pillHover
                    }

                    Rectangle {
                        id: del
                        readonly property bool asking: root.confirmDelete === pill.modelData.id
                        visible: pillHover.hovered || asking
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: visible ? delText.implicitWidth + 14 : 0
                        height: 26
                        radius: 13
                        color: asking ? Theme.error : delArea.containsMouse ? Qt.alpha(pill.fg, 0.25) : Qt.alpha(pill.fg, 0.12)
                        Text {
                            id: delText
                            anchors.centerIn: parent
                            text: del.asking ? IsletClient.t("Delete?", "Hapus?") : "🗑"
                            color: del.asking ? Theme.onError : pill.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        MouseArea {
                            id: delArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: root.deleting === ""
                            onClicked: root.remove(pill.modelData.id)
                        }
                    }

                    Rectangle {
                        id: due
                        readonly property var chip: Due.dueChip(pill.modelData.due, new Date(), IsletClient.lang)
                        readonly property string label: chip.text
                        visible: label !== "" && !pill.modelData.done
                        anchors.right: del.left
                        anchors.rightMargin: del.visible ? 6 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: visible ? dueText.implicitWidth + 14 : 0
                        height: 22
                        radius: 11
                        color: chip.late ? Theme.error : Qt.alpha(pill.fg, 0.15)
                        Text {
                            id: dueText
                            anchors.centerIn: parent
                            text: due.label
                            color: due.chip.late ? Theme.onError : pill.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall - 1
                        }
                    }
                }
            }
        }
    }
}
