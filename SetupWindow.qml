import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import Quickshell
import Quickshell.Io

// First-run guide: a few plain questions that set Islet up. Every answer
// applies right away; everything can be changed later in Settings.
// Opens by itself once, and with `islet setup`.
FloatingWindow {
    id: win

    title: "Islet Setup"
    implicitWidth: 640
    implicitHeight: 560
    // A fixed size makes tiling compositors like niri float it as a dialog.
    minimumSize: Qt.size(640, 560)
    maximumSize: Qt.size(640, 560)
    color: "#121316"

    signal openSettings

    readonly property var o: Config.opts
    readonly property color card: "#1b1c20"
    readonly property color text: "#e4e4e8"
    readonly property color subtext: "#9a9ca5"
    readonly property color accent: Theme.primary
    readonly property string font: "Google Sans Flex"
    readonly property string cli: Qt.resolvedUrl("bin/islet").toString().replace(/^file:\/\//, "")

    property int step: 0
    readonly property int steps: 5
    property string music: o.player.toLowerCase().includes("spotify") ? "spotify" : ""
    property bool hasDms: false
    property bool hasSpicetify: false
    property bool spicyReady: false
    property string running: ""
    property string output: ""

    function finish() {
        Store.db.setupDone = true;
        visible = false;
    }

    // Run an `islet` command (dms, spicetify) and show how it went.
    function run(args, label) {
        running = label;
        output = "";
        task.command = ["sh", cli].concat(args);
        task.running = true;
    }

    Process {
        id: probe
        running: true
        command: ["sh", "-c", 'command -v dms >/dev/null && echo dms; if command -v spicetify >/dev/null; then echo spicetify; grep -q islet-bridge.js "$(spicetify -c)" 2>/dev/null && echo spicy-ready; fi; true']
        stdout: SplitParser {
            onRead: line => {
                if (line === "dms")
                    win.hasDms = true;
                if (line === "spicetify")
                    win.hasSpicetify = true;
                if (line === "spicy-ready")
                    win.spicyReady = true;
            }
        }
    }

    Process {
        id: task
        stdout: SplitParser {
            onRead: line => win.output = line
        }
        stderr: SplitParser {
            onRead: line => win.output = line
        }
        onExited: code => {
            win.output = code === 0 ? `✓ ${win.running} — done` : `Something went wrong: ${win.output}`;
            win.running = "";
        }
    }

    component Choice: Rectangle {
        id: ch
        property string icon
        property string title
        property string hint
        property bool selected: false
        property color iconColor: selected ? win.accent : win.subtext
        signal picked
        Layout.fillWidth: true
        implicitHeight: chRow.implicitHeight + 28
        radius: 16
        color: selected ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.16) : chMouse.containsMouse ? "#24262b" : win.card
        border.color: selected ? win.accent : "transparent"
        border.width: 2
        RowLayout {
            id: chRow
            x: 16
            y: 14
            width: parent.width - 32
            spacing: 14
            Text {
                text: ch.icon
                color: ch.iconColor
                font.family: Theme.iconFont
                font.pixelSize: 28
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    text: ch.title
                    color: win.text
                    font.family: win.font
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Label {
                    visible: ch.hint !== ""
                    Layout.fillWidth: true
                    text: ch.hint
                    color: win.subtext
                    wrapMode: Text.Wrap
                    font.family: win.font
                    font.pixelSize: 12
                }
            }
            Text {
                visible: ch.selected
                text: "check_circle"
                color: win.accent
                font.family: Theme.iconFont
                font.pixelSize: 22
            }
        }
        MouseArea {
            id: chMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ch.picked()
        }
    }

    component Heading: ColumnLayout {
        property string title
        property string hint
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        spacing: 4
        Label {
            text: parent.title
            color: win.text
            font.family: win.font
            font.pixelSize: 24
            font.weight: Font.Bold
        }
        Label {
            visible: parent.hint !== ""
            Layout.fillWidth: true
            text: parent.hint
            color: win.subtext
            wrapMode: Text.Wrap
            font.family: win.font
            font.pixelSize: 13
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 16
        // (Attached Material properties don't cross the window boundary.)
        Material.theme: Material.Dark
        Material.accent: win.accent
        Material.background: win.card

        // Progress dots
        Row {
            spacing: 6
            Repeater {
                model: win.steps
                Rectangle {
                    required property int index
                    width: index === win.step ? 22 : 8
                    height: 8
                    radius: 4
                    color: index <= win.step ? win.accent : "#2c2e34"
                    Behavior on width {
                        NumberAnimation {
                            duration: 200
                        }
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: win.step

            // 1 — Music
            ColumnLayout {
                spacing: 10
                Heading {
                    title: "Hi! Where do you play music?"
                    hint: "Islet shows synced lyrics for whatever is playing. This just decides which player wins when several play at once."
                }
                Choice {
                    icon: "graphic_eq"
                    title: "Spotify"
                    selected: win.music === "spotify"
                    onPicked: {
                        win.music = "spotify";
                        Config.set("player", "spotify", "Preferred player: Spotify");
                    }
                }
                Choice {
                    icon: "smart_display"
                    title: "YouTube Music or YouTube, in my browser"
                    hint: "Nothing else to do: just play it, Islet follows the browser."
                    selected: win.music === "browser"
                    onPicked: {
                        win.music = "browser";
                        Config.set("player", "", "Preferred player: any");
                    }
                }
                Choice {
                    icon: "queue_music"
                    title: "A bit of everything"
                    hint: "Spotify, browsers, mpv, VLC… Islet follows whichever is playing."
                    selected: win.music === "any"
                    onPicked: {
                        win.music = "any";
                        Config.set("player", "", "Preferred player: any");
                    }
                }
                // Spotify + Spicetify: offer Spicy Lyrics' exact timing.
                Rectangle {
                    visible: win.music === "spotify" && win.hasSpicetify
                    Layout.fillWidth: true
                    implicitHeight: spicyCol.implicitHeight + 24
                    radius: 16
                    color: win.card
                    ColumnLayout {
                        id: spicyCol
                        x: 16
                        y: 12
                        width: parent.width - 32
                        spacing: 6
                        Label {
                            Layout.fillWidth: true
                            text: "🌶️ Use Spicy Lyrics in Spotify? Islet can show its syllable-exact lyrics and timing."
                            color: win.text
                            wrapMode: Text.Wrap
                            font.family: win.font
                            font.pixelSize: 13
                        }
                        RowLayout {
                            Button {
                                text: win.spicyReady ? "✓ Already set up" : win.running === "Spicy Lyrics" ? "Setting up…" : "Set it up (restarts Spotify)"
                                enabled: win.running === "" && !win.spicyReady
                                onClicked: win.run(["spicetify"], "Spicy Lyrics")
                            }
                            Label {
                                Layout.fillWidth: true
                                text: win.output
                                color: win.subtext
                                elide: Text.ElideRight
                                font.family: win.font
                                font.pixelSize: 12
                            }
                        }
                    }
                }
                Item {
                    Layout.fillHeight: true
                }
            }

            // 2 — Notch
            ColumnLayout {
                spacing: 10
                Heading {
                    title: "Where should Islet live?"
                    hint: "Islet's notch shows the song, the lyric being sung, your focus timer, tasks and a file shelf."
                }
                Choice {
                    visible: win.hasDms
                    icon: "toolbar"
                    title: "In my DankMaterialShell bar"
                    hint: "Replaces DMS's media widget. Click it to drop Islet down right under it."
                    selected: win.o.notchEnabled && win.o.notchMode === "bar"
                    onPicked: {
                        Config.set("notchEnabled", true, "Notch on");
                        win.run(["dms"], "DMS bar widget");
                    }
                }
                Choice {
                    icon: "page_header"
                    title: "A floating island at the top"
                    hint: "Like the iPhone's Dynamic Island. Hover to peek, click to open."
                    selected: win.o.notchEnabled && win.o.notchMode !== "bar"
                    onPicked: {
                        Config.set("notchEnabled", true, "Notch on");
                        Config.set("notchMode", "island", "Notch: floating island");
                    }
                }
                Choice {
                    icon: "block"
                    title: "No notch, thanks"
                    selected: !win.o.notchEnabled
                    onPicked: Config.set("notchEnabled", false, "Notch off")
                }
                Label {
                    visible: win.output !== "" && win.step === 1
                    Layout.fillWidth: true
                    text: win.output
                    color: win.subtext
                    wrapMode: Text.Wrap
                    font.family: win.font
                    font.pixelSize: 12
                }
                Item {
                    Layout.fillHeight: true
                }
            }

            // 3 — Lyrics on the screen
            ColumnLayout {
                spacing: 10
                Heading {
                    title: "Lyrics on the side of the screen?"
                    hint: "Big glowing karaoke lyrics on every workspace. They're in the notch either way."
                }
                Choice {
                    icon: "align_horizontal_right"
                    title: "Yes, on the right"
                    selected: win.o.lyricsEnabled && win.o.side === "right"
                    onPicked: {
                        Config.set("lyricsEnabled", true, "Lyrics overlay on");
                        Config.set("side", "right", "Lyrics: right side");
                    }
                }
                Choice {
                    icon: "align_horizontal_left"
                    title: "Yes, on the left"
                    selected: win.o.lyricsEnabled && win.o.side === "left"
                    onPicked: {
                        Config.set("lyricsEnabled", true, "Lyrics overlay on");
                        Config.set("side", "left", "Lyrics: left side");
                    }
                }
                Choice {
                    icon: "visibility_off"
                    title: "No, only in the notch"
                    selected: !win.o.lyricsEnabled
                    onPicked: Config.set("lyricsEnabled", false, "Lyrics overlay off")
                }
                Item {
                    Layout.fillHeight: true
                }
            }

            // 4 — Look
            ColumnLayout {
                spacing: 10
                Heading {
                    title: "Pick a look"
                    hint: "Sample lyrics are on screen so you can see each one. Colours, glow and fonts can be tuned later."
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 10
                    Repeater {
                        model: Config.presets
                        Choice {
                            required property var modelData
                            icon: "palette"
                            iconColor: modelData.color
                            title: modelData.name
                            selected: Object.keys(modelData.values).every(k => win.o[k] === modelData.values[k])
                            onPicked: Config.applyPreset(modelData)
                        }
                    }
                }
                Item {
                    Layout.fillHeight: true
                }
            }

            // 5 — Done
            ColumnLayout {
                spacing: 12
                Heading {
                    title: "You're all set 🎉"
                    hint: "A few things worth knowing:"
                }
                Repeater {
                    model: [
                        { icon: "touch_app", text: "Click the notch (or the Islet pill in your bar) for music, focus timer, tasks and the shelf." },
                        { icon: "search", text: "Want to change something? Open Settings and type what you're after, like “youtube” or “too fast”." },
                        { icon: "keyboard", text: "Bind keys to 'islet notch', 'islet toggle' or 'islet settings' — the README has examples for niri and Hyprland." },
                        { icon: "update", text: "Islet tells you when there's an update; one click installs it." },
                        { icon: "event_note", text: "School timetable and tasks in Notion? Settings → Calendar & Notion shows today's lessons and deadlines in the notch and syncs them with Google Calendar. No databases yet? 'Make Islet's databases' there builds them for you." },
                        { icon: "widgets", text: "Settings → DankMaterialShell puts lyrics, to-dos, notes, a timer, a calendar and a clock on your desktop.", dms: true }
                    ].filter(t => !t.dms || win.hasDms)
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 14
                        Text {
                            text: modelData.icon
                            color: win.accent
                            font.family: Theme.iconFont
                            font.pixelSize: 24
                        }
                        Label {
                            Layout.fillWidth: true
                            text: modelData.text
                            color: win.text
                            wrapMode: Text.Wrap
                            font.family: win.font
                            font.pixelSize: 14
                        }
                    }
                }
                Item {
                    Layout.fillHeight: true
                }
            }
        }

        // Navigation
        RowLayout {
            Layout.fillWidth: true
            Button {
                text: win.step === 0 ? "Skip" : "Back"
                flat: true
                onClicked: win.step === 0 ? win.finish() : win.step--
            }
            Item {
                Layout.fillWidth: true
            }
            Button {
                visible: win.step === win.steps - 1
                text: "Open Settings"
                flat: true
                onClicked: {
                    win.finish();
                    win.openSettings();
                }
            }
            Button {
                text: win.step === win.steps - 1 ? "Done" : "Next"
                highlighted: true
                onClicked: win.step === win.steps - 1 ? win.finish() : win.step++
            }
        }
    }

    // Sample lyrics on screen while picking a look.
    Binding {
        target: LyricsService
        property: "demo"
        value: true
        when: win.visible && win.step === 3 && win.o.lyricsEnabled
        restoreMode: Binding.RestoreValue
    }
}
