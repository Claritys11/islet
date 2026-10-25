import QtQuick
import "fmtkeys.mjs" as Keys
import "mdedit.mjs" as Md

// The formatting toolbar and shortcuts for a Markdown text field: the Notes
// desktop widget and (patched in by dms-ui-build) DMS's own notepad. Works
// on any TextEdit or TextArea; edits go through remove/insert so Ctrl+Z
// still undoes them. Needs nothing from DMS, so tests/load.sh covers it.
Flow {
    id: root

    property Item target
    property color textColor: "#9df0fb"
    property color accentColor: "#81d3df"
    property string fontFamily: ""
    property real fontSize: 13
    // Tab on any line indents (Notes); otherwise only on list lines, so a
    // plain Tab still types a tab in the notepad.
    property bool indentAnywhere: true
    // The hovered button's name and shortcut, for the host to show.
    property string hint: ""

    spacing: 3

    function apply(r): void {
        const d = Md.diff(root.target.text, r.text);
        if (d.remove > 0)
            root.target.remove(d.at, d.at + d.remove);
        if (d.insert !== "")
            root.target.insert(d.at, d.insert);
        root.target.select(r.start, r.end);
    }

    function run(action): void {
        const t = root.target;
        if (!t || t.readOnly)
            return;
        const s = t.selectionStart, e = t.selectionEnd;
        const wraps = { bold: ["**"], italic: ["*"], strike: ["~~"], underline: ["<u>", "</u>"], code: ["`"] };
        if (wraps[action])
            root.apply(Md.wrap(t.text, s, e, wraps[action][0], wraps[action][1]));
        else if (action === "link")
            root.apply(Md.link(t.text, s, e));
        else
            root.apply(Md.setBlock(t.text, s, e, action));
        t.forceActiveFocus();
    }

    function onListLine(): bool {
        const t = root.target, pos = t.selectionStart;
        const line = t.text.slice(t.text.lastIndexOf("\n", pos - 1) + 1).split("\n")[0];
        return /^[ \t]*(- \[[ xX]\] |[-*] |\d+[.)] |> )/.test(line);
    }

    // A key from the field's Keys.onPressed; true when it was a formatting
    // key (then accept the event), false to let the field have it.
    function handleKey(event): bool {
        const t = root.target;
        if (!t || t.readOnly)
            return false;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0, shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const action = Keys.keyAction(event.key, ctrl, shift);
        if (action) {
            root.run(action);
            return true;
        }
        const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
        if (enter && !ctrl && !shift && !(event.modifiers & Qt.AltModifier) && t.selectionStart === t.selectionEnd) {
            const r = Md.onEnter(t.text, t.cursorPosition);
            if (r) {
                root.apply(r);
                return true;
            }
            return false;
        }
        if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && !ctrl && (root.indentAnywhere || root.onListLine())) {
            root.apply(Md.indent(t.text, t.selectionStart, t.selectionEnd, event.key === Qt.Key_Backtab || shift ? -1 : 1));
            return true;
        }
        return false;
    }

    Repeater {
        model: Keys.TOOLS
        Rectangle {
            required property var modelData
            width: Math.max(28, toolLabel.implicitWidth + 12)
            height: 26
            radius: 8
            color: toolArea.containsMouse ? Qt.alpha(root.accentColor, 0.3) : Qt.alpha(root.textColor, 0.08)
            Text {
                id: toolLabel
                anchors.centerIn: parent
                text: modelData.label
                textFormat: Text.PlainText
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: root.fontSize
                font.bold: modelData.id === "bold" || modelData.id.startsWith("h")
                font.italic: modelData.id === "italic"
                font.underline: modelData.id === "underline"
                font.strikeout: modelData.id === "strike"
            }
            MouseArea {
                id: toolArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: root.hint = containsMouse ? modelData.tip : ""
                onClicked: root.run(modelData.id)
            }
        }
    }
}
