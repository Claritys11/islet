import QtQuick
import QtQuick.Layouts

// Shelf tab: files parked on the notch. Drop files anywhere on the island,
// or paste what you copied (Ctrl+V, or the paste button), to add them; drag
// a tile out to drop the file into another app; click to open it.
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
            text: ShelfService.pasteNote || Lang.t("Drop files here to keep them close", "Taruh file di sini supaya selalu dekat")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 14
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Lang.t("…or copy them and press Ctrl+V. Drag them out again into any app.", "…atau copy lalu tekan Ctrl+V. Seret keluar lagi ke aplikasi mana pun.")
            color: Theme.subtext
            font.family: Theme.font
            font.pixelSize: 12
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: pasteRow.implicitWidth + 24
            implicitHeight: 32
            radius: 16
            color: pasteMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
            Row {
                id: pasteRow
                anchors.centerIn: parent
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "content_paste"
                    color: Theme.primary
                    font.family: Theme.iconFont
                    font.pixelSize: 17
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Lang.t("Paste", "Tempel")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13
                }
            }
            MouseArea {
                id: pasteMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ShelfService.paste()
            }
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
                text: ShelfService.pasteNote || Lang.t(`${root.items.length} file${root.items.length === 1 ? "" : "s"} · drag one out, or click to open`, `${root.items.length} file · seret keluar, atau klik untuk membuka`)
                color: ShelfService.pasteNote ? Theme.primary : Theme.subtext
                font.family: Theme.font
                font.pixelSize: 12
            }
            NotchIconButton {
                icon: "content_paste"
                size: 26
                tint: Theme.subtext
                onClicked: ShelfService.paste()
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
                        // A picture of the tile, taken as the pointer comes
                        // near, so a drag carries it (kept, or it's freed).
                        property var shot: null

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
                            text: tile.modelData.missing ? Lang.t("not found", "tidak ditemukan") : tile.modelData.name
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
                            Drag.imageSource: tile.shot?.url ?? ""
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
                            onContainsMouseChanged: if (containsMouse)
                                tile.grabToImage(r => tile.shot = r)
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
