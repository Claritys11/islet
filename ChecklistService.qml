pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Checklist backed either by a local file or by the to-do blocks of a Notion
// page. Both expose the same `items` / add / setChecked / remove API.
Singleton {
    id: root

    readonly property bool useNotion: Config.opts.checklistSource === "notion"
    readonly property string tokenPath: `${Config.dir}/notion-token`
    property string token: ""
    readonly property string pageId: parsePageId(Config.opts.notionPage)

    // [{ id, text, checked }]
    readonly property var items: useNotion ? _notionItems : Store.db.checklist
    property var _notionItems: []
    // "ready" | "loading" | "setup" | "error"
    property string status: "ready"
    property string error: ""
    readonly property int doneCount: items.filter(i => i.checked).length

    // Accepts a page URL or a raw ID, with or without dashes.
    function parsePageId(s) {
        const ids = (s ?? "").split("?")[0].replace(/-/g, "").match(/[0-9a-fA-F]{32}/g);
        if (!ids)
            return "";
        const id = ids[ids.length - 1].toLowerCase();
        return `${id.slice(0, 8)}-${id.slice(8, 12)}-${id.slice(12, 16)}-${id.slice(16, 20)}-${id.slice(20)}`;
    }

    function add(text) {
        text = text.trim();
        if (text === "")
            return;
        if (!useNotion) {
            Store.db.checklist = Store.db.checklist.concat([{ id: `${Date.now()}`, text, checked: false }]);
            return;
        }
        const body = { children: [{ object: "block", type: "to_do", to_do: { rich_text: [{ type: "text", text: { content: text } }], checked: false } }] };
        notion("PATCH", `blocks/${pageId}/children`, body, (ok, res) => {
            if (ok)
                _notionItems = _notionItems.concat(res.results.filter(b => b.type === "to_do").map(toItem));
        });
    }

    function setChecked(id, checked) {
        const update = list => list.map(i => i.id === id ? Object.assign({}, i, { checked }) : i);
        if (!useNotion) {
            Store.db.checklist = update(Store.db.checklist);
            return;
        }
        // Optimistic: flip it now, roll back if Notion refuses.
        const before = _notionItems;
        _notionItems = update(_notionItems);
        notion("PATCH", `blocks/${id}`, { to_do: { checked } }, ok => {
            if (!ok)
                _notionItems = before;
        });
    }

    function remove(id) {
        if (!useNotion) {
            Store.db.checklist = Store.db.checklist.filter(i => i.id !== id);
            return;
        }
        const before = _notionItems;
        _notionItems = _notionItems.filter(i => i.id !== id);
        notion("DELETE", `blocks/${id}`, null, ok => {
            if (!ok)
                _notionItems = before;
        });
    }

    function clearDone() {
        for (const i of items.filter(i => i.checked))
            remove(i.id);
    }

    function refresh() {
        if (!useNotion) {
            status = "ready";
            return;
        }
        if (token === "" || pageId === "") {
            status = "setup";
            error = token === "" ? "Add your Notion integration token in Settings → Focus." : "Paste the URL of the Notion page that holds your checklist.";
            return;
        }
        if (_notionItems.length === 0)
            status = "loading";
        loadPage("", []);
    }

    function loadPage(cursor, acc) {
        notion("GET", `blocks/${pageId}/children?page_size=100${cursor ? "&start_cursor=" + cursor : ""}`, null, (ok, res) => {
            if (!ok)
                return;
            acc = acc.concat(res.results.filter(b => b.type === "to_do").map(toItem));
            if (res.has_more && acc.length < 500)
                loadPage(res.next_cursor, acc);
            else {
                _notionItems = acc;
                status = "ready";
            }
        });
    }

    function toItem(b) {
        return { id: b.id, text: b.to_do.rich_text.map(t => t.plain_text).join(""), checked: b.to_do.checked };
    }

    function saveToken(t) {
        tokenWriter.pending = t.trim();
        tokenWriter.running = true;
    }

    function notion(method, path, body, cb) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let res = null;
            try {
                res = JSON.parse(xhr.responseText);
            } catch (e) {}
            const ok = xhr.status >= 200 && xhr.status < 300;
            if (!ok) {
                status = "error";
                error = xhr.status === 0 ? "Can't reach Notion — are you offline?"
                    : xhr.status === 401 ? "Notion rejected the token. Check it in Settings."
                    : xhr.status === 404 ? "Page not found. In Notion, open the page → ••• → Connections → add your integration."
                    : `Notion error ${xhr.status}: ${res?.message ?? ""}`;
            }
            cb(ok, res);
        };
        xhr.open(method, `https://api.notion.com/v1/${path}`);
        xhr.setRequestHeader("Authorization", `Bearer ${token}`);
        xhr.setRequestHeader("Notion-Version", "2022-06-28");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body ? JSON.stringify(body) : null);
    }

    onUseNotionChanged: refresh()
    onPageIdChanged: refresh()
    onTokenChanged: refresh()

    // Pick up edits made in Notion itself.
    Timer {
        running: root.useNotion && root.status !== "setup"
        repeat: true
        interval: 120000
        onTriggered: root.refresh()
    }

    FileView {
        path: root.tokenPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.token = text().trim()
        onLoadFailed: root.token = ""
    }

    // Written through stdin with a private umask, so the secret never shows up
    // in the process list and the file is readable only by you.
    Process {
        id: tokenWriter
        property string pending
        command: ["sh", "-c", 'mkdir -p "$(dirname "$0")" && umask 077 && cat > "$0"', root.tokenPath]
        stdinEnabled: true
        onStarted: {
            write(pending);
            stdinEnabled = false;
        }
        onExited: {
            stdinEnabled = true;
            root.token = pending;
            pending = "";
        }
    }
}
