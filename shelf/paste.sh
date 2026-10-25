#!/bin/sh
# paste.sh DIR — what's on the clipboard, as files for the shelf, one path
# a line: copied files as they are; a picture or text saved into DIR first.
# Exits 1 when there's nothing to paste.
dir=$1
types=$(wl-paste --list-types 2>/dev/null) || exit 1
has() { printf '%s\n' "$types" | grep -qx "$1"; }

# file:// URIs (one a line, # comments skipped) → decoded paths.
uris() {
    tr -d '\r' | LC_ALL=C awk '
        BEGIN { for (i = 0; i < 256; i++) hex[sprintf("%02x", i)] = sprintf("%c", i) }
        /^file:\/\// {
            s = substr($0, 8); sub(/^[^\/]*/, "", s); out = ""
            while ((i = index(s, "%")) > 0) {
                out = out substr(s, 1, i - 1); h = tolower(substr(s, i + 1, 2))
                if (h in hex) { out = out hex[h]; s = substr(s, i + 3) } else { out = out "%"; s = substr(s, i + 1) }
            }
            print out s
        }'
}

# DIR/NAME.EXT, or NAME (2).EXT… when that's taken.
fresh() {
    p="$dir/$1.$2" n=2
    while [ -e "$p" ]; do p="$dir/$1 ($n).$2" n=$((n + 1)); done
    printf '%s\n' "$p"
}

out() { [ -n "$1" ] && printf '%s\n' "$1" && exit 0; exit 1; }

if has text/uri-list; then
    out "$(wl-paste -n -t text/uri-list | uris)"
fi
if has x-special/gnome-copied-files; then
    out "$(wl-paste -n -t x-special/gnome-copied-files | uris)"
fi

image=$(printf '%s\n' "$types" | grep -m1 '^image/')
if [ -n "$image" ]; then
    ext=${image#image/} ext=${ext%%+*}
    [ "$ext" = jpeg ] && ext=jpg
    mkdir -p "$dir"
    p=$(fresh "Tempelan $(date '+%Y-%m-%d %H.%M.%S')" "$ext")
    wl-paste -n -t "$image" > "$p" && [ -s "$p" ] && out "$p"
    rm -f "$p"
    exit 1
fi

for t in 'text/plain;charset=utf-8' text/plain UTF8_STRING TEXT STRING; do
    has "$t" || continue
    text=$(wl-paste -n -t "$t") || continue
    [ -n "$text" ] || exit 1
    # Paths (or file:// URIs) to things that exist: those things.
    paths=$(printf '%s\n' "$text" | awk 'NF' | while IFS= read -r l; do
        case $l in file://*) l=$(printf '%s\n' "$l" | uris) ;; esac
        case $l in /*) [ -e "$l" ] && printf '%s\n' "$l" || echo "-" ;; *) echo "-" ;; esac
    done)
    if [ -n "$paths" ] && ! printf '%s\n' "$paths" | grep -qx -- -; then
        out "$paths"
    fi
    # Anything else: a text file named after its first words.
    name=$(printf '%s\n' "$text" | awk 'NF { print; exit }' | tr -d '/\\:*?"<>|' | tr -s ' \t' '  ' |
        awk '{ s = ""; for (i = 1; i <= NF && i <= 6; i++) s = s (i > 1 ? " " : "") $i; print substr(s, 1, 40) }')
    [ -n "$name" ] || name="Teks $(date '+%Y-%m-%d %H.%M.%S')"
    mkdir -p "$dir"
    p=$(fresh "$name" txt)
    printf '%s' "$text" > "$p" && out "$p"
    exit 1
done
exit 1
