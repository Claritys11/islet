"""place_cards.py install|uninstall SETTINGS — Islet's overview cards (Hari
ini, Focus, Checklist, Shelf) in DMS's dashboard: each in the first free
cells of the overview grid (DMS's 6 columns, below the cards already there),
and the overview tall enough to show them. Cards already placed keep their
place; uninstall takes only Islet's away. DMS rewrites settings.json while it
runs: call this with DMS stopped.
"""
import json, os, sys

COLUMNS = 6
# id, width, height (grid cells; rows are 96 px)
# Sized to fit four more rows on a 1080 px screen: Hari ini and Checklist
# side by side, then Focus and the Shelf as one-row strips.
CARDS = [
    ("plugin_isletToday", 4, 3),
    ("plugin_isletChecklist", 2, 3),
    ("plugin_isletFocus", 3, 1),
    ("plugin_isletShelf", 3, 1),
]
ISLET = {c[0] for c in CARDS}


def free_spot(taken, w, h):
    row = 0
    while True:
        for col in range(COLUMNS - w + 1):
            if all((r, c) not in taken for r in range(row, row + h) for c in range(col, col + w)):
                return col, row
        row += 1


def main(mode, path):
    with open(path) as f:
        data = json.load(f)
    cards = data.get("dashCards") or []
    if mode == "install":
        have = {c.get("id") for c in cards}
        taken = {(r, k) for c in cards for r in range(c["row"], c["row"] + c["h"]) for k in range(c["col"], c["col"] + c["w"])}
        for cid, w, h in CARDS:
            if cid in have:
                continue
            col, row = free_spot(taken, w, h)
            cards.append({"id": cid, "w": w, "h": h, "col": col, "row": row})
            taken |= {(r, k) for r in range(row, row + h) for k in range(col, col + w)}
        bottom = max((c["row"] + c["h"] for c in cards), default=0)
        overview = data.setdefault("dashOptions", {}).setdefault("overview", {})
        overview["panelRows"] = max(overview.get("panelRows", 0), bottom)
    elif mode == "uninstall":
        cards = [c for c in cards if c.get("id") not in ISLET]
    else:
        sys.exit("usage: place_cards.py install|uninstall SETTINGS")
    data["dashCards"] = cards
    tmp = path + ".islet-tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: place_cards.py install|uninstall SETTINGS")
    main(*sys.argv[1:])
