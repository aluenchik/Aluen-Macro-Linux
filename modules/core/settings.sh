# ================================================================
#   modules/config.sh - Configuration management
# ================================================================

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sols_rng/config.conf"
CONFIG_DIR="$(dirname "$CONFIG_FILE")"

# ┌─────────────────────────────────────────┐
# │         GLOBAL BIOME ARRAYS             │
# └─────────────────────────────────────────┘

declare -gA BIOME_COLORS=(
    ["WINDY"]="6006984"       # #5BA8C8 — soft sky blue
    ["SNOWY"]="10537192"      # #A0C8E8 — pale ice blue
    ["RAINY"]="3045560"       # #2E78B8 — medium storm blue
    ["SANDSTORM"]="13137952"  # #C87820 — sandy orange
    ["HELL"]="13375488"       # #CC1800 — bright crimson
    ["HEAVEN"]="15253536"     # #E8C020 — gold
    ["STARFALL"]="46292"      # #00B4D4 — teal/aqua
    ["CORRUPTION"]="7876776"  # #7830A8 — purple
    ["NULL"]="8421504"        # #808080 — gray
    ["GLITCHED"]="2152512"    # #20D840 — neon green
    ["DREAMSPACE"]="14700728" # #E050B8 — pink/magenta
    ["CYBERSPACE"]="51448"    # #00C8F8 — electric cyan
    ["EGGLAND"]="6860848"     # #68B030 — grass green
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

# ┌─────────────────────────────────────────┐
# │         MERCHANT MODULE                 │
# └─────────────────────────────────────────┘

MERCHANT_ENABLED=false
MERCHANT_INTERVAL=300

# Calibration points — defaults for 1920x1080, recalibrate if UI differs
MERCHANT_CAL_INV_X=35
MERCHANT_CAL_INV_Y=510
MERCHANT_CAL_ITEMS_TAB_X=1247
MERCHANT_CAL_ITEMS_TAB_Y=340
MERCHANT_CAL_SEARCH_X=960
MERCHANT_CAL_SEARCH_Y=368
MERCHANT_CAL_ITEM_X=846
MERCHANT_CAL_ITEM_Y=463
MERCHANT_CAL_USE_X=683
MERCHANT_CAL_USE_Y=574
MERCHANT_CAL_SHOP_X=589
MERCHANT_CAL_SHOP_Y=936
MERCHANT_CAL_DIALOG_X=773
MERCHANT_CAL_DIALOG_Y=849
MERCHANT_CAL_BUY_X=1041
MERCHANT_CAL_BUY_Y=648
MERCHANT_CAL_MAX_X=1300
MERCHANT_CAL_MAX_Y=614

# Items to auto-buy from Mari (match shop tab text, any case)
MARI_BUY_ITEMS=()

# Items from Mari to buy with max quantity
MARI_MAX_ITEMS=()

# Items to auto-buy from Jester (match shop tab text, any case)
JESTER_BUY_ITEMS=()

# Items from Jester to buy with max quantity
JESTER_MAX_ITEMS=()


# ┌─────────────────────────────────────────┐
# │       STRANGE CONTROLLER                │
# └─────────────────────────────────────────┘

STRANGE_CONTROLLER_ENABLED=false
STRANGE_CONTROLLER_INTERVAL=1200   # 20 minutes

# ┌─────────────────────────────────────────┐
# │         BIOME RANDOMIZER                │
# └─────────────────────────────────────────┘

BIOME_RANDOMIZER_ENABLED=false
BIOME_RANDOMIZER_INTERVAL=2100   # 35 minutes

# ┌─────────────────────────────────────────┐
# │          CUSTOM USE ITEMS               │
# └─────────────────────────────────────────┘

# Format: "Item Name|cooldown_seconds"
CUSTOM_USE_ITEMS=()
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

