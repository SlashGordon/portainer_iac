#!/bin/sh
# DynDNS Update Script for FritzBox
# Called by adnanh/webhook when FritzBox sends an IP update
# Uses nas-manager for Cloudflare DNS updates
#
# Arguments (from webhook):
#   $1 - IPv4 address (ipaddr)
#   $2 - IPv6 address (ip6addr)
#   $3 - Domain name (domain)
#   $4 - Username (username)
#   $5 - Password (pass)
#   $6 - IPv6 LAN prefix (ip6lanprefix)
#   $7 - Dualstack flag (dualstack)
#
# Environment variables are also set:
#   DYNDNS_IPV4, DYNDNS_IPV6, DYNDNS_DOMAIN, DYNDNS_USERNAME,
#   DYNDNS_PASSWORD, DYNDNS_IP6LANPREFIX, DYNDNS_DUALSTACK
#
# Required environment variables for Cloudflare:
#   CF_API_TOKEN, CF_ZONE_ID, CF_RECORD_NAME

set -e

# Use environment variables (more reliable than positional args)
IPV4="${DYNDNS_IPV4:-$1}"
IPV6="${DYNDNS_IPV6:-$2}"
DOMAIN="${DYNDNS_DOMAIN:-$3}"
USERNAME="${DYNDNS_USERNAME:-$4}"
PASSWORD="${DYNDNS_PASSWORD:-$5}"
IP6LANPREFIX="${DYNDNS_IP6LANPREFIX:-$6}"
DUALSTACK="${DYNDNS_DUALSTACK:-$7}"

LOG_FILE="/var/log/dyndns-update.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo "$1"
}

# Validate required parameters
if [ -z "$DOMAIN" ]; then
    log "ERROR: Domain is required"
    exit 1
fi

if [ -z "$IPV4" ] && [ -z "$IPV6" ]; then
    log "ERROR: At least one IP address (IPv4 or IPv6) is required"
    exit 1
fi

log "DynDNS update received for domain: $DOMAIN"
[ -n "$IPV4" ] && log "  IPv4: $IPV4"
[ -n "$IPV6" ] && log "  IPv6: $IPV6"
[ -n "$IP6LANPREFIX" ] && log "  IPv6 LAN Prefix: $IP6LANPREFIX"
[ -n "$DUALSTACK" ] && log "  Dualstack: $DUALSTACK"
[ -n "$USERNAME" ] && log "  Username: $USERNAME"

# Store current IP addresses in files for reference
IP_STORE_DIR="/var/lib/dyndns"
mkdir -p "$IP_STORE_DIR"

DOMAIN_SAFE=$(echo "$DOMAIN" | tr '.' '_')

if [ -n "$IPV4" ]; then
    echo "$IPV4" > "$IP_STORE_DIR/${DOMAIN_SAFE}_ipv4"
    log "Stored IPv4 address for $DOMAIN"
fi

if [ -n "$IPV6" ]; then
    echo "$IPV6" > "$IP_STORE_DIR/${DOMAIN_SAFE}_ipv6"
    log "Stored IPv6 address for $DOMAIN"
fi

if [ -n "$IP6LANPREFIX" ]; then
    echo "$IP6LANPREFIX" > "$IP_STORE_DIR/${DOMAIN_SAFE}_ip6lanprefix"
    log "Stored IPv6 LAN prefix for $DOMAIN"
fi

# Optional: Execute custom update script if exists
CUSTOM_SCRIPT="/scripts/dyndns-custom.sh"
if [ -x "$CUSTOM_SCRIPT" ]; then
    log "Executing custom update script..."
    export DYNDNS_IPV4 DYNDNS_IPV6 DYNDNS_DOMAIN DYNDNS_USERNAME
    export DYNDNS_PASSWORD DYNDNS_IP6LANPREFIX DYNDNS_DUALSTACK
    "$CUSTOM_SCRIPT"
fi

# Update Cloudflare security rules using nas-manager (if CF_AUTH_TOKEN is set)
if [ -n "$CF_AUTH_TOKEN" ] && [ -n "$ZONE_ID" ]; then
    log "Cloudflare integration enabled - updating security rules via nas-manager..."
    
    # Export as CF_API_TOKEN for nas-manager compatibility
    export CF_API_TOKEN="${CF_AUTH_TOKEN}"
    
    # Update Rule 1: PATCH rule (block all traffic but not ipv6 network)
    if [ -n "$RULE_ID_PATCH" ] && [ -n "$RULESET_ID" ]; then
        EXPRESSION_PATCH_DECODED=$(printf '%s' "$EXPRESSION_PATCH_B64" | base64 -d)
        log "Updating PATCH rule: $DESCRIPTION_PATCH"
        if nas-manager security cloudflare \
            --zone-id="$ZONE_ID" \
            --ruleset-id="$RULESET_ID" \
            --rule-id="$RULE_ID_PATCH" \
            --action=block \
            --description="$DESCRIPTION_PATCH" \
            --enabled=true \
            --expression="$EXPRESSION_PATCH_DECODED"; then
            log "Successfully updated PATCH rule"
        else
            log "ERROR: Failed to update PATCH rule"
        fi
    fi
    
    # Update Rule 2: MULTI rule (allow only my IPv6 network for specific hosts)
    if [ -n "$RULE_ID_MULTI" ] && [ -n "$RULESET_ID" ]; then
        EXPRESSION_MULTI_DECODED=$(printf '%s' "$EXPRESSION_MULTI_B64" | base64 -d)
        log "Updating MULTI rule: $DESCRIPTION_MULTI"
        if nas-manager security cloudflare \
            --zone-id="$ZONE_ID" \
            --ruleset-id="$RULESET_ID" \
            --rule-id="$RULE_ID_MULTI" \
            --action=block \
            --description="$DESCRIPTION_MULTI" \
            --enabled=true \
            --expression="$EXPRESSION_MULTI_DECODED"; then
            log "Successfully updated MULTI rule"
        else
            log "ERROR: Failed to update MULTI rule"
        fi
    fi
fi

log "DynDNS update completed successfully for $DOMAIN"
exit 0
