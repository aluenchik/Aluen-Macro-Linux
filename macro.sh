#!/usr/bin/env bash
# ================================================================
#   Dependencies: curl, xdotool (for AntiAFK)
# ================================================================

# ┌─────────────────────────────────────────┐
# │             MACRO VERSION               │
# └─────────────────────────────────────────┘
VERSION="1.0"

# ┌─────────────────────────────────────────┐
# │           MODULE PATH SETUP             │
# └─────────────────────────────────────────┘

# Resolve the real script location (follow symlinks)
if [ -L "${BASH_SOURCE[0]}" ]; then
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
else
    SCRIPT_PATH="${BASH_SOURCE[0]}"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"

# Create modules directory if it doesn't exist
mkdir -p "$MODULES_DIR"

# ┌─────────────────────────────────────────┐
# │            LOAD MODULES                 │
# └─────────────────────────────────────────┘

# Check that a module file exists
check_module() {
    local module="$1"
    if [ ! -f "${MODULES_DIR}/${module}" ]; then
        echo "[ERROR] Module not found: ${module}"
        echo "Make sure all files from the modules directory are in: ${MODULES_DIR}"
        exit 1
    fi
}

# Load all required modules
check_module "settings.sh"
check_module "discord.sh"
check_module "menu.sh"
check_module "biome_parser.sh"
check_module "antiafk.sh"
check_module "monitor.sh"

source "${MODULES_DIR}/settings.sh"
source "${MODULES_DIR}/discord.sh"
source "${MODULES_DIR}/menu.sh"
source "${MODULES_DIR}/biome_parser.sh"
source "${MODULES_DIR}/antiafk.sh"
source "${MODULES_DIR}/monitor.sh"

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

    # Strip leading 'v' for comparison
    local latest_clean="${latest#v}"

    if [ "$latest_clean" != "$VERSION" ]; then
        echo "╔══════════════════════════════════════════╗"
        echo "║           UPDATE AVAILABLE               ║"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        echo "  Current version : v${VERSION}"
        echo "  Latest version  : ${latest}"
        echo ""
        echo "  https://github.com/aluenchik/Aluen-Macro-Linux"
        echo ""
        read -p "Press Enter to continue..."
    fi
}

# ┌─────────────────────────────────────────┐
# │              ENTRY POINT                │
# └─────────────────────────────────────────┘

main() {
    load_config
    check_for_updates
    show_main_menu
}

main