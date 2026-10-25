import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets
import "common"

// Islet's notch inside DMS: Focus, Hari ini, Shelf and Checklist, drawn with
// DMS's own widgets and colours, fed by Islet over its socket (IsletClient).
// The dash tab shows it whole; a big overview card shows it too.
Item {
    id: root

    // Visible: timers run only then.
    property bool live: true
    property int page: 0

    // Islet isn't running: say so instead of empty pages.
    Column {
        anchors.centerIn: parent
        visible: !IsletClient.connected
        spacing: Theme.spacingS
        DIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "power_off"
            size: Theme.iconSizeLarge
            color: Theme.surfaceVariantText
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Islet isn't running"
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
        }
    }

    ColumnLayout {
        anchors.fill: parent
        visible: IsletClient.connected
        spacing: Theme.spacingM

        DTabBar {
            id: tabs
            Layout.fillWidth: true
            currentIndex: root.page
            model: [
                { text: "Focus", icon: "timer" },
                { text: "Hari ini", icon: "today" },
                { text: "Shelf", icon: "inventory_2" },
                { text: "Checklist", icon: "checklist" }
            ]
            onTabClicked: index => root.page = index
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.page

            IsletFocusPage {}
            IsletTodayPage {}
            IsletShelfPage {}
            IsletChecklistPage {}
        }
    }
}
