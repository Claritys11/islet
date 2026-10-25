"""place.py install|uninstall SETTINGS SESSION [both|left|right] — Islet's
desktop widgets on the DMS desktop, laid out so none overlap: clock, calendar
and lyrics in one column, to-do, notes and the timer in the other. "both"
puts the columns at the two edges; "left"/"right" puts both columns on that
side (away from Islet's lyrics on the screen edge). Right-hand columns are
anchored to the right edge, so they fit any screen. Widgets already there keep
their place. GitHub isn't placed: it needs a user name first.

DMS must not be running: it doesn't reload session.json, and would write its
own default places over these.
"""
import json, os, sys, time

# widgetType, name, column (0 or 1), top (px on a 1080 px screen), width, height
LAYOUT = [
    ("deskwClock", "Clock", 0, 60, 220, 220),
    ("deskwCalendar", "Calendar", 0, 300, 300, 280),
    ("deskwLyrics", "Lyrics", 0, 600, 420, 220),
    ("deskwTodo", "To-Do", 1, 60, 360, 300),
    ("deskwNotes", "Notes", 1, 380, 360, 380),
    ("deskwPomodoro", "Pomodoro", 1, 780, 360, 220),
]
COLUMN = {0: 420, 1: 360}
EDGE, GAP = 40, 20


def spot(column, top, width, height, side):
    """Where one widget goes: px from its edge (a fraction of 1920, as DMS
    keeps synced places), and which edge."""
    if side == "both":
        edge, offset = ("left", EDGE) if column == 0 else ("right", EDGE)
    else:
        # The column nearer the edge first: the other one beside it.
        near = 0 if side == "left" else 1
        edge = side
        offset = EDGE if column == near else EDGE + COLUMN[near] + GAP
    out = {"x": offset / 1920, "y": top / 1080, "width": width, "height": height}
    if edge == "right":
        out["anchorX"] = "end"
    return out


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".islet-tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)


def main(mode, settings_path, session_path, side="both"):
    if side not in ("both", "left", "right"):
        sys.exit("side must be both, left or right")
    if not os.path.exists(settings_path):
        sys.exit(f"{settings_path} not found")
    settings, session = load(settings_path), load(session_path)
    instances = settings.get("desktopWidgetInstances") or []
    positions = session.get("desktopWidgetInstancePositions") or {}
    if mode == "install":
        have = {i.get("widgetType") for i in instances}
        stamp = int(time.time() * 1000)
        for n, (kind, name, column, top, w, h) in enumerate(LAYOUT):
            if kind in have:
                continue
            iid = f"dw_islet_{stamp}_{n}"
            instances.append({"id": iid, "widgetType": kind, "name": name, "enabled": True,
                              "config": {"syncPositionAcrossScreens": True}})
            positions[iid] = {"_synced": spot(column, top, w, h, side)}
    elif mode == "uninstall":
        gone = {i["id"] for i in instances if str(i.get("widgetType", "")).startswith("deskw")}
        instances = [i for i in instances if i["id"] not in gone]
        positions = {k: v for k, v in positions.items() if k not in gone}
    else:
        sys.exit("usage: place.py install|uninstall SETTINGS SESSION [both|left|right]")
    session["desktopWidgetInstancePositions"] = positions
    save(session_path, session)
    settings["desktopWidgetInstances"] = instances
    save(settings_path, settings)


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5):
        sys.exit("usage: place.py install|uninstall SETTINGS SESSION [both|left|right]")
    main(*sys.argv[1:])
