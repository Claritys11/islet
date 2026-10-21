import QtQuick
import QtQuick.Layouts

// Shelf tab: files parked on the notch. Drop files anywhere on the island to
// add them; drag a tile out to drop the file into another app; click to
// open it.
Item {
    id: root

    readonly property var items: ShelfService.items

    // Nothing parked yet: say how it works.
    Column {
        anchors.centerIn: parent
        visible: root.items.length === 0
        spacing: 8
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "move_to_inbox"
            color: Theme.subtext
            font.family: Theme.iconFont
            font.pixelSize: 36
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Drop files here to keep them close"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 14
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Drag them out again into any app. The files stay where they are."
            color: Theme.subtext
            font.family: Theme.font
            font.pixelSize: 12
        }
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.items.length > 0
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: `${root.items.length} file${root.items.length === 1 ? "" : "s"} · drag one out, or click to open`
                color: Theme.subtext
                font.family: Theme.font
                font.pixelSize: 12
            }
            NotchIconButton {
                icon: "delete_sweep"
                size: 26
                tint: Theme.subtext
                onClicked: ShelfService.clear()
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: grid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Flow {
                id: grid
                width: parent.width
                spacing: 8

                Repeater {
                    model: root.items

                    Rectangle {
                        id: tile
                        required property var modelData
                        width: 92
                        height: 92
                        radius: 14
                        color: tileMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)
                        // Moved somewhere Islet couldn't find, or deleted.
                        opacity: modelData.missing ? 0.45 : 1

                        Image {
                            id: thumb
                            visible: ShelfService.isImage(tile.modelData.name) && status === Image.Ready
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 8
                            width: 48
                            height: 48
                            source: ShelfService.isImage(tile.modelData.name) ? ShelfService.url(tile.modelData.path) : ""
                            sourceSize: Qt.size(96, 96)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Text {
                            visible: !thumb.visible
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 10
                            text: ShelfService.icon(tile.modelData)
                            color: Theme.primary
                            font.family: Theme.iconFont
                            font.pixelSize: 38
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 6
                            text: tile.modelData.missing ? "tidak ditemukan" : tile.modelData.name
                            color: tile.modelData.missing ? Theme.danger : Theme.text
                            elide: Text.ElideMiddle
                            horizontalAlignment: Text.AlignHCenter
                            font.family: Theme.font
                            font.pixelSize: 11
                        }

                        // What actually travels: an invisible stand-in, so
                        // the tile stays put while you drag.
                        Item {
                            id: dragProxy
                            width: tile.width
                            height: tile.height
                            Drag.active: tileMouse.drag.active
                            Drag.dragType: Drag.Automatic
                            Drag.supportedActions: Qt.CopyAction | Qt.LinkAction | Qt.MoveAction
                            Drag.mimeData: ({
                                    "text/uri-list": ShelfService.url(tile.modelData.path) + "\r\n",
                                    "text/plain": tile.modelData.path
                                })
                            Drag.imageSource: thumb.visible ? thumb.source : ""
                            Drag.hotSpot.x: width / 2
                            Drag.hotSpot.y: height / 2
                            // Moved by the drop? Follow it.
                            Drag.onDragFinished: {
                                ShelfService.dragging = false;
                                ShelfService.followSoon();
                            }
                        }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            drag.target: dragProxy
                            drag.threshold: 6
                            onPressedChanged: if (!pressed)
                                ShelfService.dragging = false
                            drag.onActiveChanged: if (drag.active)
                                ShelfService.dragging = true
                            onReleased: {
                                dragProxy.x = 0;
                                dragProxy.y = 0;
                            }
                            onClicked: tile.modelData.missing ? ShelfService.follow() : Qt.openUrlExternally(ShelfService.url(tile.modelData.path))
                        }

                        NotchIconButton {
                            visible: tileMouse.containsMouse || containsMouse
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 2
                            icon: "close"
                            size: 22
                            tint: Theme.subtext
                            onClicked: ShelfService.remove(tile.modelData.path)
                        }
                    }
                }
            }
        }
    }
}
