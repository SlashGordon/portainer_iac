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

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log() {
    msg="$1"
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    line="[$timestamp] $msg"
    echo "$line"
    echo "$line" >> "$LOG_FILE" 2>/dev/null || true
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

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

main() {
    log "FritzBox DynDNS webhook triggered"

    # Validate required environment variables
    if [ -z "$CF_AUTH_TOKEN" ] || [ -z "$CF_ACCOUNT_ID" ] || [ -z "$CF_POLICY_ID" ]; then
        log "ERROR: CF_AUTH_TOKEN, CF_ACCOUNT_ID, and CF_POLICY_ID must be set"
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
    
    # Send PUT request using wget. Busybox wget uses POST with --post-data, 
    # so we use X-HTTP-Method-Override to force Cloudflare to process it as a PUT request.
    put_response=$(wget -qO- \
        --header="Authorization: Bearer $CF_AUTH_TOKEN" \
        --header="Content-Type: application/json" \
        --header="X-HTTP-Method-Override: PUT" \
        --post-data="$update_payload" \
        "$policy_url")

    if echo "$put_response" | grep -q '"success":true' || echo "$put_response" | grep -q '"success": true'; then
        log "Zero Trust policy updated successfully"
    else
        log "ERROR: Zero Trust policy update failed."
        exit 1
    fi

    log "DynDNS update completed"
}

main "$@"