import QtQuick

// The end4-pC style card every deskw widget sits in: a rounded Material
// container with an optional title row and a header button. Colours come
// from the widget (DMS Theme), so this file needs nothing from DMS.
Item {
    id: root

    property string title: ""
    property color cardColor: "#004f56"
    property color textColor: "#9df0fb"
    property color accentColor: "#81d3df"
    property real radius: 24
    property real padding: 16
    property string fontFamily: ""
    // A small round button at the right of the title (e.g. "+").
    property string actionIcon: ""
    signal actionClicked()
    // The pointer is on that button. A widget that types after the click
    // asks DMS for keyboard focus already now: DMS only lets the compositor
    // focus a widget that wants it at the moment it's clicked.
    readonly property bool actionHovered: actionArea.containsMouse

    default property alias content: body.data
    readonly property real headerHeight: root.title !== "" ? titleText.implicitHeight + 10 : 0

    // Solid, or end4-style glass: the card colour see-through, a hairline
    // edge, and the desktop behind it blurred (DeskStyle, shared by all).
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: DeskStyle.fill(root.cardColor)
        border.width: DeskStyle.border ? 1 : 0
        border.color: Qt.alpha(root.textColor, 0.18)

        Glass {
            active: DeskStyle.blur
            radius: root.radius
        }
    }

    Text {
        id: titleText

        visible: root.title !== ""
        x: root.padding
        y: root.padding - 2
        width: parent.width - 2 * root.padding - (actionButton.visible ? actionButton.width + 8 : 0)
        text: root.title
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 22
        elide: Text.ElideRight
    }

    Rectangle {
        id: actionButton

        visible: root.actionIcon !== ""
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding - 4
        width: 34
        height: 34
        radius: 12
        color: actionArea.containsMouse ? Qt.lighter(root.accentColor, 1.1) : root.accentColor

        Text {
            anchors.centerIn: parent
            text: root.actionIcon
            color: root.cardColor
            font.pixelSize: 20
            font.bold: true
        }

        MouseArea {
            id: actionArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.actionClicked()
        }
    }

    Item {
        id: body

        x: root.padding
        y: root.padding + root.headerHeight
        width: parent.width - 2 * root.padding
        height: parent.height - 2 * root.padding - root.headerHeight
        clip: true
    }
}
