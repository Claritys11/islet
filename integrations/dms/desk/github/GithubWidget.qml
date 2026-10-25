import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import "common"
import "contrib.mjs" as Contrib

// A year of GitHub contributions, like impasto's GitHub wall: 53 weeks ×
// 7 days in your DMS colours, with total, streak and today. Reads the public
// contribution calendar with curl (no token; contrib.mjs reads it), every
// 30 minutes.
DesktopPluginComponent {
    id: root

    minWidth: 360
    minHeight: 130

    property string user: (pluginData.githubUser ?? "").trim().replace(/^@/, "")

    property var weeks: []
    property int total: 0
    property int streak: 0
    property int today: 0
    property bool available: false
    property string error: ""

    // Cells fill the width: 53 columns with a gap of a quarter cell.
    readonly property real cell: Math.max(4, Math.min(14, (width - 40) / (53 * 1.25)))
    readonly property real gap: root.cell / 4

    function levelColor(level): color {
        if (level === null || level === undefined)
            return "transparent";
        if (level <= 0)
            return Qt.alpha(Theme.onPrimaryContainer, 0.1);
        return Qt.alpha(Theme.primary, [0, 0.35, 0.6, 0.82, 1][Math.min(level, 4)]);
    }

    // DMS fills pluginData a few times while it builds the widget (empty,
    // the name, empty, the name): wait for it to settle, and never let an
    // older run's answer land after a newer request.
    function refresh(): void {
        settle.restart();
    }

    function fetch(): void {
        if (root.user === "") {
            root.error = "Set your GitHub username in this widget's settings";
            return;
        }
        if (query.busy) {
            query.again = true;
            return;
        }
        query.busy = true;
        // Set here, not bound, so it's always the current name.
        query.command = ["curl", "-fsSL", "--max-time", "20", `https://github.com/users/${encodeURIComponent(root.user)}/contributions`];
        query.running = true;
    }

    Timer {
        id: settle
        interval: 300
        onTriggered: root.fetch()
    }

    onUserChanged: refresh()
    Component.onCompleted: refresh()

    Process {
        id: query
        property string page: ""
        property bool again: false
        // Ours, not `running`: that can still read true inside onExited.
        property bool busy: false
        running: false
        stdout: StdioCollector {
            onStreamFinished: query.page = text
        }
        onExited: code => {
            query.busy = false;
            if (query.again) {
                query.again = false;
                query.page = "";
                Qt.callLater(root.fetch);
                return;
            }
            // Keep the last good grid when it doesn't work out.
            if (code !== 0) {
                root.error = code === 22 ? `No GitHub user "${root.user}"` : "GitHub unavailable";
                return;
            }
            const r = Contrib.parseContributions(query.page, root.user);
            query.page = "";
            if (!r.available) {
                root.error = `No public contributions for "${root.user}"`;
                return;
            }
            root.weeks = r.weeks;
            root.total = r.total;
            root.streak = r.streak;
            root.today = r.today;
            root.available = true;
            root.error = "";
        }
    }

    Timer {
        interval: 30 * 60 * 1000
        repeat: true
        running: true
        onTriggered: root.refresh()
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
            spacing: 10

            Row {
                spacing: 10
                Text {
                    id: heading
                    text: "GitHub"
                    color: Theme.onPrimaryContainer
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                }
                Text {
                    anchors.baseline: heading.baseline
                    text: root.available
                        ? `${root.total.toLocaleString(Qt.locale("en_US"), "f", 0)} contributions · ${root.streak} day streak · ${root.today} today`
                        : (root.error || "Loading…")
                    color: Qt.alpha(Theme.onPrimaryContainer, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Row {
                spacing: root.gap
                Repeater {
                    model: root.weeks
                    Column {
                        required property var modelData
                        spacing: root.gap
                        Repeater {
                            model: modelData
                            Rectangle {
                                required property var modelData
                                width: root.cell
                                height: root.cell
                                radius: root.cell * 0.3
                                color: root.levelColor(modelData)
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(`https://github.com/${root.user}`)
        }
    }
}
