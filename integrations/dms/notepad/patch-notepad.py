#!/usr/bin/env python3
"""dms-ui-build's patch step: gives DMS's notepad the formatting toolbar
and shortcuts of Islet's Notes widget (FormatBar in ../desk/common).

Every change is anchored on exact text from DMS's NotepadTextEditor.qml; if
any anchor is missing (a DMS update changed the file) nothing is written
and it exits 1, so dms-run-ui keeps using DMS's own UI.

    python3 -I patch-notepad.py <copied UI dir> <desk/common dir>
"""
import os
import sys

root = sys.argv[1]
path = os.path.join(root, "Modules", "Notepad", "NotepadTextEditor.qml")
common = os.path.realpath(sys.argv[2])

with open(path, encoding="utf-8") as f:
    src = f.read()

EDITS = [
    # The shared component, under its own name.
    ("import qs.DCommon.Widgets\n",
     'import qs.DCommon.Widgets\nimport "file://%s" as Deskw\n' % common),
    # The toolbar above the editor, which gives up its height.
    ("    StyledRect {\n"
     "        width: parent.width\n"
     "        height: parent.height - bottomControls.height - Theme.spacingM - (searchVisible ? searchBar.height + Theme.spacingM : 0)\n",
     "    // Islet: formatting toolbar (Markdown, Notion's shortcuts).\n"
     "    Deskw.FormatBar {\n"
     "        id: deskwBar\n"
     "        width: parent.width\n"
     "        target: textArea\n"
     "        indentAnywhere: false\n"
     "        textColor: Theme.surfaceText\n"
     "        accentColor: Theme.primary\n"
     "        fontFamily: SettingsData.fontFamily\n"
     "        fontSize: Theme.fontSizeSmall\n"
     "    }\n"
     "\n"
     "    StyledRect {\n"
     "        width: parent.width\n"
     "        height: parent.height - bottomControls.height - Theme.spacingM - (searchVisible ? searchBar.height + Theme.spacingM : 0) - deskwBar.height - Theme.spacingM\n"),
    # Its shortcuts, Enter list continuation and Tab on list lines, before
    # the notepad's own keys (Ctrl+S/O/N/A/F/P stay the notepad's).
    ("                        Keys.onPressed: event => {\n"
     "                            if (event.modifiers & Qt.ControlModifier) {\n"
     "                                switch (event.key) {\n"
     "                                case Qt.Key_S:\n",
     "                        Keys.onPressed: event => {\n"
     "                            if (deskwBar.handleKey(event)) {\n"
     "                                event.accepted = true;\n"
     "                                return;\n"
     "                            }\n"
     "                            if (event.modifiers & Qt.ControlModifier) {\n"
     "                                switch (event.key) {\n"
     "                                case Qt.Key_S:\n"),
]

for old, new in EDITS:
    if src.count(old) != 1:
        print("patch-notepad: anchor not found once:", old.splitlines()[0].strip(), file=sys.stderr)
        sys.exit(1)
    src = src.replace(old, new)

if not os.path.isfile(os.path.join(common, "FormatBar.qml")):
    print("patch-notepad: no FormatBar.qml in", common, file=sys.stderr)
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("patch-notepad: ok")
