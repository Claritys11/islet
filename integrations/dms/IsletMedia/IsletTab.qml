import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Modules.DDash

// The "Islet" tab in DMS's dashboard (and in the Island when DMS routes the
// dash there): Islet's notch — Focus, Hari ini, Shelf, Checklist.
DashTabComponent {
    id: root

    implicitHeight: Math.max(DashMetrics.tabMinHeight, 420)

    IsletPanel {
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        live: root.live
    }
}
