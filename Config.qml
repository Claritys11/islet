pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Settings live in ~/.config/lyrics-wheel/config.json. They are edited from
// the settings panel (`lyrics-wheel settings`) or by hand — both hot-reload.
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/lyrics-wheel`
    readonly property string path: `${dir}/config.json`
    property alias opts: adapter

    // Single source of truth for default values (also used by "Reset").
    readonly property var defaults: ({
            // Source
            player: "spotify",
            offsetMs: 250,
            lrclibUrl: "https://lrclib.net",
            // Placement
            side: "right",
            screens: "",
            layer: "top",
            clickThrough: true,
            width: 620,
            marginTop: 60,
            marginBottom: 60,
            marginSide: 0,
            // Wheel
            textColor: "#a6a6a6",
            activeColor: "#ffffff",
            fontFamily: "Google Sans Flex",
            fontSize: 30,
            minFontSize: 14,
            spacing: 1.5,
            curve: 1,
            tilt: 6,
            blur: 2,
            fade: 0.25,
            minOpacity: 0.05,
            smoothing: 200,
            inset: 80,
            visibleLines: 6,
            restingWeight: 200,
            activeWeight: 500,
            // Karaoke
            karaoke: "sweep",
            unsungOpacity: 0.45,
            feather: 28,
            glowColor: "#ffffff",
            glow: 0.7,
            // Background vocals "( … )"
            bgVocals: "below",
            bgScale: 0.62,
            bgOpacity: 0.7,
            bgItalic: true,
            // Lyrics visible area: a soft-edged window the wheel shows through
            viewHeight: 1.0,
            viewOffset: 0,
            edgeFade: 80,
            // Notch
            notchEnabled: true,
            notchShape: "island",
            notchStyle: "black",
            notchScreen: "",
            notchMarginTop: 44,
            notchWidth: 600,
            notchHeight: 250,
            notchPillWidth: 300,
            notchIdle: "handle",
            notchPillText: "lyrics",
            notchHoverDelay: 150,
            notchAutoClose: true,
            // Pomodoro
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            longBreakEvery: 4,
            autoStartBreaks: true,
            autoStartFocus: false,
            pomodoroSound: true,
            // Checklist
            checklistSource: "local",
            notionPage: "",
            // Readability & behaviour
            shadow: true,
            backdrop: 0.35,
            showTrackInfo: true,
            hideWhenPaused: false,
            hideWhenNoLyrics: false,
            fadeDuration: 400
        })

    function reset() {
        for (const key in defaults)
            adapter[key] = defaults[key];
    }

    function set(key, value) {
        if (adapter[key] !== value)
            adapter[key] = value;
    }

    // Writing on every slider tick would thrash the disk; batch them.
    Timer {
        id: saveTimer
        interval: 300
        onTriggered: file.writeAdapter()
    }

    Process {
        id: mkdir
        command: ["mkdir", "-p", root.dir]
        onExited: file.writeAdapter()
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: saveTimer.restart()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                mkdir.running = true;
        }

        JsonAdapter {
            id: adapter

            property string player: root.defaults.player
            property int offsetMs: root.defaults.offsetMs
            property string lrclibUrl: root.defaults.lrclibUrl

            property string side: root.defaults.side
            property string screens: root.defaults.screens
            property string layer: root.defaults.layer
            property bool clickThrough: root.defaults.clickThrough
            property int width: root.defaults.width
            property int marginTop: root.defaults.marginTop
            property int marginBottom: root.defaults.marginBottom
            property int marginSide: root.defaults.marginSide

            property string textColor: root.defaults.textColor
            property string activeColor: root.defaults.activeColor
            property string fontFamily: root.defaults.fontFamily
            property real fontSize: root.defaults.fontSize
            property real minFontSize: root.defaults.minFontSize
            property real spacing: root.defaults.spacing
            property real curve: root.defaults.curve
            property real tilt: root.defaults.tilt
            property real blur: root.defaults.blur
            property real fade: root.defaults.fade
            property real minOpacity: root.defaults.minOpacity
            property int smoothing: root.defaults.smoothing
            property int inset: root.defaults.inset
            property int visibleLines: root.defaults.visibleLines
            property int restingWeight: root.defaults.restingWeight
            property int activeWeight: root.defaults.activeWeight

            property string karaoke: root.defaults.karaoke
            property real unsungOpacity: root.defaults.unsungOpacity
            property real feather: root.defaults.feather
            property string glowColor: root.defaults.glowColor
            property real glow: root.defaults.glow

            property string bgVocals: root.defaults.bgVocals
            property real bgScale: root.defaults.bgScale
            property real bgOpacity: root.defaults.bgOpacity
            property bool bgItalic: root.defaults.bgItalic

            property real viewHeight: root.defaults.viewHeight
            property int viewOffset: root.defaults.viewOffset
            property int edgeFade: root.defaults.edgeFade

            property bool notchEnabled: root.defaults.notchEnabled
            property string notchShape: root.defaults.notchShape
            property string notchStyle: root.defaults.notchStyle
            property string notchScreen: root.defaults.notchScreen
            property int notchMarginTop: root.defaults.notchMarginTop
            property int notchWidth: root.defaults.notchWidth
            property int notchHeight: root.defaults.notchHeight
            property int notchPillWidth: root.defaults.notchPillWidth
            property string notchIdle: root.defaults.notchIdle
            property string notchPillText: root.defaults.notchPillText
            property int notchHoverDelay: root.defaults.notchHoverDelay
            property bool notchAutoClose: root.defaults.notchAutoClose

            property real focusMinutes: root.defaults.focusMinutes
            property real shortBreakMinutes: root.defaults.shortBreakMinutes
            property real longBreakMinutes: root.defaults.longBreakMinutes
            property int longBreakEvery: root.defaults.longBreakEvery
            property bool autoStartBreaks: root.defaults.autoStartBreaks
            property bool autoStartFocus: root.defaults.autoStartFocus
            property bool pomodoroSound: root.defaults.pomodoroSound

            property string checklistSource: root.defaults.checklistSource
            property string notionPage: root.defaults.notionPage

            property bool shadow: root.defaults.shadow
            property real backdrop: root.defaults.backdrop
            property bool showTrackInfo: root.defaults.showTrackInfo
            property bool hideWhenPaused: root.defaults.hideWhenPaused
            property bool hideWhenNoLyrics: root.defaults.hideWhenNoLyrics
            property int fadeDuration: root.defaults.fadeDuration
        }
    }
}
