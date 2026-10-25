// Standalone load test for deskw-common (no DMS needed): instantiates the
// card and the cookie, then reports the islet connection twice.
import QtQuick
import Quickshell
import "common"

ShellRoot {
    // Widgets bind to the client at once; do the same.
    Component.onCompleted: void IsletClient.connected
    FloatingWindow {
        visible: false
        DeskCard {
            title: "Test"
            cardColor: "#004f56"
            textColor: "#9df0fb"
            Text { text: "x" }
        }
        CookieShape { sides: 9; implicitSize: 120; color: "#81d3df" }
        TextEdit { id: field; text: "a tebal\n- x" }
        FormatBar { id: bar; target: field }
    }
    // M1: a Requester destroyed before islet answers leaves nothing pending
    // and its callback is never called.
    Component {
        id: reqComp
        Requester {}
    }
    property string m1: "pending"
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            const r = reqComp.createObject(null);
            r.request("calendar-month", { year: 2026, month: 9 }, () => { m1 = "called-after-destroy"; });
            r.destroy();
        }
    }
    Timer {
        interval: 4500
        running: true
        onTriggered: {
            if (m1 === "pending")
                m1 = Object.keys(IsletClient._pending).length === 0 ? "ok" : "left-pending";
            console.log("deskw-load m1=" + m1);
        }
    }
    // FormatBar on a real TextEdit: Ctrl+B-style wrap, Enter continues the
    // list, undo takes the wrap back.
    Timer {
        interval: 500
        running: true
        onTriggered: {
            field.select(2, 7);
            bar.run("bold");
            const wrapped = field.text === "a **tebal**\n- x";
            field.cursorPosition = field.length;
            const ev = { key: Qt.Key_Return, modifiers: 0 };
            const handled = bar.handleKey(ev);
            const listed = field.text === "a **tebal**\n- x\n- ";
            // QML's TextEdit keeps remove and insert as separate undo steps.
            for (let i = 0; i < 4 && field.text !== "a tebal\n- x"; i++)
                field.undo();
            const undone = field.text === "a tebal\n- x";
            console.log("deskw-load formatbar=" + (wrapped && handled && listed && undone ? "ok" : "bad:" + JSON.stringify(field.text)));
        }
    }
    Timer {
        interval: 6000
        running: true
        onTriggered: {
            console.log("deskw-load connected=" + IsletClient.connected + " hasState=" + (IsletClient.state !== null))
            Qt.quit()
        }
    }
}
