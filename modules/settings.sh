# ================================================================
#   modules/config.sh - Configuration management
# ================================================================

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sols_rng/config.conf"
CONFIG_DIR="$(dirname "$CONFIG_FILE")"

# ┌─────────────────────────────────────────┐
# │         GLOBAL BIOME ARRAYS             │
# └─────────────────────────────────────────┘

declare -gA BIOME_COLORS=(
    ["WINDY"]="3447003"       ["SNOWY"]="11393254"
    ["RAINY"]="5592405"       ["SANDSTORM"]="15105570"
    ["HELL"]="15158332"       ["HEAVEN"]="16777215"
    ["STARFALL"]="2899536"    ["CORRUPTION"]="7340032"
    ["NULL"]="4605510"        ["GLITCHED"]="1752220"
    ["DREAMSPACE"]="15277667" ["CYBERSPACE"]="1146986"
    ["EGGLAND"]="16776960"
)

declare -gA BIOME_EMOJIS=(
    ["WINDY"]="🌬️"   ["SNOWY"]="❄️"    ["RAINY"]="🌧️"
    ["SANDSTORM"]="🏜️" ["HELL"]="🔥"   ["HEAVEN"]="✨"
    ["STARFALL"]="🌠"  ["CORRUPTION"]="☠️" ["NULL"]="🌑"
    ["GLITCHED"]="⚡"  ["DREAMSPACE"]="🌸" ["CYBERSPACE"]="🤖"
    ["EGGLAND"]="🥚"
)

# ┌─────────────────────────────────────────┐
# │         CREATE DEFAULT CONFIG           │
# └─────────────────────────────────────────┘

create_default_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<'EOF'
# ================================================================
#   Sol's RNG Configuration File
# ================================================================

# Discord Webhook URL
WEBHOOK_URL=""

# Roblox Server Invite Link
SERVER_INVITE=""

# Discord Role ID for pings (leave empty to disable)
PING_ROLE_ID=""

# ┌─────────────────────────────────────────┐
# │            ANTIAFK SETTINGS             │
# └─────────────────────────────────────────┘

ANTIAFK_ENABLED=true
ANTIAFK_INTERVAL=300   # seconds between keypresses (300 = 5 minutes)

# ┌─────────────────────────────────────────┐
# │       BIOMES TO NOTIFY ABOUT            │
# └─────────────────────────────────────────┘

# Leave empty () to notify about ALL biomes
NOTIFY_ONLY=(
    "SANDSTORM"
    "RAINY"
    "WINDY"
    "HELL"
    "HEAVEN"
    "NULL"
    "CORRUPTION"
    "GLITCHED"
    "STARFALL"
    "DREAMSPACE"
    "CYBERSPACE"
    "EGGLAND"
)

# Biomes that trigger role ping
PING_FOR=(
    "GLITCHED"
    "DREAMSPACE"
    "CYBERSPACE"
)
EOF
    echo "[+] Default config created: $CONFIG_FILE"
}

# ┌─────────────────────────────────────────┐
# │            LOAD CONFIG                  │
# └─────────────────────────────────────────┘

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        create_default_config
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
}

# ┌─────────────────────────────────────────┐
# │            SAVE CONFIG                  │
# └─────────────────────────────────────────┘

save_config_value() {
    local key="$1"
    local value="$2"

    local escaped_key
    local escaped_value
    escaped_key=$(printf '%s\n' "$key" | sed 's/[&/\[\\.^$*]/\\&/g')
    escaped_value=$(printf '%s\n' "$value" | sed 's/[&/\[\\.^$*]/\\&/g')

    if grep -q "^${escaped_key}=" "$CONFIG_FILE"; then
        sed -i "s|^${escaped_key}=.*|${escaped_key}=\"${escaped_value}\"|" "$CONFIG_FILE"
    else
        echo "${key}=\"${value}\"" >> "$CONFIG_FILE"
    fi
}

# ┌─────────────────────────────────────────┐
# │           EDIT SETTINGS                 │
# └─────────────────────────────────────────┘

edit_webhook_url() {
    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║          SET WEBHOOK URL                 ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "Current Webhook URL:"
    echo "$WEBHOOK_URL"
    echo ""
    read -p "Enter new Discord Webhook URL (Enter to keep current): " new_url

    if [ -n "$new_url" ]; then
        save_config_value "WEBHOOK_URL" "$new_url"
        echo ""
        echo "[✓] Webhook URL updated!"
    else
        echo ""
        echo "[i] Setting unchanged"
    fi
    echo ""
    read -p "Press Enter to continue..."
}

edit_server_invite() {
    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║          SET SERVER LINK                 ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "Current server link:"
    echo "$SERVER_INVITE"
    echo ""
    read -p "Enter new invite link (Enter to keep current): " new_invite

    if [ -n "$new_invite" ]; then
        save_config_value "SERVER_INVITE" "$new_invite"
        echo ""
        echo "[✓] Server link updated!"
    else
        echo ""
        echo "[i] Setting unchanged"
    fi
    echo ""
    read -p "Press Enter to continue..."
}


toggle_antiafk() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════╗"
        echo "║           ANTIAFK SETTINGS               ║"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        if $ANTIAFK_ENABLED; then
            echo "Current status: Enabled"
            echo "Interval: ${ANTIAFK_INTERVAL} seconds"
        else
            echo "Current status: Disabled"
        fi
        echo ""
        echo "1) Enable AntiAFK"
        echo "2) Disable AntiAFK"
        echo "3) Change interval (current: ${ANTIAFK_INTERVAL}s)"
        echo "4) Back"
        echo ""
        read -p "Select option [1-4]: " choice

        case $choice in
            1)
                save_config_value "ANTIAFK_ENABLED" "true"
                echo ""
                echo "[✓] AntiAFK enabled!"
                read -p "Press Enter to continue..."
                ;;
            2)
                save_config_value "ANTIAFK_ENABLED" "false"
                echo ""
                echo "[✓] AntiAFK disabled!"
                read -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                read -p "Enter interval in seconds (recommended: 300): " new_interval
                if [ -n "$new_interval" ] && [ "$new_interval" -gt 0 ] 2>/dev/null; then
                    save_config_value "ANTIAFK_INTERVAL" "$new_interval"
                    echo ""
                    echo "[✓] Interval changed to ${new_interval} seconds!"
                else
                    echo ""
                    echo "[!] Invalid value. Must be a positive number."
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                return
                ;;
            *)
                echo "Invalid choice."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

edit_config_manual() {
    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║          MANUAL CONFIG EDIT              ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "Config file: $CONFIG_FILE"
    echo ""

    if [ -n "$EDITOR" ]; then
        $EDITOR "$CONFIG_FILE"
    elif command -v nano &>/dev/null; then
        nano "$CONFIG_FILE"
    elif command -v vim &>/dev/null; then
        vim "$CONFIG_FILE"
    elif command -v vi &>/dev/null; then
        vi "$CONFIG_FILE"
    else
        echo "[!] No editor found."
        echo "Set the \$EDITOR variable or install nano/vim"
        echo ""
        read -p "Press Enter to continue..."
        return
    fi
}
