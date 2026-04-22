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
    echo "Aluen's Macro v${VERSION}"
}

_send_with_logo() {
    local payload="$1"
    local log_label="$2"
    local logo_icon="${CORE_DIR}/logo.png"

    local http_code
    if [ -f "$logo_icon" ]; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            -F "payload_json=${payload}" \
            -F "files[0]=@${logo_icon};filename=logo.png" \
            "$WEBHOOK_URL" 2>/dev/null)
    else
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$WEBHOOK_URL" 2>/dev/null)
    fi

    local curl_status=$?
    if [ $curl_status -ne 0 ]; then
        echo "[$(date '+%H:%M:%S')] ${log_label} error: curl failed (exit code: $curl_status)"
    elif [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        echo "[$(date '+%H:%M:%S')] ${log_label} sent to Discord"
    else
        echo "[$(date '+%H:%M:%S')] ${log_label} error (HTTP $http_code)"
    fi
}

send_startup_notification() {
    local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local footer_text; footer_text=$(get_footer_text)

    local payload
    payload=$(cat <<EOF
{
  "embeds": [{
    "title": "Macro Status",
    "description": "# Macro started! \n\nJoin our Discord:\nhttps://discord.gg/nQFyFsRPaG",
    "color": 5763719,
    "thumbnail": {"url": "attachment://logo.png"},
    "footer": {
      "text": "${footer_text}"
    },
    "timestamp": "${timestamp}"
  }]
}
EOF
)
    _send_with_logo "$payload" "Startup notification"
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
        description="# BIOME STARTED — ${escaped_biome}\n\n# [Join Server](${escaped_invite})\nJoin our Discord:\nhttps://discord.gg/nQFyFsRPaG"
    else
        title=""
        description="# BIOME ENDED — ${escaped_biome}\nJoin our Discord:\nhttps://discord.gg/nQFyFsRPaG"
        color="3158064"
    fi

    # Resolve icon paths
    local biome_lower; biome_lower=$(echo "$biome" | tr '[:upper:]' '[:lower:]')
    local biome_icon="${CORE_DIR}/biomes/${biome_lower}.png"
    local logo_icon="${CORE_DIR}/logo.png"

    local thumbnail_json="" footer_icon_json=""
    local has_biome_icon=false has_logo=false
    [ -f "$biome_icon" ] && has_biome_icon=true
    [ -f "$logo_icon"  ] && has_logo=true

    if $has_biome_icon; then
        thumbnail_json='"thumbnail": {"url": "attachment://biome.png"},'
    fi
    if $has_logo; then
        footer_icon_json='"icon_url": "attachment://logo.png",'
    fi

    local payload
    payload=$(cat <<EOF
{
  "content": "${ping_content}",
  "embeds": [{
    "title": "${title}",
    "description": "${description}",
    "color": ${color},
    ${thumbnail_json}
    "footer": {
      ${footer_icon_json}
      "text": "${footer_text}"
    },
    "timestamp": "${timestamp}"
  }]
}
EOF
)

    local http_code curl_status
    if $has_biome_icon || $has_logo; then
        # Send with file attachments (multipart)
        local curl_args=(-s -o /dev/null -w "%{http_code}" -X POST)
        curl_args+=(-F "payload_json=${payload}")
        $has_biome_icon && curl_args+=(-F "files[0]=@${biome_icon};filename=biome.png")
        $has_logo        && curl_args+=(-F "files[1]=@${logo_icon};filename=logo.png")
        http_code=$(curl "${curl_args[@]}" "$WEBHOOK_URL" 2>/dev/null)
    else
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$WEBHOOK_URL" 2>/dev/null)
    fi

    curl_status=$?
    if [ $curl_status -ne 0 ]; then
        echo "[$(date '+%H:%M:%S')] Webhook error: curl failed (exit code: $curl_status)"
    elif [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        echo "[$(date '+%H:%M:%S')] Webhook OK — ${event}: $biome"
    else
        echo "[$(date '+%H:%M:%S')] Webhook error HTTP $http_code — $biome"
    fi
}

# ┌─────────────────────────────────────────┐
# │        MERCHANT NOTIFICATION            │
# └─────────────────────────────────────────┘

send_merchant_notification() {
    local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local footer_text; footer_text=$(get_footer_text)

    local payload
    payload=$(cat <<EOF
{
  "embeds": [{
    "title": "🏪 ${DETECTED_MERCHANT_NAME} Detected!",
    "color": 16766720,
    "footer": {"text": "${footer_text}"},
    "timestamp": "${timestamp}"
  }],
  "components": [{
    "type": 1,
    "components": [
      {"type": 2, "style": 5, "label": "Join Server", "url": "${SERVER_INVITE}"},
      {"type": 2, "style": 5, "label": "Discord", "url": "https://discord.gg/nQFyFsRPaG"}
    ]
  }]
}
EOF
)

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$WEBHOOK_URL" 2>/dev/null)

    if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
        echo "[$(date '+%H:%M:%S')] [Merchant] Notify sent to Discord (HTTP $http_code)"
    else
        echo "[$(date '+%H:%M:%S')] [Merchant] Discord error (HTTP $http_code)"
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
    "description": "# Macro stopped!\n\nJoin our Discord:\nhttps://discord.gg/nQFyFsRPaG",
    "color": 15158332,
    "thumbnail": {"url": "attachment://logo.png"},
    "fields": [
      {
        "name": "Session Time",
        "value": "**$duration_formatted**",
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
    _send_with_logo "$payload" "Stop notification"
}
