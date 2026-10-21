import QtQuick
import QtQuick.Layouts

// Finder inside the notch: a search box, the results, and the keys. Type
// fragments of a name ("isw" → islet-windows); Enter opens, Ctrl+T opens a
// terminal there, Ctrl+E the editor, Alt+Enter the containing folder, Ctrl+C
// copies the path.
Item {
    id: root

    signal closeRequested
    property int current: 0
    // The selection follows the item, not the row: file results arriving
    // after folder results reorder the list.
    property string selectedPath: ""
    readonly property var results: FinderService.results

    // Called when the notch switches to Finder.
    function start(text) {
        input.text = text;
        FinderService.begin(text);
        input.cursorPosition = text.length;
        current = 0;
        selectedPath = "";
        input.forceActiveFocus();
        updatedClock.now = Date.now();
    }

    function act(action) {
        if (results.length > 0)
            FinderService.act(Math.min(current, results.length - 1), action);
    }

    function move(by) {
        if (results.length > 0)
            select((current + by + results.length) % results.length);
    }

    function select(i) {
        current = i;
        selectedPath = results[i]?.path ?? "";
    }

    Connections {
        target: FinderService
        function onResultsChanged() {
            const i = root.results.findIndex(r => r.path === root.selectedPath);
            root.current = Math.max(0, i);
        }
        function onActed(action) {
            if (action !== "copy")
                root.closeRequested();
        }
    }

    // The name with the matched letters lit, as styled text.
    function highlight(name, positions) {
        const lit = new Set(positions);
        const esc = c => c === "<" ? "&lt;" : c === ">" ? "&gt;" : c === "&" ? "&amp;" : c;
        let out = "";
        for (let i = 0; i < name.length; i++)
            out += lit.has(i) ? `<b><font color="${Theme.primary}">${esc(name[i])}</font></b>` : esc(name[i]);
        return out;
    }

    function kindIcon(r) {
        if (r.kind === "cmd")
            return r.icon;
        if (r.kind === "dir")
            return r.project ? "folder_special" : "folder";
        return ShelfService.icon({ name: r.name, dir: false });
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // ── Search box ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 10
            Text {
                text: "search"
                color: Theme.subtext
                font.family: Theme.iconFont
                font.pixelSize: 22
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: 34
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: "Find files and folders — type part of a name"
                    color: Theme.subtext
                    font.family: Theme.font
                    font.pixelSize: 16
                }
                TextInput {
                    id: input
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    selectionColor: Theme.primary
                    selectedTextColor: Theme.onPrimary
                    selectByMouse: true
                    font.family: Theme.font
                    font.pixelSize: 16
                    clip: true
                    onTextChanged: {
                        root.selectedPath = "";
                        FinderService.query = text;
                    }
                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) {
                            root.move(1);
                        } else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) {
                            root.move(-1);
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.act(event.modifiers & Qt.AltModifier ? "reveal" : "open");
                        } else if (ctrl && event.key === Qt.Key_T) {
                            root.act("terminal");
                        } else if (ctrl && event.key === Qt.Key_E) {
                            root.act("editor");
                        } else if (ctrl && event.key === Qt.Key_C && input.selectedText === "") {
                            root.act("copy");
                        } else if (event.key === Qt.Key_Escape) {
                            root.closeRequested();
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        // ── Results ───────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: root.results
                currentIndex: root.current
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 44
                    radius: 12
                    color: index === root.current ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10
                        Text {
                            text: root.kindIcon(row.modelData)
                            color: row.modelData.kind === "dir" || row.modelData.kind === "cmd" ? Theme.primary : Theme.subtext
                            font.family: Theme.iconFont
                            font.pixelSize: 20
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            RowLayout {
                                spacing: 8
                                Text {
                                    Layout.maximumWidth: row.width - 140
                                    text: root.highlight(row.modelData.name, row.modelData.positions)
                                    textFormat: Text.StyledText
                                    color: Theme.text
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                }
                                Rectangle {
                                    visible: row.modelData.project
                                    implicitWidth: tag.implicitWidth + 12
                                    implicitHeight: 17
                                    radius: 8
                                    color: Qt.rgba(1, 1, 1, 0.1)
                                    Text {
                                        id: tag
                                        anchors.centerIn: parent
                                        text: "project"
                                        color: Theme.subtext
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.short
                                color: Theme.subtext
                                elide: Text.ElideMiddle
                                font.family: Theme.font
                                font.pixelSize: 12
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.select(row.index)
                        onClicked: {
                            root.select(row.index);
                            root.act("open");
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.results.length === 0
                horizontalAlignment: Text.AlignHCenter
                text: FinderService.status === "missing-tools" ? "Install fd and fzf to search your files"
                    : FinderService.status === "no-folders" ? "None of the folders in Settings → Finder exist"
                    : FinderService.counts.files === 0 ? "Indexing your files…"
                    : input.text === "" ? "Type part of a name — \"isw\" finds islet-windows"
                    : "No matches"
                color: Theme.subtext
                font.family: Theme.font
                font.pixelSize: 13
            }
        }

        // ── Keys and status ───────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 11

            Repeater {
                model: [["Enter", "Open"], ["Ctrl+T", "Terminal"], ["Ctrl+E", "Editor"], ["Alt+Enter", "Folder"], ["Ctrl+C", "Copy"]]
                Row {
                    required property var modelData
                    spacing: 5
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: keyText.implicitWidth + 10
                        implicitHeight: 18
                        radius: 5
                        color: Qt.rgba(1, 1, 1, 0.1)
                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            text: modelData[0]
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData[1]
                        color: Theme.subtext
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                id: updatedClock
                property real now: Date.now()
                readonly property int mins: Math.max(0, Math.round((now - FinderService.indexedAt) / 60000))
                text: FinderService.message !== "" ? FinderService.message
                    : FinderService.status === "indexing" ? "Indexing…"
                    : FinderService.indexedAt > 0 ? `${Math.round((FinderService.counts.dirs + FinderService.counts.files) / 1000)}k items · ${mins < 1 ? "now" : mins + " min ago"}`
                    : ""
                color: FinderService.message !== "" ? Theme.primary : Theme.subtext
                font.family: Theme.font
                font.pixelSize: 11
            }
        }
    }
}
