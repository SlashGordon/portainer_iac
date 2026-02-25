#!/bin/sh
#
# FritzBox DynDNS Webhook Handler for Alpine Linux (Busybox)
# Triggered by FritzBox on IP change - updates Cloudflare Zero Trust policy directly via API
#
# Required environment variables:
#   CF_AUTH_TOKEN, CF_ACCOUNT_ID, CF_POLICY_ID

LOG_FILE="/var/log/dyndns-update.log"
MAX_RETRIES=5
RETRY_DELAY_SECONDS=2
SECRETS_DIR="/run/secrets"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log() {
    msg="$1"
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    line="[$timestamp] $msg"
    # Print to stderr (>&2) so command substitutions $(...) don't capture logs
    echo "$line" >&2
    # Append to log file, fail silently if no permission
    echo "$line" >> "$LOG_FILE" 2>/dev/null || true
}

read_secret_file() {
    # Reads a secret file and strips trailing newlines.
    file_path="$1"
    if [ -n "$file_path" ] && [ -f "$file_path" ] && [ -r "$file_path" ]; then
        # Busybox-compatible newline stripping
        tr -d '\r\n' < "$file_path"
        return 0
    fi
    return 1
}

load_secret_into_var() {
    # If the target variable is empty, try to load it from:
    # 1) an explicit *_FILE env var, or
    # 2) /run/secrets/<default_secret_name>
    var_name="$1"
    default_secret_name="$2"

    eval current_val="\${$var_name}"
    if [ -n "$current_val" ]; then
        return 0
    fi

    file_var_name="${var_name}_FILE"
    eval explicit_file_path="\${$file_var_name}"
    if secret_val=$(read_secret_file "$explicit_file_path"); then
        export "$var_name=$secret_val"
        return 0
    fi

    if secret_val=$(read_secret_file "${SECRETS_DIR}/${default_secret_name}"); then
        export "$var_name=$secret_val"
        return 0
    fi

    return 1
}

fetch_ipv4_once() {
    wget -qO- -T 5 https://api.ipify.org || \
    wget -qO- -T 5 https://api4.my-ip.io/ip || \
    wget -qO- -T 5 https://v4.ident.me || echo ""
}

fetch_ipv6_once() {
    wget -qO- -T 5 https://api6.ipify.org || \
    wget -qO- -T 5 https://api6.my-ip.io/ip || \
    wget -qO- -T 5 https://v6.ident.me || echo ""
}

fetch_with_retry() {
    ip_version="$1"
    delay=$RETRY_DELAY_SECONDS
    attempt=1

    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        if [ "$ip_version" = "IPv4" ]; then
            result=$(fetch_ipv4_once)
        else
            result=$(fetch_ipv6_once)
        fi
        
        if [ -n "$result" ]; then
            echo "$result"
            return 0
        fi
        
        if [ "$attempt" -lt "$MAX_RETRIES" ]; then
            log "Failed to fetch $ip_version, retrying in ${delay}s (${attempt}/${MAX_RETRIES})..."
            sleep "$delay"
            delay=$((delay * 2)) # Exponential backoff
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

get_ipv6_network() {
    ipv6="$1"
    if [ -z "$ipv6" ]; then
        echo ""
        return
    fi
    # Extracts the first 4 blocks of the IPv6 address and appends ::/64
    echo "$ipv6" | cut -d: -f1-4 | sed 's/$/::\/64/'
}

get_static_curl() {
    CURL_BIN="/tmp/curl"
    if [ ! -x "$CURL_BIN" ]; then
        arch=$(uname -m)
        if [ "$arch" = "x86_64" ]; then
            curl_url="https://github.com/moparisthebest/static-curl/releases/latest/download/curl-amd64"
        elif [ "$arch" = "aarch64" ]; then
            curl_url="https://github.com/moparisthebest/static-curl/releases/latest/download/curl-aarch64"
        else
            log "ERROR: Unsupported architecture ($arch) for static curl."
            exit 1
        fi
        
        log "Bootstrapping static curl ($arch) to handle PUT request..."
        wget -qO "$CURL_BIN" "$curl_url"
        chmod +x "$CURL_BIN"
    fi
    # Only echo the binary path so CURL_EXEC captures it cleanly
    echo "$CURL_BIN"
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

main() {
    log "FritzBox DynDNS webhook triggered"

    # Load required environment variables (supports Docker secrets via /run/secrets/*)
    load_secret_into_var "CF_AUTH_TOKEN" "cf_auth_token" || true
    load_secret_into_var "CF_ACCOUNT_ID" "cf_account_id" || true
    load_secret_into_var "CF_POLICY_ID" "cf_policy_id" || true

    # Validate required environment variables
    if [ -z "$CF_AUTH_TOKEN" ] || [ -z "$CF_ACCOUNT_ID" ] || [ -z "$CF_POLICY_ID" ]; then
        log "ERROR: CF_AUTH_TOKEN, CF_ACCOUNT_ID, and CF_POLICY_ID must be set (env or Docker secrets)"
        exit 1
    fi

    # Fetch public IPs
    log "Fetching public IP addresses..."
    ipv4=$(fetch_with_retry "IPv4")
    ipv6=$(fetch_with_retry "IPv6")
    
    log "Fetched IPv4: $ipv4, IPv6: $ipv6"

    if [ -z "$ipv4" ]; then
        log "ERROR: Could not fetch public IPv4 address"
        exit 1
    fi

    # Calculate IPv6 /64 network
    ipv6_network=$(get_ipv6_network "$ipv6")
    if [ -n "$ipv6_network" ]; then
        log "Calculated IPv6 network: $ipv6_network"
    fi

    api_base="https://api.cloudflare.com/client/v4"
    policy_url="${api_base}/accounts/${CF_ACCOUNT_ID}/access/policies/${CF_POLICY_ID}"

    # Fetch existing policy
    log "Fetching existing policy..."
    get_response=$(wget -qO- \
        --header="Authorization: Bearer $CF_AUTH_TOKEN" \
        --header="Content-Type: application/json" \
        "$policy_url")

    # Verify response success manually without jq
    if ! echo "$get_response" | grep -q '"success":true' && ! echo "$get_response" | grep -q '"success": true'; then
        log "ERROR: Failed to fetch existing policy or policy not found."
        exit 1
    fi

    # Extract name, decision, and precedence using grep/awk string extraction
    policy_name=$(echo "$get_response" | grep -o '"name":"[^"]*"' | head -n 1 | awk -F'"' '{print $4}')
    policy_decision=$(echo "$get_response" | grep -o '"decision":"[^"]*"' | head -n 1 | awk -F'"' '{print $4}')
    policy_precedence=$(echo "$get_response" | grep -o '"precedence":[0-9]*' | head -n 1 | awk -F':' '{print $2}')

    # Apply defaults if extraction failed
    [ -z "$policy_name" ] && policy_name="DynDNS Whitelist"
    [ -z "$policy_decision" ] && policy_decision="non_identity"
    [ -z "$policy_precedence" ] && policy_precedence=0

    log "Current policy: name=$policy_name, decision=$policy_decision"

    # Build new include rules array as a string
    if [ -n "$ipv6_network" ]; then
        include_rules="[{\"ip\": {\"ip\": \"$ipv4\"}}, {\"ip\": {\"ip\": \"$ipv6_network\"}}]"
    else
        include_rules="[{\"ip\": {\"ip\": \"$ipv4\"}}]"
    fi

    # Build full JSON update payload 
    # (Note: Assumes 'exclude' and 'require' are empty for standard IP whitelist policies)
    update_payload="{\"name\": \"$policy_name\", \"decision\": \"$policy_decision\", \"precedence\": $policy_precedence, \"include\": $include_rules, \"exclude\": [], \"require\": []}"

    log "Updating policy with new IPs..."
    
    # Send PUT request using dynamically downloaded static curl
    CURL_EXEC=$(get_static_curl)
    
    put_response=$("$CURL_EXEC" -s -X PUT "$policy_url" \
        -H "Authorization: Bearer $CF_AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$update_payload")

    if echo "$put_response" | grep -q '"success":true' || echo "$put_response" | grep -q '"success": true'; then
        log "Zero Trust policy updated successfully"
    else
        log "ERROR: Zero Trust policy update failed. Dump: $put_response"
        exit 1
    fi

    log "DynDNS update completed"
}

main "$@"