#!/bin/sh
# One Finder search: search.sh ID QUERY FILE prints ID on the first line,
# then up to 150 matches from FILE, best first. The ID lets Islet drop the
# output of a search that a newer one replaced.
id=$1 query=$2 file=$3
printf '%s\n' "$id"
[ -f "$file" ] || exit 0
# Options from the user's shell (e.g. --exact) would change what matches.
unset FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE
# In the background, so that when a newer search stops this one (SIGTERM),
# fzf stops too instead of running on unseen.
fzf --filter "$query" < "$file" | head -n 150 &
trap 'pkill -P $$ 2>/dev/null; exit 0' TERM INT
wait
