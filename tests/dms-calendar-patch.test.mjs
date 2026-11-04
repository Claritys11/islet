import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const script = join(repo, "integrations/dms/notepad/patch-calendar.py");
const run = (ui, today = join(repo, "today")) => spawnSync("python3", ["-I", script, ui, today], { encoding: "utf8" });

const CARD = `import "../../../Common/DateOnly.js" as DateOnly
leftIconName: "add_task"
placeholderText: I18n.tr("Add a task...", "placeholder in the new-task input field")
                    CalendarService.addTaskForDate(root.selectedDate, txt);
                    text = "";
`;
const BACKEND = `        return calendars.filter(c => !c.readOnly);
        return writable.length > 0 ? writable[0] : null;
    }

    function loadEvents(
`;
function fakeUi(card = CARD, backend = BACKEND) {
    const ui = mkdtempSync(join(tmpdir(), "islet-cal-"));
    mkdirSync(join(ui, "Modules/DDash/Overview"), { recursive: true });
    mkdirSync(join(ui, "Services"));
    writeFileSync(join(ui, "Modules/DDash/Overview/CalendarOverviewCard.qml"), card);
    writeFileSync(join(ui, "Services/CalendarDankBackend.qml"), backend);
    return ui;
}

test("calendar patch: the field makes events, new events skip task lists", () => {
    const ui = fakeUi();
    const r = run(ui);
    assert.equal(r.status, 0, r.stderr);
    const card = readFileSync(join(ui, "Modules/DDash/Overview/CalendarOverviewCard.qml"), "utf8");
    assert.match(card, /agenda\.mjs" as IsletAgenda/);
    assert.match(card, /IsletAgenda\.parseEvent\(txt, root\.selectedDate, 60\)/);
    assert.match(card, /CalendarService\.createEvent\(/);
    assert.match(card, /ToastService\.showError/);
    const backend = readFileSync(join(ui, "Services/CalendarDankBackend.qml"), "utf8");
    assert.match(backend, /supportedComponents\.includes\("VEVENT"\)/);
    assert.match(backend, /c\.name === c\.accountName/);
});

test("calendar patch: a missing anchor in either file writes nothing", () => {
    const ui = fakeUi(CARD, "something else\n");
    const r = run(ui);
    assert.equal(r.status, 1);
    assert.equal(readFileSync(join(ui, "Modules/DDash/Overview/CalendarOverviewCard.qml"), "utf8"), CARD);
});

test("calendar patch: fits the DMS UI on this machine, if there is one", t => {
    const unpacked = process.env.XDG_RUNTIME_DIR ? join(process.env.XDG_RUNTIME_DIR, "dms-shell") : "";
    const sources = unpacked && existsSync(unpacked) ? readdirSync(unpacked).map(d => join(unpacked, d)).filter(d => existsSync(join(d, "shell.qml"))) : [];
    if (!sources.length)
        return t.skip("DMS's own UI isn't unpacked here");
    const ui = fakeUi(readFileSync(join(sources[0], "Modules/DDash/Overview/CalendarOverviewCard.qml"), "utf8"), readFileSync(join(sources[0], "Services/CalendarDankBackend.qml"), "utf8"));
    const r = run(ui);
    assert.equal(r.status, 0, r.stderr);
});
