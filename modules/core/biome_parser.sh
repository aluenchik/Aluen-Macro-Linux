# ================================================================
#   modules/biome_parser.sh - Log parsing and biome detection
# ================================================================

# ┌─────────────────────────────────────────┐
# │            FIND SOBER LOG               │
# └─────────────────────────────────────────┘

find_latest_log() {
    local base="$HOME/.var/app/org.vinegarhq.Sober"
    # Only look for logs modified in the last 30 minutes
    # Optimized: single command instead of piping through xargs ls -t
    find "$base" -name "*.log" -type f -mmin -30 -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn \
        | head -1 \
        | cut -d' ' -f2-
}

# ┌─────────────────────────────────────────┐
# │           PARSE LOG LINE                │
# └─────────────────────────────────────────┘

parse_biome_from_line() {
    local line="$1"
    [[ "$line" == *'"command":"SetRichPresence"'* ]] || return
    local hover
    hover=$(printf '%s' "$line" | grep -oP '"largeImage"\s*:\s*\{\s*"hoverText"\s*:\s*"\K[^"]+')
    [ -z "$hover" ] && return
    printf '%s' "$hover"
}

# ┌─────────────────────────────────────────┐
# │           NORMALIZE BIOME               │
# └─────────────────────────────────────────┘

normalize_biome() {
    case "${1^^}" in
        "SAND STORM"|"SANDSTORM") echo "SANDSTORM" ;;
        "STAR FALL"|"STARFALL")   echo "STARFALL" ;;
        "DREAM SPACE"|"DREAMSPACE") echo "DREAMSPACE" ;;
        "CYBERSPACE"|"CYBER")     echo "CYBERSPACE" ;;
        *) echo "${1^^}" ;;
    esac
}

should_notify() {
    local biome="$1"
    [ ${#NOTIFY_ONLY[@]} -eq 0 ] && return 0
    for b in "${NOTIFY_ONLY[@]}"; do [ "$b" = "$biome" ] && return 0; done
    return 1
}
