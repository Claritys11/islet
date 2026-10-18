import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Checklist tab: local or Notion to-dos, with an input to add new ones.
Item {
    id: root

    readonly property var todo: ChecklistService
    property alias inputFocused: input.activeFocus
    property alias draft: input.text

    function focusInput() {
        input.forceActiveFocus();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.todo.useNotion ? "Notion" : "Checklist"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Text {
                text: root.todo.items.length ? `${root.todo.doneCount}/${root.todo.items.length}` : ""
                color: Theme.subtext
                font.family: Theme.font
                font.pixelSize: 12
            }
            Item {
                Layout.fillWidth: true
            }
            NotchIconButton {
                icon: "done_all"
                size: 28
                visible: root.todo.doneCount > 0
                onClicked: root.todo.clearDone()
            }
            NotchIconButton {
                icon: "refresh"
                size: 28
                visible: root.todo.useNotion
                onClicked: root.todo.refresh()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.todo.status === "setup" || root.todo.status === "error"
            text: root.todo.error
            color: root.todo.status === "error" ? Theme.danger : Theme.subtext
            wrapMode: Text.WordWrap
            font.family: Theme.font
            font.pixelSize: 12
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.todo.items
            boundsBehavior: Flickable.StopAtBounds

            Text {
                anchors.centerIn: parent
                visible: list.count === 0 && root.todo.status === "ready"
                text: "Nothing to do ✨"
                color: Theme.subtext
                font.family: Theme.font
                font.pixelSize: 13
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                width: ListView.view.width
                height: 34
                radius: 10
                color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.todo.setChecked(row.modelData.id, !row.modelData.checked)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 4
                    spacing: 10

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        color: row.modelData.checked ? Theme.primary : "transparent"
                        border.width: row.modelData.checked ? 0 : 2
                        border.color: Theme.subtext
                        Text {
                            anchors.centerIn: parent
                            visible: row.modelData.checked
                            text: "check"
                            color: Theme.onPrimary
                            font.family: Theme.iconFont
                            font.pixelSize: 14
                            font.weight: Font.Bold
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.text
                        color: row.modelData.checked ? Theme.subtext : Theme.text
                        opacity: row.modelData.checked ? 0.6 : 1
                        font.strikeout: row.modelData.checked
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 14
                    }
                    NotchIconButton {
                        icon: "close"
                        size: 26
                        opacity: rowMouse.containsMouse ? 1 : 0.25
                        tint: Theme.subtext
                        onClicked: root.todo.remove(row.modelData.id)
                    }
                }
            }
        }

        TextField {
            id: input
            Layout.fillWidth: true
            enabled: root.todo.status !== "setup"
            placeholderText: "Add a task…"
            placeholderTextColor: Theme.subtext
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 14
            leftPadding: 14
            background: Rectangle {
                radius: 12
                color: Theme.raised
                border.width: input.activeFocus ? 1 : 0
                border.color: Theme.primary
            }
            onAccepted: {
                root.todo.add(text);
                text = "";
            }
        }
    }
}
