import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import "common"

// end4-pC's To-Do, showing your Notion Tasks through islet: open tasks as
// coloured pills (due date chip), tick to finish, "+" to add one.
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
    property bool saving: false
    property string addError: ""
    // The task whose 🗑 was clicked once; a second click deletes it.
    property string confirmDelete: ""
    property string deleting: ""

    function dueLabel(due): string {
        if (!due)
            return "";
        const d = new Date(due.length <= 10 ? due + "T00:00:00" : due);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const day = new Date(d);
        day.setHours(0, 0, 0, 0);
        const diff = Math.round((day - today) / 864e5);
        return diff < 0 ? IsletClient.t("Late", "Terlambat") : diff === 0 ? IsletClient.t("Today", "Hari ini") : diff === 1 ? IsletClient.t("Tomorrow", "Besok") : Qt.formatDate(d, "d MMM");
    }

    // Keeps the text until islet says Notion has the task (review I2).
    function submit(): void {
        const text = field.text.trim();
        if (text === "" || root.saving)
            return;
        root.saving = true;
        root.addError = "";
        requester.request("task-add", { text }, (ok, data, err) => {
            root.saving = false;
            if (!ok) {
                root.addError = err;
                return;
            }
            field.text = "";
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
                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.onPrimaryContainer
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    clip: true
                    readOnly: root.saving
                    onAccepted: root.submit()
                    Keys.onEscapePressed: root.adding = false
                    Text {
                        visible: !field.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.saving ? IsletClient.t("Saving…", "Menyimpan…") : IsletClient.t("New task, Enter to add", "Tugas baru, Enter untuk menambah")
                        color: Qt.alpha(Theme.onPrimaryContainer, 0.5)
                        font: field.font
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
                        readonly property string label: root.dueLabel(pill.modelData.due)
                        visible: label !== "" && !pill.modelData.done
                        anchors.right: del.left
                        anchors.rightMargin: del.visible ? 6 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: visible ? dueText.implicitWidth + 14 : 0
                        height: 22
                        radius: 11
                        color: label === IsletClient.t("Late", "Terlambat") ? Theme.error : Qt.alpha(pill.fg, 0.15)
                        Text {
                            id: dueText
                            anchors.centerIn: parent
                            text: due.label
                            color: due.label === IsletClient.t("Late", "Terlambat") ? Theme.onPrimary : pill.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall - 1
                        }
                    }
                }
            }
        }
    }
}
