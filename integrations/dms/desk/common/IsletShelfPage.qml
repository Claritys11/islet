import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets

// The Shelf: files parked on Islet; click to open, paste what you copied.
// Drawn with DMS's widgets, fed by Islet over its socket (IsletClient); the
// DMS dashboard's Islet tab and the Shelf card both show it.
ColumnLayout {
    id: root

    // Fewer details for a small card; one row for a card one cell tall.
    property bool compact: false
    property bool strip: false
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
    RowLayout {
        visible: !root.strip
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true
            text: root.shelf.length ? IsletClient.t(`${root.shelf.length} file${root.shelf.length === 1 ? "" : "s"} · click to open`, `${root.shelf.length} file · klik untuk membuka`) : IsletClient.t("Copy a file and press Paste, or drop files on Islet's pill", "Copy file lalu tekan Tempel, atau taruh file di pill Islet")
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }
        DIconButton {
            iconName: "content_paste"
            onClicked: root.cmd("shelf-paste")
        }
        DIconButton {
            visible: root.shelf.length > 0
            iconName: "delete_sweep"
            onClicked: root.cmd("shelf-clear")
        }
    }
    // One row: the files as chips, sliding sideways, and Paste.
    RowLayout {
        visible: root.strip
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Theme.spacingS
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            clip: true
            spacing: Theme.spacingXS
            model: root.shelf
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.count === 0
                text: IsletClient.t("Copy a file, then Paste", "Copy file, lalu Tempel")
                wrapMode: Text.NoWrap
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
            delegate: Rectangle {
                id: chip
                required property var modelData
                y: (ListView.view.height - height) / 2
                width: Math.min(160, chipRow.implicitWidth + Theme.spacingM * 2)
                height: 32
                radius: 16
                opacity: modelData.missing ? 0.45 : 1
                color: chipMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS
                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: chip.modelData.dir ? "folder" : chip.modelData.image ? "image" : "description"
                        size: 16
                        color: Theme.primary
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 120)
                        text: chip.modelData.name
                        elide: Text.ElideMiddle
                        wrapMode: Text.NoWrap
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cmd("shelf-open", { path: chip.modelData.path })
                }
            }
        }
        DIconButton {
            iconName: "content_paste"
            onClicked: root.cmd("shelf-paste")
        }
    }
    GridView {
        visible: !root.strip
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        cellWidth: 96
        cellHeight: 96
        model: root.shelf
        delegate: Rectangle {
            id: tile
            required property var modelData
            width: 88
            height: 88
            radius: Theme.cornerRadius
            opacity: modelData.missing ? 0.45 : 1
            color: tileMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
            Image {
                id: thumb
                visible: tile.modelData.image && status === Image.Ready
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                width: 44
                height: 44
                source: tile.modelData.image ? "file://" + tile.modelData.path : ""
                sourceSize: Qt.size(88, 88)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            DIcon {
                visible: !thumb.visible
                anchors.horizontalCenter: parent.horizontalCenter
                y: 10
                name: tile.modelData.dir ? "folder" : "description"
                size: 36
                color: Theme.primary
            }
            StyledText {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                text: tile.modelData.missing ? IsletClient.t("not found", "tidak ditemukan") : tile.modelData.name
                elide: Text.ElideMiddle
                wrapMode: Text.NoWrap
                horizontalAlignment: Text.AlignHCenter
                color: tile.modelData.missing ? Theme.error : Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
            MouseArea {
                id: tileMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cmd("shelf-open", { path: tile.modelData.path })
            }
            DIcon {
                visible: tileMouse.containsMouse
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 4
                name: "close"
                size: 16
                color: Theme.surfaceVariantText
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cmd("shelf-remove", { path: tile.modelData.path })
                }
            }
        }
    }
}
