pragma Singleton
import QtQuick
import Quickshell

// Notion databases for "Today" (the timetable and the task list), with the
// integration secret the Checklist already keeps. Callbacks get
// (ok, reply | errorText).
Singleton {
    id: root

    readonly property string token: ChecklistService.token
    property var _titles: ({})

    function message(status, res) {
        return status === 0 ? "Can't reach Notion — are you offline?"
            : status === 401 ? "Notion rejected the secret. Check it in Settings."
            : status === 404 ? "Notion page not found. In Notion, open your Workspace page → ••• → Connections → add your integration."
            : `Notion error ${status}: ${res?.message ?? ""}`;
    }

    // Busy (429): wait as long as Notion asks, up to three times.
    Component {
        id: waitComponent
        Timer {
            property var then
            running: true
            onTriggered: {
                then();
                destroy();
            }
        }
    }

    function request(method, path, body, cb, attempt) {
        if (token === "") {
            cb(false, "Add your Notion secret in Settings → Checklist or Calendar & Notion.");
            return;
        }
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let res = null;
            try {
                res = JSON.parse(xhr.responseText);
            } catch (e) {}
            if (xhr.status === 429 && (attempt ?? 0) < 3) {
                const wait = Math.max(1, parseFloat(xhr.getResponseHeader("Retry-After")) || 1) * 1000;
                waitComponent.createObject(root, { interval: wait, then: () => request(method, path, body, cb, (attempt ?? 0) + 1) });
                return;
            }
            const ok = xhr.status >= 200 && xhr.status < 300;
            cb(ok, ok ? res : message(xhr.status, res));
        };
        xhr.open(method, `https://api.notion.com/v1/${path}`);
        xhr.setRequestHeader("Authorization", `Bearer ${token}`);
        xhr.setRequestHeader("Notion-Version", "2022-06-28");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body ? JSON.stringify(body) : null);
    }

    // Every page of a paged list (search or a database query).
    function pages(method, path, body, cb, acc, cursor) {
        const b = Object.assign({ page_size: 100 }, body ?? {});
        if (cursor)
            b.start_cursor = cursor;
        request(method, path, b, (ok, res) => {
            if (!ok)
                return cb(false, res);
            const all = (acc ?? []).concat(res.results ?? []);
            if (res.has_more && all.length < 2000)
                pages(method, path, body, cb, all, res.next_cursor);
            else
                cb(true, all);
        });
    }

    // The databases the integration can see, with their columns.
    function listDatabases(cb) {
        pages("POST", "search", { filter: { property: "object", value: "database" } }, cb);
    }

    function query(dbId, cb) {
        pages("POST", `databases/${dbId}/query`, {}, cb);
    }

    // Titles of related pages (a lesson's subject), remembered.
    function pageTitles(ids, cb) {
        const missing = ids.filter(id => _titles[id] === undefined);
        if (missing.length === 0)
            return cb(_titles);
        let left = missing.length;
        for (const id of missing) {
            request("GET", `pages/${id}`, null, (ok, page) => {
                const next = Object.assign({}, _titles);
                if (ok) {
                    const prop = Object.values(page.properties ?? {}).find(p => p.type === "title");
                    next[id] = (prop?.title ?? []).map(t => t.plain_text).join("");
                } else {
                    next[id] = "";
                }
                _titles = next;
                if (--left === 0)
                    cb(_titles);
            });
        }
    }

    function update(pageId, properties, cb) {
        request("PATCH", `pages/${pageId}`, { properties }, cb ?? (() => {}));
    }

    function create(dbId, properties, cb) {
        request("POST", "pages", { parent: { database_id: dbId }, properties }, cb ?? (() => {}));
    }

    // To Notion's trash (restorable there for 30 days).
    function trash(pageId, cb) {
        request("PATCH", `pages/${pageId}`, { archived: true }, cb ?? (() => {}));
    }
}
