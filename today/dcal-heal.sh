#!/bin/sh
# Upgrading dcal leaves the old daemon running from the deleted binary until
# something restarts it. Start the new one, hidden: `dcal restart` drops
# --hidden and opens the window. Its own unit: a child of islet.service would
# die whenever Islet restarts. Does nothing if the daemon is current.
for pid in $(pgrep -x dcal 2>/dev/null); do
    case "$(readlink "/proc/$pid/exe" 2>/dev/null)" in
        *" (deleted)")
            dcal kill >/dev/null 2>&1
            sleep 1
            exec systemd-run --user --collect --quiet -p ExitType=cgroup dcal run -d --hidden ;;
    esac
done
