ANTIAFK_LAST=0

_has_cmd() { command -v "$1" &>/dev/null; }

# Returns X11 window ID (decimal) for the Sober window, or empty string.
# Requires Sober to be running with X11 enabled (set in Flatseal).
get_window_id() {
    [ -n "$DISPLAY" ] || return 1
    _has_cmd xdotool || return 1

    local wid
    for pattern in \
        "--class sober.org.vinegarhq.Sober" \
        "--class Sober" \
        "--classname sober" \
        "--name Roblox"; do
        wid=$(xdotool search $pattern 2>/dev/null | head -1)
        [ -n "$wid" ] && { echo "$wid"; return 0; }
    done

    return 1
}

antiafk_tick() {
    [[ "$ANTIAFK_ENABLED" == "true" ]] || return
    local now; now=$(date +%s)
    (( now - ANTIAFK_LAST < ANTIAFK_INTERVAL )) && return

    ANTIAFK_LAST=$now
    local ts; ts="[$(date '+%H:%M:%S')] [AntiAFK]"

    local wid; wid=$(get_window_id)

    if [ -z "$wid" ]; then
        echo "$ts Sober not found (enable X11 in Flatseal for Sober)"
        return
    fi

    # Send key directly to the window — no focus change needed.
    local prev; prev=$(xdotool getactivewindow 2>/dev/null)
    xdotool windowactivate --sync "$wid" 2>/dev/null
    xdotool key --window "$wid" --clearmodifiers --delay 100 space
    [ -n "$prev" ] && [ "$prev" != "$wid" ] && xdotool windowactivate "$prev" 2>/dev/null

    echo "$ts AntiAFK: jump sent"
}
