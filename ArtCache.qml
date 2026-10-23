pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "media/art.mjs" as Art

// The playing track's art as a local file, for the DankMaterialShell bar
// widget. Loading https images inside DMS made it crash at startup (two of
// its threads reading the system certificates at once in OpenSSL), so Islet
// downloads the art and the widget only ever opens files.
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"}/islet/art`
    readonly property string source: LyricsService.artUrl
    // What the widget shows: a file:// URL, or "" while it downloads (or
    // if it couldn't).
    property string local: ""

    onSourceChanged: fetch()
    Component.onCompleted: {
        Quickshell.execDetached(["find", dir, "-type", "f", "-mtime", "+14", "-delete"]);
        fetch();
    }

    function fetch() {
        const src = source;
        const name = Art.cacheName(src);
        if (name === null) {
            local = src;
            return;
        }
        local = "";
        const path = `${dir}/${name}`;
        const p = fetchComponent.createObject(root, { url: src, path });
        p.running = true;
    }

    // One download per track; an answer for a track already gone is dropped.
    Component {
        id: fetchComponent
        Process {
            id: proc
            property string url
            property string path
            // The URL and paths travel as separate arguments, never through
            // the shell's parsing.
            command: ["sh", "-c", 'mkdir -p "$1" && { [ -s "$2" ] || { curl -fsSL --max-time 15 -o "$2.part" "$3" && mv -f "$2.part" "$2"; }; } && touch "$2"', "sh", root.dir, path, url]
            onExited: code => {
                if (code === 0 && root.source === url)
                    root.local = "file://" + path;
                proc.destroy();
            }
        }
    }
}
