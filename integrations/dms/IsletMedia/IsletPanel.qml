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

    readonly property var pageNames: ["focus", "today", "shelf", "checklist"]
    function takePage() {
        const i = pageNames.indexOf(IsletClient.panelPage);
        if (i >= 0)
            root.page = i;
        IsletClient.panelPage = "";
    }
    Component.onCompleted: takePage()
    Connections {
        target: IsletClient
        function onPanelPageChanged() {
            if (IsletClient.panelPage !== "")
                root.takePage();
        }
    }

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
            text: IsletClient.t("Islet isn't running", "Islet tidak berjalan")
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
                { text: IsletClient.t("Focus", "Fokus"), icon: "timer" },
                { text: IsletClient.t("Today", "Hari ini"), icon: "today" },
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
            // The panel takes the drops, on whichever page it's showing.
            IsletShelfPage {
                acceptDrops: false
            }
            IsletChecklistPage {}
        }
    }

    // Files dragged over any of it: to the Shelf, where they land.
    DropArea {
        id: panelDrop
        anchors.fill: parent
        enabled: IsletClient.connected
        onEntered: drag => {
            if (!drag.hasUrls)
                return;
            drag.accept(Qt.CopyAction);
            root.page = root.pageNames.indexOf("shelf");
        }
        onDropped: drop => {
            if (!drop.hasUrls)
                return;
            IsletClient.send({ cmd: "shelf-add", urls: drop.urls.map(u => u.toString()) });
            drop.accept(Qt.CopyAction);
        }
    }
    Rectangle {
        visible: panelDrop.containsDrag
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Qt.alpha(Theme.primary, 0.08)
        border.color: Theme.primary
        border.width: 2
    }
}
