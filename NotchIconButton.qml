import QtQuick

// Round icon button using Material Symbols ligatures ("play_arrow", "pause", …).
Rectangle {
    id: root

    property string icon
    property real size: 34
    property real iconSize: size * 0.58
    property bool filled: false
    property bool highlighted: false
    property color tint: highlighted ? Theme.onPrimary : Theme.text
    readonly property alias containsMouse: mouse.containsMouse
    signal clicked

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: highlighted ? Theme.primary : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
    opacity: enabled ? 1 : 0.35
    scale: mouse.pressed ? 0.9 : 1

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 90
        }
    }

    Text {
        anchors.centerIn: parent
        text: root.icon
        color: root.tint
        font.family: Theme.iconFont
        font.pixelSize: root.iconSize
        // Variable fonts only switch instance reliably when every axis is set.
        font.hintingPreference: Font.PreferNoHinting
        font.variableAxes: ({
                FILL: root.filled ? 1 : 0,
                GRAD: 0,
                opsz: 24,
                wght: root.filled ? 500 : 400
            })
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
