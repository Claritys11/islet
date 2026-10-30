import QtQuick
import QtQuick.Layouts
import "due.mjs" as Due

// A month to click a task's due date on: quick days beside the month's
// name, times down the side, and a line to type one ("jum 14.00") under
// it. It edits the due text (`value`) through `chosen`, so clicking and
// typing stay one thing. Sized to whatever room it gets (a 4×3 DMS card
// up to the notch). Plain QtQuick: DMS's widgets and Islet's notch give it
// their colours.
Item {
    id: root

    // The due text, and the text after a click or a key (`done`: the
    // picker can close).
    property string value: ""
    signal chosen(string text, bool done)
    // Days that already have a task due ("2026-11-05"): a dot under them.
    property var marks: []
    // Typing in its line (a shell gives the keyboard while it is).
    readonly property bool typing: typed.activeFocus

    property string lang: "id"
    property color textColor: "white"
    property color subColor: "#aaa"
    property color accentColor: "#8ab4f8"
    property color accentTextColor: "black"
    property color hoverColor: Qt.rgba(1, 1, 1, 0.08)
    property color tileColor: Qt.rgba(1, 1, 1, 0.04)
    property color errorColor: "#f28b82"
    property string fontFamily: ""
    property int fontSize: 12

    readonly property var sel: Due.picked(root.value, new Date())
    property int year: new Date().getFullYear()
    property int month: new Date().getMonth()
    readonly property var cells: Due.monthGrid(root.year, root.month, new Date())
    readonly property var quick: [
        { text: root.t("Today", "Hari ini"), words: "hari ini" },
        { text: root.t("Tomorrow", "Besok"), words: "besok" },
        { text: root.t("+1 week", "+1 minggu"), words: "minggu depan" }
    ]

    function t(en, id) {
        return root.lang === "en" ? en : id;
    }
    function show(y, m) {
        const d = new Date(y, m, 1);
        root.year = d.getFullYear();
        root.month = d.getMonth();
    }
    // The month of the date in the text, else this one.
    function reset() {
        const iso = root.sel?.iso;
        if (iso)
            root.show(+iso.slice(0, 4), +iso.slice(5, 7) - 1);
        else
            root.show(new Date().getFullYear(), new Date().getMonth());
        typed.text = root.value;
    }
    Component.onCompleted: reset()
    onVisibleChanged: if (visible)
        reset()
    // A click elsewhere changed the text: the line follows, and the month
    // goes to the day picked.
    onValueChanged: {
        if (!typed.activeFocus)
            typed.text = root.value;
        const iso = root.sel?.iso;
        if (iso && (+iso.slice(0, 4) !== root.year || +iso.slice(5, 7) - 1 !== root.month))
            root.show(+iso.slice(0, 4), +iso.slice(5, 7) - 1);
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => root.show(root.year, root.month + (event.angleDelta.y > 0 ? -1 : 1))
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        // ‹ November 2026 ›            Hari ini · Besok · +1 minggu
        RowLayout {
            Layout.fillWidth: true
            spacing: 2
            PickerButton {
                label: "‹"
                implicitWidth: implicitHeight
                onClicked: root.show(root.year, root.month - 1)
            }
            Text {
                Layout.minimumWidth: 0
                Layout.preferredWidth: implicitWidth
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                elide: Text.ElideRight
                text: Due.monthTitle(root.year, root.month, root.lang)
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: root.fontSize
                font.weight: Font.DemiBold
            }
            PickerButton {
                label: "›"
                implicitWidth: implicitHeight
                onClicked: root.show(root.year, root.month + 1)
            }
            Item {
                Layout.fillWidth: true
            }
            Repeater {
                model: root.quick
                PickerButton {
                    required property var modelData
                    label: modelData.text
                    active: root.sel?.iso === Due.picked(modelData.words, new Date())?.iso
                    onClicked: root.chosen(Due.withDay(root.value, Due.picked(modelData.words, new Date()).iso, new Date()), true)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            // Seven columns, seven rows (heads and six weeks), the cells as
            // big as the room allows.
            Item {
                id: area
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 7 * 15
                readonly property real cellW: width / 7
                readonly property real headH: Math.min(16, height / 8)
                readonly property real cellH: Math.min((height - headH) / 6, cellW * 0.75)
                readonly property real gap: cellH > 26 ? 3 : 1

                Grid {
                    columns: 7
                    Repeater {
                        model: Due.weekHeads(root.lang)
                        Text {
                            required property string modelData
                            width: area.cellW
                            height: area.headH
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData
                            color: root.subColor
                            font.family: root.fontFamily
                            font.pixelSize: Math.max(9, root.fontSize - 3)
                        }
                    }
                    Repeater {
                        model: root.cells
                        Item {
                            id: cell
                            required property var modelData
                            readonly property bool chosen: modelData.iso === root.sel?.iso
                            readonly property bool marked: root.marks.includes(modelData.iso)
                            width: area.cellW
                            height: area.cellH
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: area.gap
                                radius: Math.min(8, height / 3)
                                color: cell.chosen ? root.accentColor : cellMouse.containsMouse ? root.hoverColor : cell.modelData.inMonth && !cell.modelData.past ? root.tileColor : "transparent"
                                border.width: cell.modelData.today && !cell.chosen ? 1.5 : 0
                                border.color: root.accentColor
                            }
                            Text {
                                anchors.centerIn: parent
                                text: cell.modelData.day
                                opacity: cell.chosen ? 1 : cell.modelData.past ? 0.35 : cell.modelData.inMonth ? 1 : 0.45
                                color: cell.chosen ? root.accentTextColor : cell.modelData.today ? root.accentColor : root.textColor
                                font.family: root.fontFamily
                                font.pixelSize: Math.max(9, Math.min(root.fontSize, area.cellH * 0.55))
                                font.weight: cell.chosen || cell.modelData.today ? Font.DemiBold : Font.Normal
                                font.features: ({ tnum: 1 })
                            }
                            // A task is due that day already.
                            Rectangle {
                                visible: cell.marked
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.rightMargin: area.gap + 3
                                anchors.topMargin: area.gap + 3
                                width: 5
                                height: 5
                                radius: 2.5
                                color: cell.chosen ? root.accentTextColor : root.accentColor
                            }
                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                // Past days stay clickable: a late task is still a task.
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.chosen(Due.withDay(root.value, cell.modelData.iso, new Date()), true)
                            }
                        }
                    }
                }
            }

            // Times, top to bottom; a time without a day is today's.
            Flickable {
                Layout.fillHeight: true
                Layout.preferredWidth: times.implicitWidth
                contentHeight: times.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: times
                    spacing: 3
                    Text {
                        text: root.t("TIME", "JAM")
                        color: root.subColor
                        font.family: root.fontFamily
                        font.pixelSize: Math.max(9, root.fontSize - 3)
                    }
                    Repeater {
                        model: ["", "07.00", "12.00", "15.00", "23.59"]
                        PickerButton {
                            required property string modelData
                            width: Math.max(implicitWidth, 52)
                            label: modelData === "" ? root.t("None", "Tanpa") : root.lang === "en" ? modelData.replace(".", ":") : modelData
                            active: root.sel !== null && (root.sel?.time ?? "") === modelData
                            onClicked: root.chosen(Due.withTime(root.value, modelData, new Date()), false)
                        }
                    }
                }
            }
        }

        // Or typed: "jum 14.00", said back as the date it will be.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(24, typed.implicitHeight + 8)
            radius: height / 2
            color: root.tileColor
            border.width: 1
            border.color: typed.activeFocus ? root.accentColor : Qt.alpha(root.subColor, 0.3)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 4
                spacing: 6
                TextInput {
                    id: typed
                    Layout.fillWidth: true
                    clip: true
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 1
                    selectByMouse: true
                    onTextEdited: root.chosen(text, false)
                    onAccepted: if (Due.parseDue(text, new Date()))
                        root.chosen(text, true)
                    Text {
                        visible: !typed.text
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        elide: Text.ElideRight
                        text: root.t("or type: fri 14:00, 5/11, +3", "atau ketik: jum 14.00, 5/11, +3")
                        color: root.subColor
                        font: typed.font
                    }
                }
                Text {
                    readonly property string preview: typed.text.trim() === "" ? "" : Due.duePreview(typed.text, new Date(), root.lang)
                    visible: preview !== ""
                    text: preview
                    color: preview.startsWith("→") ? root.accentColor : root.errorColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 2
                }
                PickerButton {
                    visible: root.value.trim() !== ""
                    label: root.t("Clear", "Hapus")
                    onClicked: root.chosen("", false)
                }
            }
        }
    }

    component PickerButton: Rectangle {
        id: btn
        property string label
        property bool active: false
        signal clicked
        implicitWidth: btnText.implicitWidth + 14
        implicitHeight: Math.max(20, btnText.implicitHeight + 4)
        radius: height / 2
        color: active ? root.accentColor : btnMouse.containsMouse ? root.hoverColor : "transparent"
        border.width: active ? 0 : 1
        border.color: Qt.alpha(root.subColor, 0.3)
        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            color: btn.active ? root.accentTextColor : root.textColor
            font.family: root.fontFamily
            font.pixelSize: Math.max(9, root.fontSize - 2)
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
