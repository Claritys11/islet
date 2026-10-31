// Islet's Notion template: what "Make Islet's databases" creates in a page
// the user shared with the integration — an "Islet" page holding a subject
// list, a weekly timetable, a task list and notes, linked to each other, plus
// a Checklist page. Columns are the ones Islet finds by itself (notion.mjs)
// and the Notes widget sorts by. Plain request bodies for Notion's API
// (2022-06-28), so Node can test them.

const text = s => [{ type: "text", text: { content: s } }];
const options = (...pairs) => ({ options: pairs.map(([name, color]) => ({ name, color })) });
const paragraph = s => ({ object: "block", type: "paragraph", paragraph: { rich_text: text(s) } });
const toDo = s => ({ object: "block", type: "to_do", to_do: { rich_text: text(s), checked: false } });
const link = id => ({ relation: { database_id: id, type: "dual_property", dual_property: {} } });

export function homePage(parentPageId) {
    return {
        parent: { page_id: parentPageId },
        icon: { type: "emoji", emoji: "🏝️" },
        properties: { title: { title: text("Islet") } },
        children: [
            paragraph("Islet reads these: your lessons for the week (Jadwal Pelajaran), what you have to do (Tasks), your notes (Notes) and the to-dos below (Checklist)."),
            paragraph("Fill in Mata Pelajaran and Jadwal Pelajaran once; Jam is like 07.00-08.30. Add tasks with a Tenggat (deadline) and they show in the notch, and in Google Calendar if you sync. Daily Tasks come back on their days (Hari; none chosen is every day); Islet takes last day's ticks off Selesai by itself.")
        ]
    };
}

// Made in this order: the others link back to the subject list.
export const DATABASES = ["mapel", "jadwal", "tasks", "notes", "daily"];

const TITLES = { mapel: ["📚", "Mata Pelajaran"], jadwal: ["🗓️", "Jadwal Pelajaran"], tasks: ["✅", "Tasks"], notes: ["📝", "Notes"], daily: ["🔁", "Daily Tasks"] };

function columns(key, ids) {
    switch (key) {
    case "mapel":
        return {
            Mapel: { title: {} },
            Guru: { rich_text: {} },
            "Link Classroom": { url: {} }
        };
    case "jadwal":
        return {
            Slot: { title: {} },
            Hari: { select: options(["Senin", "blue"], ["Selasa", "green"], ["Rabu", "yellow"], ["Kamis", "orange"], ["Jumat", "purple"], ["Sabtu", "gray"]) },
            Jam: { rich_text: {} },
            Guru: { rich_text: {} },
            Mapel: link(ids.mapel),
            Kapan: { formula: { expression: 'let(hari, ["Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"], d, day(now()), if(prop("Hari") == hari.at(d), "Hari ini", if(prop("Hari") == hari.at(mod(d + 1, 7)), "Besok", "")))' } }
        };
    case "tasks":
        return {
            Tugas: { title: {} },
            // A select: Notion's API can't make its status type.
            Status: { select: options(["To do", "gray"], ["Doing", "blue"], ["Done", "green"]) },
            "Rencana Mulai": { date: {} },
            Tenggat: { date: {} },
            Prioritas: { select: options(["Tinggi", "red"], ["Sedang", "yellow"], ["Rendah", "green"]) },
            Tipe: { select: options(["Sekolah", "blue"], ["Project", "purple"], ["Personal", "gray"]) },
            Mapel: link(ids.mapel),
            "GCal ID": { rich_text: {} },
            "Sisa waktu": { formula: { expression: 'if(prop("Status") == "Done" or empty(prop("Tenggat")), "", let(d, dateBetween(prop("Tenggat"), today(), "days"), if(d < 0, "🔴 Telat " + format(abs(d)) + " hari", if(d == 0, "🟠 Hari ini", if(d <= 2, "🟡 " + format(d) + " hari lagi", "🟢 " + format(d) + " hari lagi")))))' } }
        };
    case "daily":
        return {
            Tugas: { title: {} },
            Selesai: { checkbox: {} },
            // None chosen: every day.
            Hari: { multi_select: options(["Senin", "blue"], ["Selasa", "green"], ["Rabu", "yellow"], ["Kamis", "orange"], ["Jumat", "purple"], ["Sabtu", "gray"], ["Minggu", "red"]) },
            Jam: { rich_text: {} },
            Nonaktif: { checkbox: {} }
        };
    case "notes":
        return {
            Judul: { title: {} },
            Tipe: { select: options(["Catatan Pelajaran", "blue"], ["Materi / Cheatsheet", "orange"], ["Ide", "yellow"]) },
            Topik: { multi_select: { options: [] } },
            Mapel: link(ids.mapel),
            Dibuat: { created_time: {} }
        };
    }
    throw new Error(`unknown database ${key}`);
}

// One database, in the Islet page; `ids` has the ones made before it.
export function databaseBody(key, homeId, ids) {
    const [emoji, title] = TITLES[key];
    return {
        parent: { type: "page_id", page_id: homeId },
        icon: { type: "emoji", emoji },
        title: text(title),
        properties: columns(key, ids)
    };
}

// An example subject and a lesson of it, to show how Jam is written.
export function exampleMapel(ids) {
    return { parent: { database_id: ids.mapel }, properties: { Mapel: { title: text("Matematika (contoh)") } } };
}
export function exampleLesson(ids, mapelPageId) {
    return {
        parent: { database_id: ids.jadwal },
        properties: {
            Slot: { title: text("Matematika (contoh)") },
            Hari: { select: { name: "Senin" } },
            Jam: { rich_text: text("07.00-08.30") },
            Mapel: { relation: [{ id: mapelPageId }] }
        }
    };
}

export function checklistPage(homeId) {
    return {
        parent: { page_id: homeId },
        icon: { type: "emoji", emoji: "☑️" },
        properties: { title: { title: text("Checklist") } },
        children: [toDo("Tick me in the notch's Checklist tab"), toDo("Add to-dos here or from the notch")]
    };
}

// The subject list's back-links are named after the databases ("Jadwal
// Pelajaran", "Tasks", "Notes"): shorter names, as a PATCH body.
export function relationRenames(mapelProps, ids) {
    const want = { [ids.jadwal]: "Jadwal", [ids.tasks]: "Tugas", [ids.notes]: "Catatan" };
    const out = {};
    for (const [name, p] of Object.entries(mapelProps ?? {})) {
        const to = p.type === "relation" ? want[p.relation?.database_id] : undefined;
        if (to && to !== name)
            out[name] = { name: to };
    }
    return out;
}
