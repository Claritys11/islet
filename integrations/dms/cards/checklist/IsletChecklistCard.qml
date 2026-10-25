import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash
import "common"

// Islet's Checklist as a card on DMS's overview (and in its Island): one of
// the notch's tabs on its own, fewer details when the card is small.
DashCardComponent {
    id: root

    clipContent: true
    pad: Theme.spacingM

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS
            DIcon {
                name: "checklist"
                size: Theme.iconSize
                color: root.accentColor
            }
            StyledText {
                Layout.fillWidth: true
                text: IsletClient.connected ? "Checklist" : "Checklist · Islet isn't running"
                color: root.contentColor
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }
        IsletChecklistPage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: IsletClient.connected
            compact: root.height < DashMetrics.gridRowUnit * 3
        }
    }
}
