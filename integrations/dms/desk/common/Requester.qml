import QtQuick

// IsletClient.request for one widget: what it still waits for is cancelled
// when the widget is destroyed (DMS reload/restart), so no answer calls a
// callback whose widget is gone — the "TypeError" pair in the journal on
// every DMS start (review M1).
QtObject {
    id: root

    property var _reqs: ({})

    function request(cmd, args, cb, timeoutMs): void {
        let req = 0;
        req = IsletClient.request(cmd, args, (ok, data, err) => {
            delete root._reqs[req];
            cb(ok, data, err);
        }, timeoutMs);
        if (req)
            root._reqs[req] = true;
    }

    Component.onDestruction: {
        for (const req of Object.keys(root._reqs))
            IsletClient.cancel(Number(req));
    }
}
