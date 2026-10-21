#!/bin/sh
# Shelf helper.
#   locate.sh info PATH...                 → PATH<TAB>inode<TAB>1 if a folder, else 0
#   locate.sh find ROOT [PATH INODE]...    → for each PATH that is gone: PATH<TAB>where it is now
#                                            (empty if not found)
# A file moved on the same disk keeps its inode, even renamed; without one,
# a single file of the same name counts. Hidden folders (the trash) aren't
# searched.
set -f
mode=$1
shift
case $mode in
info)
    for p; do
        d=0
        [ -d "$p" ] && d=1
        printf '%s\t%s\t%s\n' "$p" "$(stat -c %i -- "$p" 2>/dev/null)" "$d"
    done ;;
find)
    root=$1
    shift
    while [ $# -ge 2 ]; do
        p=$1 ino=$2
        shift 2
        [ -e "$p" ] && continue
        new=
        [ -n "$ino" ] && new=$(find "$root" -xdev -mindepth 1 -name '.*' -prune -o -inum "$ino" -print -quit 2>/dev/null)
        if [ -z "$new" ]; then
            # The name, literally (no glob).
            name=$(printf '%s' "${p##*/}" | sed 's/[][*?\\]/\\&/g')
            m=$(find "$root" -xdev -mindepth 1 -name '.*' -prune -o -name "$name" -print 2>/dev/null | head -n 2)
            [ -n "$m" ] && [ "$(printf '%s\n' "$m" | wc -l)" -eq 1 ] && new=$m
        fi
        printf '%s\t%s\n' "$p" "$new"
    done ;;
esac
