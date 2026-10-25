pragma Singleton
import QtQuick
import Quickshell
import "today/template.mjs" as Template

// "Make Islet's databases": Islet's Notion template (today/template.mjs)
// made in a page the user shared with the integration, then Islet pointed at
// it — so a newcomer needn't build a timetable and task list by hand.
Singleton {
    id: root

    // "" | "working" | "done" | "error"
    property string status: ""
    property string step: ""
    property string error: ""
    // The new Islet page, to open in Notion.
    property string url: ""
    // Pages the integration can see, to put the template in: [{id, title}].
    property var places: []
    property bool loadingPlaces: false

    function loadPlaces() {
        loadingPlaces = true;
        NotionDbService.request("POST", "search", { filter: { property: "object", value: "page" }, sort: { direction: "descending", timestamp: "last_edited_time" }, page_size: 100 }, (ok, found) => {
            loadingPlaces = false;
            if (!ok) {
                places = [];
                error = found;
                return;
            }
            const res = found.results ?? [];
            const title = p => (Object.values(p.properties ?? {}).find(x => x.type === "title")?.title ?? []).map(t => t.plain_text).join("").trim();
            // Pages, not database rows; the ones at the top of the workspace first.
            places = res.filter(p => p.parent?.type !== "database_id" && !p.archived && title(p) !== "")
                .sort((a, b) => (a.parent?.type === "workspace" ? 0 : 1) - (b.parent?.type === "workspace" ? 0 : 1))
                .slice(0, 40)
                .map(p => ({ id: p.id, title: `${p.icon?.emoji ? p.icon.emoji + " " : ""}${title(p)}` }));
        });
    }

    function fail(where, message) {
        status = "error";
        error = `${where}: ${message}`;
    }

    // Each step waits for the one before: the databases link to each other.
    function create(parentPageId) {
        if (status === "working" || !parentPageId)
            return;
        status = "working";
        error = "";
        url = "";
        step = "Islet page";
        const req = (method, path, body, cb) => NotionDbService.request(method, path, body, cb);
        req("POST", "pages", Template.homePage(parentPageId), (ok, home) => {
            if (!ok)
                return fail("Islet page", home);
            url = home.url ?? "";
            const ids = {};
            const next = i => {
                if (i === Template.DATABASES.length)
                    return linked(home.id, ids);
                const key = Template.DATABASES[i];
                step = `database ${i + 1} of ${Template.DATABASES.length}`;
                req("POST", "databases", Template.databaseBody(key, home.id, ids), (ok2, db) => {
                    if (!ok2)
                        return fail(key, db);
                    ids[key] = db.id;
                    next(i + 1);
                });
            };
            next(0);
        });
    }

    // Short names for the subject list's back-links, the example lesson, the
    // Checklist page; then Islet uses them.
    function linked(homeId, ids) {
        const req = (method, path, body, cb) => NotionDbService.request(method, path, body, cb);
        step = "links";
        req("GET", `databases/${ids.mapel}`, null, (ok, db) => {
            const renames = ok ? Template.relationRenames(db.properties, ids) : {};
            const afterRename = () => {
                step = "example lesson";
                req("POST", "pages", Template.exampleMapel(ids), (ok2, subject) => {
                    const afterLesson = () => {
                        step = "Checklist";
                        req("POST", "pages", Template.checklistPage(homeId), (ok3, list) => {
                            if (!ok3)
                                return fail("Checklist", list);
                            use(ids, list.id);
                        });
                    };
                    if (!ok2)
                        return afterLesson();
                    req("POST", "pages", Template.exampleLesson(ids, subject.id), () => afterLesson());
                });
            };
            if (Object.keys(renames).length === 0)
                return afterRename();
            req("PATCH", `databases/${ids.mapel}`, { properties: renames }, () => afterRename());
        });
    }

    // Islet takes up only what it didn't have: switching a task list that
    // syncs with Google would take the old tasks' events out of the calendar.
    // The others are picked on the Calendar & Notion page.
    property var took: []
    function use(ids, checklistId) {
        const took = [];
        // The ones in use are pinned: left to find them by itself, Islet would
        // take the template's newer, empty ones on its next load.
        if (TodayService.timetableDb === "") {
            Config.set("todayTimetableDb", ids.jadwal);
            took.push("timetable");
        } else {
            Config.set("todayTimetableDb", TodayService.timetableDb);
        }
        if (TodayService.tasksDb === "") {
            Config.set("todayTasksDb", ids.tasks);
            took.push("tasks");
        } else {
            Config.set("todayTasksDb", TodayService.tasksDb);
        }
        const ownNotes = TodayService.databases.find(d => (d.title ?? []).map(t => t.plain_text).join("").trim().toLowerCase() === "notes" && d.id !== ids.notes);
        if ((Config.opts.notesDb ?? "") === "" && !ownNotes) {
            Config.set("notesDb", ids.notes);
            took.push("notes");
        } else if ((Config.opts.notesDb ?? "") === "") {
            Config.set("notesDb", ownNotes.id);
        }
        if (ChecklistService.pageId === "") {
            Config.set("notionPage", checklistId.replace(/-/g, ""));
            Config.set("checklistSource", "notion");
            took.push("checklist");
        }
        Config.set("todayEnabled", true);
        root.took = took;
        step = "";
        status = "done";
        TodayService.load();
        ChecklistService.refresh();
    }
}
