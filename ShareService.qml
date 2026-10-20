pragma Singleton
import QtQuick
import Quickshell

// "Now playing" share card: shell.qml shows ShareWindow while `open`.
Singleton {
    id: root

    property bool open: false
    // Line shown on the card (index into LyricsService.lines).
    property int line: 0

    readonly property string scratch: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/islet-share.png`

    // "copy" | "save", from the command line; ShareWindow carries it out.
    signal action(string what)
    property string _pending: ""

    function run(what) {
        if (!open) {
            _pending = what;
            show();
        } else {
            action(what);
        }
    }

    function show() {
        if (!LyricsService.hasTrack)
            return;
        line = sungLine(LyricsService.currentIndex);
        open = true;
    }

    // The line being sung, or the last one before an instrumental break.
    function sungLine(i) {
        const L = LyricsService.lines;
        for (let j = Math.min(i, L.length - 1); j >= 0; j--)
            if (!L[j].interlude && L[j].main !== "")
                return j;
        return L.findIndex(l => !l.interlude);
    }

    // Next or previous line with words, from `line`.
    function step(d) {
        const L = LyricsService.lines;
        for (let j = line + d; j >= 0 && j < L.length; j += d)
            if (!L[j].interlude && L[j].main !== "") {
                line = j;
                return;
            }
    }

    function fileName() {
        const clean = s => s.replace(/[\/\\:*?"<>|]/g, "").trim();
        return `${clean(LyricsService.artist)} - ${clean(LyricsService.title)}.png`;
    }
}
