import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import "common"

// end4-pC's cookie clock: a wavy cookie, round hour marks, two rounded
// hands, the date in a badge. Colours from DMS Theme.
DesktopPluginComponent {
    id: root

    minWidth: 160
    minHeight: 160

    property bool showSeconds: pluginData.showSeconds ?? false
    property bool showDate: pluginData.showDate ?? true
    property real sides: pluginData.sides ?? 9

    readonly property real size: Math.min(width, height)

    SystemClock {
        id: clock
        precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    readonly property real hours: clock.hours % 12 + clock.minutes / 60
    readonly property real minutes: clock.minutes + (root.showSeconds ? clock.seconds / 60 : 0)

    Item {
        width: root.size
        height: root.size
        anchors.centerIn: parent

        CookieShape {
            anchors.fill: parent
            implicitSize: root.size
            sides: root.sides
            color: DeskStyle.fill(Theme.primaryContainer)
        }

        // Glass: blur a circle just inside the cookie's waves.
        Item {
            width: root.size * 0.9
            height: width
            anchors.centerIn: parent
            Glass {
                active: DeskStyle.blur
                radius: width / 2
            }
        }

        // Twelve round marks, the quarter ones bigger.
        Repeater {
            model: 12
            Rectangle {
                required property int index
                readonly property bool quarter: index % 3 === 0
                readonly property real r: root.size * 0.36
                width: quarter ? root.size * 0.05 : root.size * 0.028
                height: width
                radius: width / 2
                color: Qt.alpha(Theme.onPrimaryContainer, quarter ? 0.9 : 0.5)
                x: root.size / 2 + Math.sin(index * Math.PI / 6) * r - width / 2
                y: root.size / 2 - Math.cos(index * Math.PI / 6) * r - height / 2
            }
        }

        // Date badge, end4-style, on the right.
        Rectangle {
            visible: root.showDate
            width: root.size * 0.2
            height: root.size * 0.14
            radius: height / 2
            color: Theme.primary
            x: root.size * 0.62
            y: root.size / 2 - height / 2
            Text {
                anchors.centerIn: parent
                text: Qt.formatDate(clock.date, "d")
                color: Theme.onPrimary
                font.family: Theme.fontFamily
                font.pixelSize: root.size * 0.075
                font.bold: true
            }
        }

        // Hand: a rounded bar rotating about the centre.
        component Hand: Rectangle {
            property real angle: 0
            property real length: 0.3
            width: root.size * 0.06
            height: root.size * length
            radius: width / 2
            x: root.size / 2 - width / 2
            y: root.size / 2 - height + width / 2
            transformOrigin: Item.Bottom
            rotation: angle
            antialiasing: true
            Behavior on rotation {
                RotationAnimation { duration: 400; direction: RotationAnimation.Shortest; easing.type: Easing.OutCubic }
            }
        }

        Hand {
            angle: root.hours * 30
            length: 0.24
            width: root.size * 0.075
            color: Theme.primary
        }
        Hand {
            angle: root.minutes * 6
            length: 0.34
            color: Theme.onPrimaryContainer
        }
        Hand {
            visible: root.showSeconds
            angle: clock.seconds * 6
            length: 0.38
            width: root.size * 0.018
            color: Theme.error
        }

        Rectangle {
            width: root.size * 0.07
            height: width
            radius: width / 2
            anchors.centerIn: parent
            color: Theme.primary
        }
    }
}
