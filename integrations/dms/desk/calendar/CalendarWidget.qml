import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import "common"
import "common/rich.mjs" as Rich

// end4-pC's month calendar, plus the events of Dux Calendar (through
// islet's "calendar-month" request): a dot on days with events and the
// list for the selected day.
DesktopPluginComponent {
    id: root

    minWidth: 260
    minHeight: 240

    property int weekStart: (pluginData.weekStart ?? "monday") === "sunday" ? 0 : 1

    property date today: new Date()
    property int year: today.getFullYear()
    property int month: today.getMonth()
    property int selected: today.getDate()
    property var monthData: ({ days: {}, byDay: {} })
    property string error: ""

    readonly property var cells: Rich.monthGrid(root.year, root.month, root.weekStart)
    readonly property bool isThisMonth: root.year === root.today.getFullYear() && root.month === root.today.getMonth()
    readonly property var dayEvents: root.monthData.byDay?.[root.selected] ?? []
    readonly property var names: root.weekStart === 1 ? ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"] : ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    function load(): void {
        if (!IsletClient.connected) {
            root.error = "islet isn't running";
            return;
        }
        const y = root.year, m = root.month;
        requester.request("calendar-month", { year: y, month: m }, (ok, data, err) => {
            if (y !== root.year || m !== root.month)
                return;
            if (ok) {
                root.monthData = data;
                root.error = "";
            } else {
                root.error = err;
            }
        });
    }

    function shift(by): void {
        const d = new Date(root.year, root.month + by, 1);
        root.year = d.getFullYear();
        root.month = d.getMonth();
        root.selected = root.isThisMonth ? root.today.getDate() : 1;
        root.monthData = { days: {}, byDay: {} };
        root.load();
    }

    Requester {
        id: requester
    }

    Component.onCompleted: load()

    Connections {
        target: IsletClient
        function onConnectedChanged() {
            if (IsletClient.connected)
                root.load();
        }
    }

    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: true
        onTriggered: {
            root.today = new Date();
            root.load();
        }
    }

    DeskCard {
        anchors.fill: parent
        cardColor: Theme.primaryContainer
        textColor: Theme.onPrimaryContainer
        accentColor: Theme.primary
        radius: Theme.cornerRadius * 1.5
        fontFamily: Theme.fontFamily

        Column {
            anchors.fill: parent
            spacing: 6

            // Month pill with ‹ ›
            Row {
                width: parent.width
                spacing: 6

                Rectangle {
                    height: 30
                    width: monthText.implicitWidth + 24
                    radius: 15
                    color: Theme.primary
                    Text {
                        id: monthText
                        anchors.centerIn: parent
                        text: Qt.formatDate(new Date(root.year, root.month, 1), "MMMM yyyy")
                        color: Theme.onPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                    }
                }
                Item { width: parent.width - monthText.implicitWidth - 24 - 2 * 36 - 18; height: 1 }
                Repeater {
                    model: ["‹", "›"]
                    Rectangle {
                        required property string modelData
                        required property int index
                        width: 30
                        height: 30
                        radius: 15
                        color: navArea.containsMouse ? Qt.alpha(Theme.primary, 0.25) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: Theme.onPrimaryContainer
                            font.pixelSize: 20
                        }
                        MouseArea {
                            id: navArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.shift(index === 0 ? -1 : 1)
                        }
                    }
                }
            }

            Grid {
                id: grid
                columns: 7
                width: parent.width
                readonly property real cell: width / 7

                Repeater {
                    model: root.names
                    Text {
                        required property string modelData
                        width: grid.cell
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Qt.alpha(Theme.onPrimaryContainer, 0.7)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                Repeater {
                    model: root.cells
                    Item {
                        required property var modelData
                        readonly property bool isToday: root.isThisMonth && modelData.inMonth && modelData.day === root.today.getDate()
                        readonly property bool isSelected: modelData.inMonth && modelData.day === root.selected
                        readonly property int count: modelData.inMonth ? (root.monthData.days?.[modelData.day] ?? 0) : 0
                        width: grid.cell
                        height: Math.min(grid.cell, 30)

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) - 2
                            height: width
                            radius: width / 2
                            color: parent.isToday ? Theme.primary : parent.isSelected ? Qt.alpha(Theme.primary, 0.25) : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.day
                            color: parent.isToday ? Theme.onPrimary : Qt.alpha(Theme.onPrimaryContainer, modelData.inMonth ? 1 : 0.35)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: parent.isToday
                        }
                        Rectangle {
                            visible: parent.count > 0
                            width: 4
                            height: 4
                            radius: 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            color: parent.isToday ? Theme.onPrimary : Theme.primary
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.inMonth
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selected = modelData.day
                        }
                    }
                }
            }

            // The selected day's events.
            ListView {
                width: parent.width
                height: Math.max(0, parent.height - y)
                clip: true
                spacing: 4
                model: root.dayEvents
                visible: height > 20

                header: Text {
                    width: parent ? parent.width : 0
                    bottomPadding: 4
                    textFormat: Text.PlainText
                    text: root.error !== "" ? root.error
                        : root.dayEvents.length === 0 ? "No events on " + root.selected
                        : Qt.formatDate(new Date(root.year, root.month, root.selected), "dddd d MMM")
                    color: Qt.alpha(Theme.onPrimaryContainer, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }

                delegate: Row {
                    required property var modelData
                    spacing: 8
                    width: ListView.view.width
                    Rectangle {
                        width: 4
                        height: 28
                        radius: 2
                        color: modelData.color || Theme.primary
                    }
                    Column {
                        width: parent.width - 12
                        Text {
                            width: parent.width
                            text: modelData.title
                            textFormat: Text.PlainText
                            color: Theme.onPrimaryContainer
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: modelData.time + (modelData.calendar ? " · " + modelData.calendar : "")
                            textFormat: Text.PlainText
                            color: Qt.alpha(Theme.onPrimaryContainer, 0.7)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall - 1
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
