pragma Singleton
import QtQuick
import Quickshell
import "link/desk.mjs" as Desk

// The Notion "Notes" database, for the DankMaterialShell Notes desktop
// widget (through IsletLink): the newest notes, one note's blocks, and a new
// note from a few lines of Markdown. The database is Config `notesDb`, or the
// one titled "Notes" the integration can see.
Singleton {
    id: root

    property string dbId: ""
    property var db: null
    property string error: ""

    function titleProp() {
        const props = root.db?.properties ?? {};
        return Object.keys(props).find(k => props[k].type === "title") ?? "Name";
    }

    // The select column notes are sorted into ("Tipe" in the user's
    // workspace), and the multi-select topics ("Topik").
    function selectProp(type, preferred) {
        const props = root.db?.properties ?? {};
        if (props[preferred]?.type === type)
            return preferred;
        return Object.keys(props).find(k => props[k].type === type) ?? "";
    }

    // Find (once) the database, then run `then`.
    function ready(then, fail) {
        if (root.db)
            return then();
        NotionDbService.listDatabases((ok, dbs) => {
            if (!ok)
                return fail(dbs);
            const want = Config.opts.notesDb ?? "";
            const plain = s => s.replace(/-/g, "");
            const title = d => (d.title ?? []).map(t => t.plain_text).join("").trim();
            const found = want !== ""
                ? dbs.find(d => plain(d.id) === plain(want))
                : dbs.find(d => title(d).toLowerCase() === "notes");
            if (!found)
                return fail(want !== "" ? "Notes database not found (Config notesDb)." : "No Notion database called \"Notes\" is shared with Islet.");
            root.db = found;
            root.dbId = found.id;
            then();
        });
    }

    function text(rich) {
        return (rich ?? []).map(t => t.plain_text).join("");
    }

    // cb(ok, [{id, title, tipe, topik, created, url}]) — newest first.
    function list(limit, tipe, cb) {
        ready(() => {
            const body = {
                page_size: Math.max(1, Math.min(100, limit || 30)),
                sorts: [{ timestamp: "created_time", direction: "descending" }]
            };
            const tipeProp = selectProp("select", "Tipe");
            if (tipe && tipeProp)
                body.filter = { property: tipeProp, select: { equals: tipe } };
            NotionDbService.request("POST", `databases/${root.dbId}/query`, body, (ok, res) => {
                if (!ok)
                    return cb(false, res);
                const t = titleProp(), s = selectProp("select", "Tipe"), m = selectProp("multi_select", "Topik");
                cb(true, (res.results ?? []).map(p => ({
                    id: p.id,
                    title: text(p.properties?.[t]?.title) || "(tanpa judul)",
                    tipe: s ? (p.properties?.[s]?.select?.name ?? "") : "",
                    topik: m ? (p.properties?.[m]?.multi_select ?? []).map(o => o.name) : [],
                    created: p.created_time,
                    url: p.url
                })));
            });
        }, err => cb(false, err));
    }

    // cb(ok, blocks, cut): the note's blocks with their children at any
    // depth (columns, callouts, toggles too), paged past Notion's 100; `cut`
    // when it stopped at Desk.walkBlocks' caps.
    function get(id, cb) {
        const fetch = (blockId, cursor, done) => NotionDbService.request("GET",
            `blocks/${blockId}/children?page_size=100${cursor ? "&start_cursor=" + encodeURIComponent(cursor) : ""}`, null, done);
        Desk.walkBlocks(fetch, id, {}, cb);
    }

    // cb(ok, {id, url}) for a note typed as Markdown (first line = title).
    function create(markdown, cb) {
        let note;
        try {
            note = Desk.markdownToBlocks(markdown);
        } catch (e) {
            return cb(false, e.message);
        }
        ready(() => {
            const properties = {};
            properties[titleProp()] = { title: note.titleRich };
            // Notion takes at most 100 blocks a call: the rest are appended.
            const parts = Desk.chunks(note.blocks, 100);
            NotionDbService.request("POST", "pages", { parent: { database_id: root.dbId }, properties, children: parts[0] ?? [] }, (ok, res) => {
                if (!ok)
                    return cb(false, res);
                const page = { id: res.id, url: res.url };
                const append = i => {
                    if (i >= parts.length)
                        return cb(true, page);
                    NotionDbService.request("PATCH", `blocks/${page.id}/children`, { children: parts[i] }, (ok2, res2) => {
                        if (!ok2)
                            return cb(false, `Saved only part of the note: ${res2}`);
                        append(i + 1);
                    });
                };
                append(1);
            });
        }, err => cb(false, err));
    }
}
