import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets

// The Checklist's to-dos (Islet's own or a Notion page): tick, add, remove.
// Drawn with DMS's widgets, fed by Islet over its socket (IsletClient); the
// DMS dashboard's Islet tab and the Checklist card both show it.
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
    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        model: root.checklist?.items ?? []
        StyledText {
            anchors.centerIn: parent
            visible: parent.count === 0
            text: "Nothing to do 🎉"
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
        }
        delegate: Rectangle {
            id: todo
            required property var modelData
            width: ListView.view.width
            height: 34
            radius: Theme.cornerRadius
            color: todoMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent"
            MouseArea {
                id: todoMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cmd("checklist-check", { id: todo.modelData.id, checked: !todo.modelData.checked })
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingXS
                anchors.rightMargin: Theme.spacingXS
                spacing: Theme.spacingS
                DIcon {
                    name: todo.modelData.checked ? "check_box" : "check_box_outline_blank"
                    size: Theme.iconSize
                    color: todo.modelData.checked ? Theme.primary : Theme.surfaceVariantText
                }
                StyledText {
                    Layout.fillWidth: true
                    text: todo.modelData.text
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    color: todo.modelData.checked ? Theme.surfaceVariantText : Theme.surfaceText
                    font.strikeout: todo.modelData.checked
                    font.pixelSize: Theme.fontSizeMedium
                }
                DIcon {
                    visible: todoMouse.containsMouse
                    name: "close"
                    size: 16
                    color: Theme.surfaceVariantText
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cmd("checklist-remove", { id: todo.modelData.id })
                    }
                }
            }
        }
    }
    RowLayout {
        visible: !root.compact
        Layout.fillWidth: true
        spacing: Theme.spacingS
        DTextField {
            id: todoField
            Layout.fillWidth: true
            placeholderText: root.checklist?.source === "notion" ? "＋ To-do baru (Notion)" : "＋ To-do baru"
            onAccepted: {
                if (todoField.text.trim() === "")
                    return;
                root.cmd("checklist-add", { text: todoField.text });
                todoField.text = "";
            }
        }
        DIconButton {
            visible: (root.checklist?.items ?? []).some(i => i.checked)
            iconName: "done_all"
            onClicked: root.cmd("checklist-clear-done")
        }
    }
}
