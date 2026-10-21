pragma Singleton
import QtQuick
import Quickshell
import "today/notion.mjs" as Notion
import "today/timetable.mjs" as Timetable

// "Today": the Notion timetable and task list, today's lessons and close
// deadlines, kept in sync with Google Calendar through Dank Calendar.
Singleton {
    id: root

    readonly property var o: Config.opts

    // "loading" | "ready" | "setup" | "error"
    property string status: "loading"
    property string error: ""
    property bool notionOk: false
    // Every timetable row as a Lesson, and every task.
    property var allLessons: []
    property var tasks: []
    // Rows that couldn't be read (e.g. a Jam that isn't a time).
    property var problems: []
    property var databases: []
    property string timetableDb: ""
    property string tasksDb: ""
    property var timetableMap: ({})
    property var tasksMap: ({})
    property real loadedAt: 0
    property real now: Date.now()

    readonly property var lessonsToday: Timetable.lessonsOn(allLessons, new Date(now))

    function dbTitle(id) {
        const db = databases.find(d => d.id.replace(/-/g, "") === id.replace(/-/g, ""));
        return db ? (db.title ?? []).map(t => t.plain_text).join("") : "";
    }

    function overrides() {
        try {
            return JSON.parse(o.todayColumns || "{}");
        } catch (e) {
            return {};
        }
    }

    function load() {
        if (!o.todayEnabled)
            return;
        if (status !== "ready")
            status = "loading";
        DcalService.refresh();
        NotionDbService.listDatabases((ok, dbs) => {
            if (!ok)
                return fail(dbs);
            databases = dbs;
            const pick = Notion.pickDatabases(dbs);
            timetableDb = o.todayTimetableDb || pick.timetable;
            tasksDb = o.todayTasksDb || pick.tasks;
            if (timetableDb === "" && tasksDb === "") {
                status = "setup";
                error = "Islet can't see a timetable or task list in Notion yet. Share your Workspace page with the integration (••• → Connections).";
                return;
            }
            const cols = overrides();
            const props = id => (dbs.find(d => d.id === id) ?? {}).properties ?? {};
            timetableMap = Object.assign(Notion.mapColumns("timetable", props(timetableDb)), cols.timetable ?? {});
            tasksMap = Object.assign(Notion.mapColumns("tasks", props(tasksDb)), cols.tasks ?? {});
            let left = 2;
            const done = () => {
                if (--left > 0)
                    return;
                notionOk = true;
                loadedAt = Date.now();
                now = Date.now();
                status = "ready";
                error = "";
                loaded();
            };
            loadTimetable(done);
            loadTasks(done);
        });
    }

    signal loaded

    function fail(message) {
        notionOk = false;
        error = message;
        status = "error";
    }

    function loadTimetable(done) {
        if (timetableDb === "") {
            allLessons = [];
            return done();
        }
        NotionDbService.query(timetableDb, (ok, rows) => {
            if (!ok)
                return fail(rows);
            const m = timetableMap;
            const ids = [];
            for (const r of rows)
                for (const rel of r.properties[m.mapel]?.relation ?? [])
                    ids.push(rel.id);
            NotionDbService.pageTitles(ids, titles => {
                const read = rows.map(r => Notion.lessonFromRow(r, m, titles));
                allLessons = read.filter(l => !l.error);
                problems = read.filter(l => l.error);
                done();
            });
        });
    }

    function loadTasks(done) {
        if (tasksDb === "") {
            tasks = [];
            return done();
        }
        NotionDbService.query(tasksDb, (ok, rows) => {
            if (!ok)
                return fail(rows);
            tasks = rows.map(r => Notion.taskFromRow(r, tasksMap));
            done();
        });
    }

    function statusText() {
        if (status === "loading")
            return "loading";
        const d = DcalService;
        return [
            `dcal: ${!d.available ? "not running" : d.healthy ? "ok" : d.error} (${d.account || "no account"})`,
            `notion: ${notionOk ? "ok" : error}`,
            `timetable: ${dbTitle(timetableDb) || "-"}`,
            `tasks db: ${dbTitle(tasksDb) || "-"}`,
            `lessons: ${allLessons.length}`,
            `lessons today: ${lessonsToday.length}`,
            `tasks: ${tasks.length}`,
            `problems: ${problems.length}`
        ].join("\n");
    }

    Component.onCompleted: Qt.callLater(load)
    // Notion's secret arrives a moment after start.
    Connections {
        target: ChecklistService
        function onTokenChanged() {
            root.load();
        }
    }
}
