import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import Quickshell
import Quickshell.Services.Mpris

// Settings panel. Every change is applied live to the overlay and saved to
// ~/.config/lyrics-wheel/config.json.
FloatingWindow {
    id: win

    title: "Lyrics Wheel — Settings"
    implicitWidth: 500
    implicitHeight: 780
    color: "#16161a"

    readonly property var o: Config.opts

    // Quick looks that change several settings at once.
    readonly property var presets: [
        { name: "Spicy", values: { karaoke: "sweep", glow: 0.7, glowColor: "#ffffff", activeColor: "#ffffff", textColor: "#a6a6a6", unsungOpacity: 0.45, feather: 28, blur: 2 } },
        { name: "Neon", values: { karaoke: "sweep", glow: 1, glowColor: "#ff4fd8", activeColor: "#ffe3fa", textColor: "#9a86a8", unsungOpacity: 0.35, feather: 18, blur: 2.5 } },
        { name: "Cyber", values: { karaoke: "sweep", glow: 1, glowColor: "#3ee6ff", activeColor: "#e0fbff", textColor: "#7d97a3", unsungOpacity: 0.35, feather: 18, blur: 2.5 } },
        { name: "Typewriter", values: { karaoke: "typewriter", glow: 0.6, glowColor: "#ffffff", activeColor: "#ffffff", textColor: "#a6a6a6", unsungOpacity: 0, feather: 0, blur: 2 } },
        { name: "Minimal", values: { karaoke: "none", glow: 0, activeColor: "#ffffff", textColor: "#a6a6a6", blur: 1.5 } }
    ]

    function applyPreset(values) {
        for (const key in values)
            Config.set(key, values[key]);
    }

    // ── Building blocks ───────────────────────────────────────────
    component Heading: Label {
        Layout.fillWidth: true
        Layout.topMargin: 14
        font.pixelSize: 13
        font.weight: Font.DemiBold
        font.letterSpacing: 1
        color: Material.accent
    }

    component Hint: Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: 12
        opacity: 0.6
    }

    component SliderRow: ColumnLayout {
        id: sr
        property string key
        property string label
        property real from: 0
        property real to: 1
        property real stepSize: 0.05
        property int decimals: 2
        property string unit: ""

        Layout.fillWidth: true
        spacing: -6

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: sr.label
                Layout.fillWidth: true
            }
            Label {
                text: Number(win.o[sr.key]).toFixed(sr.decimals) + sr.unit
                opacity: 0.7
                font.family: "monospace"
            }
        }
        Slider {
            Layout.fillWidth: true
            from: sr.from
            to: sr.to
            stepSize: sr.stepSize
            value: win.o[sr.key]
            onMoved: Config.set(sr.key, sr.decimals === 0 ? Math.round(value) : Number(value.toFixed(sr.decimals)))
        }
    }

    component SwitchRow: RowLayout {
        id: sw
        property string key
        property string label
        Layout.fillWidth: true
        Label {
            text: sw.label
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        Switch {
            checked: win.o[sw.key]
            onToggled: Config.set(sw.key, checked)
        }
    }

    component ChoiceRow: RowLayout {
        id: ch
        property string key
        property string label
        property var choices: [] // [{ text, value }]
        Layout.fillWidth: true
        Label {
            text: ch.label
            Layout.fillWidth: true
        }
        ComboBox {
            Layout.preferredWidth: 200
            model: ch.choices
            textRole: "text"
            valueRole: "value"
            currentIndex: ch.choices.findIndex(c => c.value === win.o[ch.key])
            onActivated: Config.set(ch.key, currentValue)
        }
    }

    component TextRow: RowLayout {
        id: tr
        property string key
        property string label
        property string placeholder
        Layout.fillWidth: true
        Label {
            text: tr.label
            Layout.fillWidth: true
        }
        TextField {
            Layout.preferredWidth: 200
            text: win.o[tr.key]
            placeholderText: tr.placeholder
            onEditingFinished: Config.set(tr.key, text.trim())
        }
    }

    component ColorRow: ColumnLayout {
        id: cr
        property string key
        property string label
        property var swatches: ["#ffffff", "#a6a6a6", "#ff4fd8", "#3ee6ff", "#a8ff60", "#ffd166", "#ff6b6b", "#b388ff"]
        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: cr.label
                Layout.fillWidth: true
            }
            Rectangle {
                width: 22
                height: 22
                radius: 11
                color: win.o[cr.key]
                border.color: "#55ffffff"
            }
            TextField {
                id: hex
                Layout.preferredWidth: 110
                text: win.o[cr.key]
                font.family: "monospace"
                validator: RegularExpressionValidator {
                    regularExpression: /#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?/
                }
                onEditingFinished: Config.set(cr.key, text.toLowerCase())
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: cr.swatches
                Rectangle {
                    required property string modelData
                    width: 24
                    height: 24
                    radius: 12
                    color: modelData
                    border.width: win.o[cr.key] === modelData ? 2 : 1
                    border.color: win.o[cr.key] === modelData ? Material.accent : "#33ffffff"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.set(cr.key, parent.modelData)
                    }
                }
            }
        }
    }

    component Page: ScrollView {
        id: page
        default property alias content: col.data
        contentWidth: availableWidth
        ColumnLayout {
            id: col
            width: page.availableWidth - 32
            x: 16
            spacing: 8
        }
    }

    // ── Layout ────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Attached Material properties don't cross the window boundary, so
        // the theme is set on the root item and inherited from here.
        Material.theme: Material.Dark
        Material.accent: "#a8c7fa"
        Material.background: "#16161a"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 16
            spacing: 2
            Label {
                text: "Lyrics Wheel"
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
            Label {
                text: LyricsService.title !== "" ? `♪  ${LyricsService.title} — ${LyricsService.artist}` : "Nothing playing"
                opacity: 0.6
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        TabBar {
            id: tabs
            Layout.fillWidth: true
            Repeater {
                model: ["Karaoke", "Look", "Placement", "Lyrics"]
                TabButton {
                    required property string modelData
                    text: modelData
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            Page {
                Heading {
                    text: "PRESETS"
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: win.presets
                        Button {
                            required property var modelData
                            text: modelData.name
                            flat: false
                            onClicked: win.applyPreset(modelData.values)
                        }
                    }
                }

                Heading {
                    text: "FILL EFFECT"
                }
                ChoiceRow {
                    key: "karaoke"
                    label: "Style"
                    choices: [
                        { text: "Sweep (Spicy Lyrics)", value: "sweep" },
                        { text: "Typewriter", value: "typewriter" },
                        { text: "Off", value: "none" }
                    ]
                }
                SliderRow {
                    key: "unsungOpacity"
                    label: "Unsung text opacity"
                }
                SliderRow {
                    key: "feather"
                    label: "Sweep edge softness"
                    to: 80
                    stepSize: 1
                    decimals: 0
                    unit: " px"
                }

                Heading {
                    text: "GLOW / NEON"
                }
                SliderRow {
                    key: "glow"
                    label: "Glow strength"
                }
                ColorRow {
                    key: "glowColor"
                    label: "Glow colour"
                }

                Heading {
                    text: "BACKGROUND VOCALS  ( … )"
                }
                Hint {
                    text: "Parts of a line inside parentheses are usually a second voice. Show them smaller, under the main line — like Spicy Lyrics."
                }
                ChoiceRow {
                    key: "bgVocals"
                    label: "Display"
                    choices: [
                        { text: "Smaller, below", value: "below" },
                        { text: "Same as lyrics", value: "same" },
                        { text: "Hidden", value: "hidden" }
                    ]
                }
                SliderRow {
                    key: "bgScale"
                    label: "Size"
                    from: 0.3
                    to: 1
                    unit: "×"
                }
                SliderRow {
                    key: "bgOpacity"
                    label: "Opacity"
                }
                SwitchRow {
                    key: "bgItalic"
                    label: "Italic"
                }
            }

            Page {
                Heading {
                    text: "COLOURS"
                }
                ColorRow {
                    key: "activeColor"
                    label: "Active line"
                }
                ColorRow {
                    key: "textColor"
                    label: "Other lines"
                }

                Heading {
                    text: "FONT"
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "Family"
                        Layout.fillWidth: true
                    }
                    ComboBox {
                        Layout.preferredWidth: 240
                        editable: true
                        model: Qt.fontFamilies()
                        currentIndex: Qt.fontFamilies().indexOf(win.o.fontFamily)
                        onActivated: Config.set("fontFamily", currentText)
                        onAccepted: Config.set("fontFamily", editText)
                    }
                }
                SliderRow {
                    key: "fontSize"
                    label: "Size"
                    from: 14
                    to: 72
                    stepSize: 1
                    decimals: 0
                    unit: " px"
                }
                SliderRow {
                    key: "minFontSize"
                    label: "Shrink long lines down to"
                    from: 8
                    to: 40
                    stepSize: 1
                    decimals: 0
                    unit: " px"
                }
                SliderRow {
                    key: "restingWeight"
                    label: "Weight — other lines"
                    from: 100
                    to: 900
                    stepSize: 100
                    decimals: 0
                }
                SliderRow {
                    key: "activeWeight"
                    label: "Weight — active line"
                    from: 100
                    to: 900
                    stepSize: 100
                    decimals: 0
                }

                Heading {
                    text: "WHEEL"
                }
                SliderRow {
                    key: "spacing"
                    label: "Line spacing"
                    from: 1
                    to: 3
                    unit: "×"
                }
                SliderRow {
                    key: "curve"
                    label: "Curve"
                    to: 2
                }
                SliderRow {
                    key: "tilt"
                    label: "Tilt"
                    to: 20
                    stepSize: 0.5
                    decimals: 1
                    unit: "°"
                }
                SliderRow {
                    key: "blur"
                    label: "Blur per line"
                    to: 8
                    stepSize: 0.1
                    decimals: 1
                    unit: " px"
                }
                SliderRow {
                    key: "fade"
                    label: "Fade per line"
                }
                SliderRow {
                    key: "visibleLines"
                    label: "Visible lines around active"
                    from: 1
                    to: 12
                    stepSize: 1
                    decimals: 0
                }
                SliderRow {
                    key: "smoothing"
                    label: "Scroll smoothing"
                    from: 30
                    to: 800
                    stepSize: 10
                    decimals: 0
                    unit: " ms"
                }

                Heading {
                    text: "READABILITY"
                }
                SwitchRow {
                    key: "shadow"
                    label: "Text shadow"
                }
                SliderRow {
                    key: "backdrop"
                    label: "Backdrop darkness"
                }
                SwitchRow {
                    key: "showTrackInfo"
                    label: "Show song title & artist"
                }
            }

            Page {
                Heading {
                    text: "POSITION"
                }
                ChoiceRow {
                    key: "side"
                    label: "Screen edge"
                    choices: [
                        { text: "Right", value: "right" },
                        { text: "Left", value: "left" }
                    ]
                }
                ChoiceRow {
                    key: "layer"
                    label: "Layer"
                    choices: [
                        { text: "Above windows", value: "top" },
                        { text: "Above everything", value: "overlay" },
                        { text: "Behind windows", value: "bottom" }
                    ]
                }
                TextRow {
                    key: "screens"
                    label: "Monitors"
                    placeholder: "all  (e.g. HDMI-A-1,DP-1)"
                }
                Hint {
                    text: "Monitors on this machine: " + Quickshell.screens.map(s => s.name).join(", ")
                }
                SliderRow {
                    key: "width"
                    label: "Panel width"
                    from: 250
                    to: 1400
                    stepSize: 10
                    decimals: 0
                    unit: " px"
                }
                SliderRow {
                    key: "inset"
                    label: "Distance from edge"
                    to: 400
                    stepSize: 2
                    decimals: 0
                    unit: " px"
                }
                SliderRow {
                    key: "marginTop"
                    label: "Top margin"
                    to: 500
                    stepSize: 5
                    decimals: 0
                    unit: " px"
                }
                SliderRow {
                    key: "marginBottom"
                    label: "Bottom margin"
                    to: 500
                    stepSize: 5
                    decimals: 0
                    unit: " px"
                }
                SliderRow {
                    key: "marginSide"
                    label: "Side margin"
                    to: 300
                    stepSize: 2
                    decimals: 0
                    unit: " px"
                }

                Heading {
                    text: "BEHAVIOUR"
                }
                SwitchRow {
                    key: "clickThrough"
                    label: "Click-through (off = click a line to seek)"
                }
                SwitchRow {
                    key: "hideWhenPaused"
                    label: "Hide when paused"
                }
                SwitchRow {
                    key: "hideWhenNoLyrics"
                    label: "Hide when no lyrics are found"
                }
            }

            Page {
                Heading {
                    text: "SOURCE"
                }
                TextRow {
                    key: "player"
                    label: "Player"
                    placeholder: "any player"
                }
                Hint {
                    text: "Players now: " + (Mpris.players.values.map(p => p.identity).join(", ") || "none")
                }
                SliderRow {
                    key: "offsetMs"
                    label: "Timing offset (+ = earlier)"
                    from: -2000
                    to: 2000
                    stepSize: 50
                    decimals: 0
                    unit: " ms"
                }
                TextRow {
                    key: "lrclibUrl"
                    label: "LRCLIB server"
                }
                Button {
                    text: "Re-fetch lyrics for this song"
                    onClicked: LyricsService.refetch()
                }
                Hint {
                    text: `Status: ${LyricsService.status}${LyricsService.status === "ready" ? (LyricsService.synced ? " · synced" : " · unsynced") + ` · ${LyricsService.lines.length} lines` : ""}`
                }
                Hint {
                    text: "Missing or wrong lyrics? Anyone can add them at lrclib.net — the whole community benefits."
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            Button {
                text: "Reset all"
                flat: true
                onClicked: Config.reset()
            }
            Button {
                text: "Open config file"
                flat: true
                onClicked: Quickshell.execDetached(["xdg-open", Config.path])
            }
            Item {
                Layout.fillWidth: true
            }
            Button {
                text: "Done"
                highlighted: true
                onClicked: win.visible = false
            }
        }
    }
}
