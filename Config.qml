pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Settings live in ~/.config/islet/config.json. They are edited from the
// settings panel (`islet settings`) or by hand — both hot-reload.
Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    // ISLET_CONFIG_DIR points Islet at another settings folder (tests, showcase).
    readonly property string dir: Quickshell.env("ISLET_CONFIG_DIR") || `${configHome}/islet`
    // Where settings lived before the project was renamed (not migrated into
    // an ISLET_CONFIG_DIR override).
    readonly property string legacyDir: Quickshell.env("ISLET_CONFIG_DIR") ? "" : `${configHome}/lyrics-wheel`
    readonly property string path: `${dir}/config.json`
    property alias opts: adapter

    // Single source of truth for default values (also used by "Reset").
    readonly property var defaults: ({
            // Modules
            lyricsEnabled: true,
            // Source
            player: "spotify",
            lyricsSource: "auto",
            spicyOffsetMs: 100,
            bridgePort: 47821,
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
            longLines: "wrap",
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
            fillSpeed: 1.0,
            feather: 28,
            glowColor: "#ffffff",
            glow: 0.7,
            // Background vocals "( … )"
            bgVocals: "below",
            bgScale: 0.62,
            bgOpacity: 0.7,
            bgItalic: true,
            bgLinger: 1.5,
            // Lyrics visible area: a soft-edged window the wheel shows through
            viewHeight: 1.0,
            viewOffset: 0,
            edgeFade: 80,
            // Notch
            notchEnabled: true,
            notchMode: "island",
            // Words in the notch, the DMS bar pill and Islet's DMS cards:
            // "en" (English) or "id" (Bahasa Indonesia).
            language: "en",
            barPillWidth: 300,
            barShowVisualizer: true,
            barShowTimer: true,
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
            notchCloseDelay: 1200,
            // Pomodoro
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            longBreakEvery: 4,
            autoStartBreaks: true,
            autoStartFocus: false,
            pomodoroSound: true,
            pauseReminderMinutes: 10,
            breakTips: true,
            // Weather (in the pill when nothing plays)
            weatherEnabled: true,
            weatherCity: "",
            weatherUnit: "c",
            // Visualizer mode: the notch becomes a visualizer while you're away
            vizMode: true,
            vizIdleSeconds: 60,
            // Performance
            maxFps: 60,
            // Updates
            checkUpdates: true,
            // Settings window: sample lyrics when nothing plays
            samplePreview: true,
            // Checklist
            checklistSource: "local",
            notionPage: "",
            // Finder (find files and folders)
            finderRoots: "~",
            finderExclude: "node_modules,venv,.venv,__pycache__,target,build,dist,.cache,.git,vendor,**/pkg/mod",
            finderHidden: false,
            finderFileManager: "",
            finderTerminal: "",
            finderEditor: "",
            finderReindexMinutes: 10,
            // Today (Notion ⇄ Google Calendar)
            todayEnabled: true,
            todaySync: true,
            // Lessons as weekly events in Google too (off: only tasks).
            todaySyncLessons: false,
            todayCalendar: "",
            todayTimetableDb: "",
            todayTasksDb: "",
            todayDailyDb: "",
            // Notion database for the DMS Notes desktop widget ("" = the one titled Notes).
            notesDb: "",
            todayColumns: "",
            todayDays: 7,
            todayMorningOpen: true,
            todayMorningSeconds: 8,
            todayNudges: true,
            todayEventMinutes: 60,
            todaySemesterEnd: "",
            todaySyncMinutes: 5,
            // Readability & behaviour
            shadow: true,
            backdrop: 0.35,
            showTrackInfo: true,
            hideWhenPaused: false,
            hideWhenNoLyrics: false,
            fadeDuration: 400
        })

    // Quick looks for the lyrics that change several settings at once.
    readonly property var presets: [
        { name: "Spicy", color: "#ffffff", values: { karaoke: "sweep", glow: 0.7, glowColor: "#ffffff", activeColor: "#ffffff", textColor: "#a6a6a6", unsungOpacity: 0.45, feather: 28, blur: 2 } },
        { name: "Neon", color: "#ff4fd8", values: { karaoke: "sweep", glow: 1, glowColor: "#ff4fd8", activeColor: "#ffe3fa", textColor: "#9a86a8", unsungOpacity: 0.35, feather: 18, blur: 2.5 } },
        { name: "Cyber", color: "#3ee6ff", values: { karaoke: "sweep", glow: 1, glowColor: "#3ee6ff", activeColor: "#e0fbff", textColor: "#7d97a3", unsungOpacity: 0.35, feather: 18, blur: 2.5 } },
        { name: "Typewriter", color: "#ffd166", values: { karaoke: "typewriter", glow: 0.6, glowColor: "#ffffff", activeColor: "#ffffff", textColor: "#a6a6a6", unsungOpacity: 0, feather: 0, blur: 2 } },
        { name: "Minimal", color: "#a6a6a6", values: { karaoke: "none", glow: 0, activeColor: "#ffffff", textColor: "#a6a6a6", blur: 1.5 } }
    ]

    function applyPreset(p) {
        for (const key in p.values)
            root.set(key, p.values[key], `${p.name} look`);
    }

    function reset() {
        for (const key in defaults)
            adapter[key] = defaults[key];
        edited("", "All settings reset", "");
    }

    // Emitted for every change made through the settings panel, so the UI
    // can show what just changed.
    signal edited(string key, string label, var value)

    function set(key, value, label) {
        if (adapter[key] === value)
            return;
        adapter[key] = value;
        edited(key, label ?? key, value);
    }

    function isDefault(key) {
        return adapter[key] === defaults[key];
    }

    function resetKey(key, label) {
        set(key, defaults[key], label);
    }

    // Writing on every slider tick would thrash the disk; batch them.
    Timer {
        id: saveTimer
        interval: 300
        onTriggered: file.writeAdapter()
    }

    // First run: create the folder and bring over settings from the old
    // lyrics-wheel location, then load whatever is there.
    property bool _setupDone: false
    Process {
        id: setup
        command: ["sh", "-c", 'mkdir -p "$0" && for f in config.json notion-token; do [ -e "$1/$f" ] && [ ! -e "$0/$f" ] && cp -p "$1/$f" "$0/$f"; done; true', root.dir, root.legacyDir]
        onExited: {
            root._setupDone = true;
            file.reload();
        }
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: saveTimer.restart()
        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound)
                return;
            if (root._setupDone)
                writeAdapter();
            else
                setup.running = true;
        }

        JsonAdapter {
            id: adapter

            property bool lyricsEnabled: root.defaults.lyricsEnabled
            property string player: root.defaults.player
            property string lyricsSource: root.defaults.lyricsSource
            property int spicyOffsetMs: root.defaults.spicyOffsetMs
            property int bridgePort: root.defaults.bridgePort
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
            property string longLines: root.defaults.longLines
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
            property real fillSpeed: root.defaults.fillSpeed
            property real feather: root.defaults.feather
            property string glowColor: root.defaults.glowColor
            property real glow: root.defaults.glow

            property string bgVocals: root.defaults.bgVocals
            property real bgScale: root.defaults.bgScale
            property real bgOpacity: root.defaults.bgOpacity
            property bool bgItalic: root.defaults.bgItalic
            property real bgLinger: root.defaults.bgLinger

            property real viewHeight: root.defaults.viewHeight
            property int viewOffset: root.defaults.viewOffset
            property int edgeFade: root.defaults.edgeFade

            property bool notchEnabled: root.defaults.notchEnabled
            property string notchMode: root.defaults.notchMode
            property string language: root.defaults.language
            property int barPillWidth: root.defaults.barPillWidth
            property bool barShowVisualizer: root.defaults.barShowVisualizer
            property bool barShowTimer: root.defaults.barShowTimer
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
            property int pauseReminderMinutes: root.defaults.pauseReminderMinutes
            property bool checkUpdates: root.defaults.checkUpdates
            property int notchCloseDelay: root.defaults.notchCloseDelay
            property bool samplePreview: root.defaults.samplePreview
            property int maxFps: root.defaults.maxFps
            property bool breakTips: root.defaults.breakTips
            property bool weatherEnabled: root.defaults.weatherEnabled
            property string weatherCity: root.defaults.weatherCity
            property string weatherUnit: root.defaults.weatherUnit
            property bool vizMode: root.defaults.vizMode
            property int vizIdleSeconds: root.defaults.vizIdleSeconds

            property string checklistSource: root.defaults.checklistSource
            property string notionPage: root.defaults.notionPage

            property string finderRoots: root.defaults.finderRoots
            property string finderExclude: root.defaults.finderExclude
            property bool finderHidden: root.defaults.finderHidden
            property string finderFileManager: root.defaults.finderFileManager
            property string finderTerminal: root.defaults.finderTerminal
            property string finderEditor: root.defaults.finderEditor
            property int finderReindexMinutes: root.defaults.finderReindexMinutes

            property bool todayEnabled: root.defaults.todayEnabled
            property bool todaySync: root.defaults.todaySync
            property bool todaySyncLessons: root.defaults.todaySyncLessons
            property string todayCalendar: root.defaults.todayCalendar
            property string todayTimetableDb: root.defaults.todayTimetableDb
            property string todayTasksDb: root.defaults.todayTasksDb
            property string todayDailyDb: root.defaults.todayDailyDb
            property string notesDb: root.defaults.notesDb
            property string todayColumns: root.defaults.todayColumns
            property int todayDays: root.defaults.todayDays
            property bool todayMorningOpen: root.defaults.todayMorningOpen
            property int todayMorningSeconds: root.defaults.todayMorningSeconds
            property bool todayNudges: root.defaults.todayNudges
            property int todayEventMinutes: root.defaults.todayEventMinutes
            property string todaySemesterEnd: root.defaults.todaySemesterEnd
            property int todaySyncMinutes: root.defaults.todaySyncMinutes

            property bool shadow: root.defaults.shadow
            property real backdrop: root.defaults.backdrop
            property bool showTrackInfo: root.defaults.showTrackInfo
            property bool hideWhenPaused: root.defaults.hideWhenPaused
            property bool hideWhenNoLyrics: root.defaults.hideWhenNoLyrics
            property int fadeDuration: root.defaults.fadeDuration
        }
    }
}
