# ================================================================
#   modules/discord.sh - Discord notifications
# ================================================================

# ┌─────────────────────────────────────────┐
# │          CONFIG VALIDATION              │
# └─────────────────────────────────────────┘

# JSON escaping function
escape_json_string() {
    local s="$1"
    # Escape backslashes, quotes, newlines, tabs, carriage returns
    s="${s//\\/\\\\}"      # \ → \\
    s="${s//\"/\\\"}"      # " → \"
    s="${s//$'\n'/\\n}"    # newline → \n
    s="${s//$'\t'/\\t}"    # tab → \t
    s="${s//$'\r'/\\r}"    # cr → \r
    printf '%s' "$s"
}

validate_webhook_url() {
    if [ -z "$WEBHOOK_URL" ] || [[ "$WEBHOOK_URL" == *"YOUR_WEBHOOK"* ]]; then
        return 1
    fi

    # Check that it's a Discord webhook
    if [[ ! "$WEBHOOK_URL" =~ discord|discordapp ]]; then
        return 1
    fi

    return 0
}

validate_server_invite() {
    if [ -z "$SERVER_INVITE" ] || [[ "$SERVER_INVITE" == *"YOUR_VIP_SERVER"* ]]; then
        return 1
    fi

    # Basic check that it's a URL
    if [[ ! "$SERVER_INVITE" =~ ^https?:// ]]; then
        return 1
    fi

    return 0
}

# ┌─────────────────────────────────────────┐
# │           EMBED FOOTER TEXT             │
# └─────────────────────────────────────────┘

get_footer_text() {
    echo "Aluen's Macro Linux v${VERSION}"
}

send_startup_notification() {
    local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local footer_text; footer_text=$(get_footer_text)

    local payload
    payload=$(cat <<EOF
{
  "embeds": [{
    "title": "Macro Status",
    "description": "# Macro started! \n\nJoin my Discord:\nhttps://discord.gg/nQFyFsRPaG",
    "color": 5763719,
    "footer": {
      "text": "${footer_text}"
    },
    "timestamp": "${timestamp}"
  }]
}
EOF
)

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$WEBHOOK_URL" 2>/dev/null)

    local curl_status=$?
    if [ $curl_status -ne 0 ]; then
        echo "[$(date '+%H:%M:%S')] Startup notification error: curl failed (exit code: $curl_status)"
    elif [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        echo "[$(date '+%H:%M:%S')] Startup notification sent to Discord"
    else
        echo "[$(date '+%H:%M:%S')] Startup notification error (HTTP $http_code)"
    fi
}

# ┌─────────────────────────────────────────┐
# │           SEND TO DISCORD               │
# └─────────────────────────────────────────┘

send_webhook() {
    local biome="$1"
    local event="$2"
    local color="${BIOME_COLORS[$biome]:-3447003}"
    local emoji="${BIOME_EMOJIS[$biome]:-🌍}"
    local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local footer_text; footer_text=$(get_footer_text)

    # Escape special characters for JSON
    local escaped_biome; escaped_biome=$(escape_json_string "$biome")
    local escaped_invite; escaped_invite=$(escape_json_string "$SERVER_INVITE")

    local ping_content=""
    if [ "$event" = "started" ]; then
        for b in "${PING_FOR[@]}"; do
            if [ "${biome^^}" = "$b" ]; then
                ping_content="@everyone"
                break
            fi
        done
    fi

    local title description
    if [ "$event" = "started" ]; then
        title=""
        description="# ${emoji} BIOME STARTED — ${escaped_biome}\n\n# [Join Server](${escaped_invite})\nJoin my Discord:\nhttps://discord.gg/nQFyFsRPaG"
    else
        title=""
        description="# ${emoji} BIOME ENDED — ${escaped_biome}\nJoin my Discord:\nhttps://discord.gg/nQFyFsRPaG"
        color="3158064"
    fi

    local payload
    payload=$(cat <<EOF
{
  "content": "${ping_content}",
  "embeds": [{
    "title": "${title}",
    "description": "${description}",
    "color": ${color},
    "footer": {
      "text": "${footer_text}"
    },
    "timestamp": "${timestamp}"
  }]
}
EOF
)
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$WEBHOOK_URL" 2>/dev/null)

    local curl_status=$?
    if [ $curl_status -ne 0 ]; then
        echo "[$(date '+%H:%M:%S')] Webhook error: curl failed (exit code: $curl_status)"
    elif [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        echo "[$(date '+%H:%M:%S')] Webhook OK — ${event}: $biome"
    else
        echo "[$(date '+%H:%M:%S')] Webhook error HTTP $http_code — $biome"
    fi
}

# ┌─────────────────────────────────────────┐
# │         STOP NOTIFICATION               │
# └─────────────────────────────────────────┘

send_stop_notification() {
    local session_duration="$1"  # in seconds

    # Check webhook before sending
    if ! validate_webhook_url; then
        echo "[$(date '+%H:%M:%S')] [!] Webhook not configured, skipping stop notification"
        return
    fi

    # Convert session duration to HH:MM:SS
    local hours=$((session_duration / 3600))
    local minutes=$(((session_duration % 3600) / 60))
    local seconds=$((session_duration % 60))
    local duration_formatted=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)

    local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local footer_text; footer_text=$(get_footer_text)

    local escaped_invite; escaped_invite=$(escape_json_string "$SERVER_INVITE")

    local payload
    payload=$(cat <<EOF
{
  "embeds": [{
    "title": "Macro Status",
    "description": "# Macro stopped!\n\n# [Join Server](${escaped_invite})\nJoin my Discord:\nhttps://discord.gg/nQFyFsRPaG",
    "color": 15158332,
    "fields": [
      {
        "name": "Session Times",
        "value": "**in this session:** $duration_formatted",
        "inline": false
      }
    ],
    "footer": {
      "text": "${footer_text}"
    },
    "timestamp": "${timestamp}"
  }]
}
EOF
)
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$WEBHOOK_URL" 2>/dev/null)

    local curl_status=$?
    if [ $curl_status -ne 0 ]; then
        echo "[$(date '+%H:%M:%S')] Stop notification error: curl failed (exit code: $curl_status)"
    elif [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        echo "[$(date '+%H:%M:%S')] Stop notification sent to Discord"
    else
        echo "[$(date '+%H:%M:%S')] Stop notification error (HTTP $http_code)"
    fi
}
