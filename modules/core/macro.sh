#!/usr/bin/env bash

# ┌─────────────────────────────────────────┐
# │             MACRO VERSION               │
# └─────────────────────────────────────────┘
VERSION="1.2.1"

# ┌─────────────────────────────────────────┐
# │           MODULE PATH SETUP             │
# └─────────────────────────────────────────┘

# Resolve the real script location (follow symlinks)
if [ -L "${BASH_SOURCE[0]}" ]; then
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
else
    SCRIPT_PATH="${BASH_SOURCE[0]}"
fi
# Core lives in modules/core/ — project root is two levels up
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../.." && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"
CORE_DIR="${MODULES_DIR}/core"
MERCHANT_DIR="${MODULES_DIR}/merchant"

mkdir -p "$CORE_DIR" "$MERCHANT_DIR"

# ┌─────────────────────────────────────────┐
# │            LOAD MODULES                 │
# └─────────────────────────────────────────┘

check_core() {
    local f="${CORE_DIR}/${1}"
    if [ ! -f "$f" ]; then
        echo "[ERROR] Core module not found: modules/core/${1}"
        exit 1
    fi
}

check_merchant() {
    local f="${MERCHANT_DIR}/${1}"
    if [ ! -f "$f" ]; then
        echo "[ERROR] Merchant module not found: modules/merchant/${1}"
        exit 1
    fi
}

# Core (always loaded)
check_core "settings.sh"
check_core "discord.sh"
check_core "biome_parser.sh"
check_core "antiafk.sh"
check_core "monitor.sh"

source "${CORE_DIR}/settings.sh"
source "${CORE_DIR}/discord.sh"
source "${CORE_DIR}/biome_parser.sh"
source "${CORE_DIR}/antiafk.sh"
source "${CORE_DIR}/monitor.sh"

# Merchant module
check_merchant "merchant.sh"
source "${MERCHANT_DIR}/merchant.sh"

# Items module (Strange Controller, Biome Randomizer)
ITEMS_MODULE="${MODULES_DIR}/items.sh"
if [ ! -f "$ITEMS_MODULE" ]; then
    echo "[ERROR] Module not found: modules/items.sh"
    exit 1
fi
source "$ITEMS_MODULE"

# ┌─────────────────────────────────────────┐
# │            UPDATE CHECK                 │
# └─────────────────────────────────────────┘

check_for_updates() {
    command -v curl &>/dev/null || return

    local api_url="https://api.github.com/repos/aluenchik/Aluen-Macro-Linux/releases/latest"
    local response
    response=$(curl -s --max-time 5 "$api_url" 2>/dev/null)
    [ -z "$response" ] && return

    local latest
    latest=$(printf '%s' "$response" | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
    [ -z "$latest" ] && return

    local latest_clean="${latest#v}"

    if [ "$latest_clean" != "$VERSION" ]; then
        echo "UPDATE AVAILABLE: v${VERSION} → ${latest}"
        echo "https://github.com/aluenchik/Aluen-Macro-Linux"
    fi
}

# ┌─────────────────────────────────────────┐
# │              ENTRY POINT                │
# └─────────────────────────────────────────┘

main() {
    load_config
    if [[ "${1:-}" == "--monitor" ]]; then
        start_monitoring
        return
    fi
    check_for_updates
    echo "Use gui.py to configure and start monitoring."
    echo "Or run: bash macro.sh --monitor"
}

main "$@"
