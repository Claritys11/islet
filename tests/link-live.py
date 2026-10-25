#!/usr/bin/env python3
"""Live check of the socket fields and requests the DMS desktop widgets use.

Needs a running islet (`systemctl --user restart islet` first). Read-only
against Notion except that it asks for an empty note, which islet must
refuse without calling Notion.

    python3 -I tests/link-live.py
"""
import json
import os
import socket
import sys
import time

PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "islet.sock")


def lines(sock):
    buf = b""
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            return
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if line.strip():
                yield json.loads(line)


def reply(sock, stream, req, payload, timeout=20):
    sock.sendall((json.dumps(dict(payload, req=req)) + "\n").encode())
    end = time.time() + timeout
    for msg in stream:
        if msg.get("reply") == req:
            return msg
        if time.time() > end:
            break
    raise AssertionError(f"no reply to {payload['cmd']} within {timeout}s")


def main():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(25)
    s.connect(PATH)
    stream = lines(s)
    state = next(stream)

    for key in ("hasTrack", "timer", "bar", "title"):
        assert key in state, f"old field {key} missing"
    for key in ("lyrics", "tasks", "pomodoro"):
        assert key in state, f"new field {key} missing"
    assert set(state["lyrics"]) >= {"index", "lines", "status", "synced"}, state["lyrics"]
    assert set(state["tasks"]) >= {"status", "items"}, state["tasks"]
    assert set(state["pomodoro"]) >= {"mode", "clock", "running", "progress", "todayCount"}, state["pomodoro"]

    r = reply(s, stream, 7, {"cmd": "notes-list", "limit": 3})
    assert r["ok"], r
    assert isinstance(r["data"], list) and len(r["data"]) <= 3, r
    if r["data"]:
        n = r["data"][0]
        assert set(n) >= {"id", "title", "tipe", "topik", "url"}, n
        g = reply(s, stream, 10, {"cmd": "note-get", "id": n["id"]})
        assert g["ok"] and isinstance(g["data"]["blocks"], list) and isinstance(g["data"]["cut"], bool), str(g)[:300]

    r = reply(s, stream, 8, {"cmd": "calendar-month", "year": 2026, "month": 9})
    assert r["ok"], r
    assert "days" in r["data"] and "byDay" in r["data"], r

    r = reply(s, stream, 9, {"cmd": "note-create", "markdown": "  "})
    assert r["ok"] is False and "empty note" in r["error"], r

    # task-add answers (I2): an empty task is refused without touching Notion.
    r = reply(s, stream, 11, {"cmd": "task-add", "text": "   "})
    assert r["ok"] is False and "empty task" in r["error"], r
    assert "message" in state["tasks"], state["tasks"]

    # task-delete answers: an id that isn't in the list is refused without
    # touching Notion.
    r = reply(s, stream, 12, {"cmd": "task-delete", "id": "not-a-task"})
    assert r["ok"] is False and "task not found" in r["error"], r

    print("link-live: ok")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, KeyError, StopIteration, OSError) as e:
        print("link-live: FAIL", type(e).__name__, e)
        sys.exit(1)
