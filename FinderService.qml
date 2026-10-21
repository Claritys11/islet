pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "finder/rank.mjs" as Rank

// Finder: find files and folders by fragments of their names, Listary-style.
// An index of every folder and file (finder/index.sh, via fd) is rebuilt in
// the background; each search filters it with fzf — folders first, since
// that's ~5× faster, files a moment later — and ranks the matches
// (finder/rank.mjs). Kept apart from the rest of Islet so it can become its
// own project.
Singleton {
    id: root

    readonly property var o: Config.opts
    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: `${Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"}/islet/finder`
    readonly property string script: decodeURIComponent(String(Qt.resolvedUrl("finder/index.sh")).replace(/^file:\/\//, ""))
    readonly property string searchScript: decodeURIComponent(String(Qt.resolvedUrl("finder/search.sh")).replace(/^file:\/\//, ""))

    // Set to search; results follow.
    property string query: ""
    // [{ path, kind, project, positions, name, short }]
    property var results: []
    // "ready" | "indexing" | "missing-tools" | "no-folders"
    property string status: "indexing"
    property real indexedAt: 0
    property var counts: ({ dirs: 0, files: 0 })
    // A short note after an action ("Path copied").
    property string message: ""
    // The apps actions use, with "auto" resolved.
    readonly property var apps: ({
            fileManager: o.finderFileManager || (_defaultFm.includes("dolphin") ? "dolphin" : ""),
            terminal: o.finderTerminal || Rank.detect(["ghostty", "kitty", "foot", "alacritty", "konsole"], _available),
            editor: o.finderEditor || Rank.detect(["code", "codium", "zed"], _available)
        })
    property var _available: []
    property string _defaultFm: ""
    property var _projects: ({})
    property bool _hasIndex: false
    property bool _again: false

    // `islet find [text]`: the notch opens Finder.
    signal openRequested(string prefill)
    // An action ran (the view closes on everything but "copy").
    signal acted(string action)

    // ── Index ─────────────────────────────────────────────────────
    function roots() {
        return o.finderRoots.split(",").map(r => r.trim()).filter(r => r !== "").map(r => r === "~" ? home : r.startsWith("~/") ? home + r.slice(1) : r);
    }

    function reindex() {
        // fd or fzf missing: nothing to build, and the message must stay.
        if (status === "missing-tools")
            return;
        // A rebuild is running: run another when it ends, so a change to
        // the settings made meanwhile isn't lost.
        if (indexer.running) {
            _again = true;
            return;
        }
        status = "indexing";
        indexer.command = ["sh", script, dir, o.finderHidden ? "1" : "0", o.finderExclude].concat(roots());
        indexer.running = true;
    }

    Process {
        id: indexer
        onExited: code => {
            if (root._again) {
                root._again = false;
                Qt.callLater(root.reindex);
            }
            if (code === 127) {
                root.status = "missing-tools";
                return;
            }
            if (code === 2) {
                root.status = "no-folders";
                return;
            }
            root.indexedAt = Date.now();
            projects.reload();
            counter.running = true;
            if (root.query !== "")
                root.search(root.query);
        }
    }

    FileView {
        id: projects
        path: `${root.dir}/projects.txt`
        onLoaded: {
            const set = {};
            for (const p of text().split("\n"))
                if (p !== "")
                    set[p] = true;
            root._projects = set;
        }
    }

    // How big the index is, and whether there is one yet.
    Process {
        id: counter
        command: ["sh", "-c", 'cd "$0" 2>/dev/null && wc -l < dirs.txt && wc -l < files.txt', root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = text.trim().split("\n").map(s => parseInt(s));
                root._hasIndex = n.length === 2 && !isNaN(n[0]);
                root.counts = root._hasIndex ? { dirs: n[0], files: n[1] } : { dirs: 0, files: 0 };
                if (!indexer.running && root.status !== "missing-tools")
                    root.status = root._hasIndex ? "ready" : "indexing";
            }
        }
    }

    // Which tools exist, and the default file manager.
    Process {
        id: tools
        running: true
        command: ["sh", "-c", 'for c in fd fzf wl-copy ghostty kitty foot alacritty konsole code codium zed; do command -v "$c" >/dev/null 2>&1 && echo "$c"; done; echo "fm:$(xdg-mime query default inode/directory 2>/dev/null)"']
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root._defaultFm = (lines.find(l => l.startsWith("fm:")) ?? "fm:").slice(3);
                root._available = lines.filter(l => !l.startsWith("fm:"));
                if (!root._available.includes("fd") || !root._available.includes("fzf"))
                    root.status = "missing-tools";
                else {
                    counter.running = true;
                    root.reindex();
                }
            }
        }
    }

    Timer {
        running: root.status !== "missing-tools"
        repeat: true
        interval: Math.max(1, root.o.finderReindexMinutes) * 60000
        onTriggered: root.reindex()
    }

    Connections {
        target: root.o
        function onFinderRootsChanged() {
            root.reindex();
        }
        function onFinderExcludeChanged() {
            root.reindex();
        }
        function onFinderHiddenChanged() {
            root.reindex();
        }
    }

    // ── Search ────────────────────────────────────────────────────
    // Every search gets a number; answers to an older one are dropped, so
    // fast typing never shows stale results.
    property int _id: 0
    property var _dirHits: null
    property var _fileHits: null
    // The query whose folder and file results are both in.
    property var _doneFor: null
    // The query the results on screen belong to (folders may be in before files).
    property var _shownFor: null
    // An action asked for before its search finished.
    property string _pending: ""

    function runPending() {
        if (_pending === "")
            return;
        const action = _pending;
        _pending = "";
        if (results.length > 0)
            act(0, action);
        else
            flash("Nothing found");
    }

    onQueryChanged: debounce.restart()
    Timer {
        id: debounce
        interval: 60
        onTriggered: root.search(root.query)
    }

    // Search now (opening Finder, the command line), not after the typing
    // pause — even when the text is the same as last time.
    function begin(q) {
        query = q;
        debounce.stop();
        search(q);
    }

    function search(q) {
        const id = ++_id;
        _shownFor = null;
        _dirHits = _fileHits = null;
        if (q.trim() === "") {
            showRecent(id, q);
            return;
        }
        const fq = Rank.fzfQuery(q);
        for (const p of [dirSearch, fileSearch]) {
            p.running = false;
            p.reqId = id;
            p.q = q;
            // The first output line is the search's number: a restarted
            // Process still reports the run it cut short, and only the
            // output itself can say which search it belongs to.
            p.command = ["sh", searchScript, String(id), fq, `${dir}/${p.file}`];
            p.running = true;
        }
    }

    component Search: Process {
        id: self
        property int reqId
        property string q
        property string file
        property string kind
        stdout: StdioCollector {
            onStreamFinished: {
                const p = self;
                const lines = text.split("\n");
                if (lines[0] !== String(root._id))
                    return;
                const hits = lines.slice(1).filter(l => l !== "").map(path => ({ path, kind: p.kind, project: p.kind === "dir" && root._projects[path] === true }));
                if (p.kind === "dir")
                    root._dirHits = hits;
                else
                    root._fileHits = hits;
                root.publish(p.q);
            }
        }
    }
    Search {
        id: dirSearch
        file: "dirs.txt"
        kind: "dir"
    }
    Search {
        id: fileSearch
        file: "files.txt"
        kind: "file"
    }

    function present(e) {
        return Object.assign({}, e, { name: e.path.split("/").pop() || e.path, short: Rank.shortPath(e.path, home) });
    }

    // Folders show as soon as they're in; files join when they arrive.
    function publish(q) {
        const all = (_dirHits ?? []).concat(_fileHits ?? []);
        results = Rank.rank(q, all, Store.db.finderHistory ?? {}, Date.now()).slice(0, 50).map(present);
        _shownFor = q;
        if (_dirHits !== null && _fileHits !== null) {
            _doneFor = q;
            runPending();
        }
    }

    // Nothing typed: what you opened lately, if it still exists.
    function showRecent(id, q) {
        const list = Rank.recent(Store.db.finderHistory ?? {}, Date.now(), 8);
        if (list.length === 0) {
            results = [];
            _shownFor = _doneFor = q;
            runPending();
            return;
        }
        exists.reqId = id;
        exists.q = q;
        exists.list = list;
        exists.command = ["sh", "-c", 'for p; do [ -e "$p" ] && printf "%s\\n" "$p"; done; true', "sh"].concat(list.map(e => e.path));
        exists.running = true;
    }
    Process {
        id: exists
        property int reqId
        property string q
        property var list: []
        stdout: StdioCollector {
            onStreamFinished: {
                if (exists.reqId !== root._id)
                    return;
                const here = text.split("\n");
                root.results = exists.list.filter(e => here.includes(e.path)).map(e => root.present(Object.assign({ positions: [], project: root._projects[e.path] === true }, e)));
                root._shownFor = root._doneFor = exists.q;
                root.runPending();
            }
        }
    }

    // ── Actions ───────────────────────────────────────────────────
    // "open" | "terminal" | "editor" | "reveal" | "copy"
    function act(index, action) {
        // The list on screen is still the previous search's (Enter right
        // after typing): act on the best match once this one is in.
        if (_shownFor !== query) {
            _pending = action;
            return;
        }
        const entry = results[index];
        if (!entry)
            return;
        if (action === "copy") {
            if (!_available.includes("wl-copy")) {
                flash("Install wl-clipboard to copy paths");
                return;
            }
            Quickshell.execDetached(Rank.actionCommand("copy", entry, apps));
            flash("Path copied");
            acted(action);
            return;
        }
        if ((action === "terminal" && apps.terminal === "") || (action === "editor" && apps.editor === "")) {
            flash(action === "terminal" ? "No terminal found — pick one in Settings → Finder" : "No editor found — pick one in Settings → Finder");
            return;
        }
        // Moved or deleted since the index was built?
        checker.entry = entry;
        checker.action = action;
        checker.command = ["test", "-e", entry.path];
        checker.running = true;
    }
    Process {
        id: checker
        property var entry
        property string action
        onExited: code => {
            if (code !== 0) {
                root.flash("Not found — reindexing");
                root.reindex();
                return;
            }
            Quickshell.execDetached(Rank.actionCommand(action, entry, root.apps));
            Store.db.finderHistory = Rank.remember(Store.db.finderHistory ?? {}, entry, Date.now());
            root.acted(action);
        }
    }

    function flash(text) {
        message = text;
        messageTimer.restart();
    }
    Timer {
        id: messageTimer
        interval: 1800
        onTriggered: root.message = ""
    }

    // For `islet find --print`: the top results once a query is done.
    function resultsFor(q) {
        if (status === "missing-tools")
            return "error: install fd and fzf";
        if (_doneFor !== q || query !== q)
            return "pending";
        return results.slice(0, 5).map(r => `${r.kind}\t${r.short}`).join("\n");
    }
}
