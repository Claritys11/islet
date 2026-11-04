#!/usr/bin/env python3
"""dms-ui-build's second patch step, on DMS's calendar:

- The field under a day makes a Google Calendar event on that day from one
  line ("Rapat 19.00-20.30", no time is all day; Islet's parseEvent), rather
  than a Google Task: the Tasks API can be out of quota for hours, and DMS
  never says a task failed. If it fails here it says so and keeps the text.
- New events go to a calendar that can hold them, the account's main one
  first: DMS took the first writable one, and a Google task list (Tugas Saya,
  only VTODO) comes before it and answers events with 404.

Every change is anchored on exact text; if any anchor is missing (a DMS update
changed the file) nothing is written and it exits 1, and DMS's calendar stays
as it was.

    python3 -I patch-calendar.py <copied UI dir> <Islet's today dir>
"""
import os
import sys

root = sys.argv[1]
today = os.path.realpath(sys.argv[2])

FILES = {
    os.path.join("Modules", "DDash", "Overview", "CalendarOverviewCard.qml"): [
        ('import "../../../Common/DateOnly.js" as DateOnly\n',
         'import "../../../Common/DateOnly.js" as DateOnly\n'
         'import "file://%s/agenda.mjs" as IsletAgenda\n' % today),
        ('leftIconName: "add_task"\n', 'leftIconName: "event"\n'),
        ('placeholderText: I18n.tr("Add a task...", "placeholder in the new-task input field")\n',
         'placeholderText: "Add event: Rapat 19.00-20.30"\n'),
        ("                    CalendarService.addTaskForDate(root.selectedDate, txt);\n"
         '                    text = "";\n',
         "                    // Islet: an event on this day in Google Calendar; the task\n"
         "                    // list only if no calendar can take one.\n"
         "                    const cal = CalendarService.canCreateEvents ? CalendarService.defaultCalendar() : null;\n"
         "                    if (!cal) {\n"
         "                        CalendarService.addTaskForDate(root.selectedDate, txt);\n"
         '                        text = "";\n'
         "                        return;\n"
         "                    }\n"
         "                    const parsed = IsletAgenda.parseEvent(txt, root.selectedDate, 60);\n"
         "                    if (!parsed) {\n"
         '                        ToastService.showWarning("The event needs a name, as in: Rapat 19.00-20.30");\n'
         "                        return;\n"
         "                    }\n"
         '                    text = "";\n'
         "                    CalendarService.createEvent({\n"
         '                        "calendarId": cal.id,\n'
         '                        "summary": parsed.title,\n'
         '                        "start": parsed.start,\n'
         '                        "end": parsed.end,\n'
         '                        "allDay": parsed.allDay\n'
         "                    }, response => {\n"
         "                        if (!response.error)\n"
         "                            return;\n"
         '                        ToastService.showError("Couldn\'t add the event", String(response.error));\n'
         '                        if (taskInput.text === "")\n'
         "                            taskInput.text = txt;\n"
         "                    });\n"),
    ],
    os.path.join("Services", "CalendarDankBackend.qml"): [
        ("        return calendars.filter(c => !c.readOnly);\n",
         "        // Islet: a task list is writable but can't hold events.\n"
         '        return calendars.filter(c => !c.readOnly && (!c.supportedComponents || c.supportedComponents.includes("VEVENT")));\n'),
        ("        return writable.length > 0 ? writable[0] : null;\n"
         "    }\n"
         "\n"
         "    function loadEvents(",
         "        // Islet: the account's main calendar is named after the account.\n"
         "        return writable.find(c => c.name === c.accountName) ?? writable[0] ?? null;\n"
         "    }\n"
         "\n"
         "    function loadEvents("),
    ],
}

if not os.path.isfile(os.path.join(today, "agenda.mjs")):
    print("patch-calendar: no agenda.mjs in", today, file=sys.stderr)
    sys.exit(1)

patched = {}
for name, edits in FILES.items():
    path = os.path.join(root, name)
    try:
        with open(path, encoding="utf-8") as f:
            src = f.read()
    except OSError as e:
        print("patch-calendar:", e, file=sys.stderr)
        sys.exit(1)
    for old, new in edits:
        if src.count(old) != 1:
            print("patch-calendar: anchor not found once:", old.splitlines()[0].strip(), file=sys.stderr)
            sys.exit(1)
        src = src.replace(old, new)
    patched[path] = src

for path, src in patched.items():
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
print("patch-calendar: ok")
