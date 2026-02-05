#!/bin/sh
# FritzBox DynDNS Webhook Handler
# Triggered by FritzBox on IP change - updates Cloudflare security rules via nas-manager
# nas-manager fetches current public IPs externally
#
# Required environment variables:
#   CF_AUTH_TOKEN, ZONE_ID, RULESET_ID, RULE_ID_PATCH, RULE_ID_MULTI,
#   EXPRESSION_PATCH_B64, EXPRESSION_MULTI_B64, DESCRIPTION_PATCH, DESCRIPTION_MULTI

LOG_FILE="/var/log/dyndns-update.log"
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "FritzBox DynDNS webhook triggered"

# IP addresses from FritzBox webhook URL parameters
IPV4="${ip:-}"
IPV6="${ip6:-}"
IPV6_PREFIX="${prefix:-}"
DUALSTACK="${dual:-}"
log "Received IPv4: $IPV4, IPv6: $IPV6, Prefix: $IPV6_PREFIX, Dualstack: $DUALSTACK"

# Update Cloudflare security rules using nas-manager
if [ -z "$CF_AUTH_TOKEN" ] || [ -z "$ZONE_ID" ]; then
    log "ERROR: CF_AUTH_TOKEN or ZONE_ID not set"
    exit 1
fi

export CF_API_TOKEN="${CF_AUTH_TOKEN}"

# Update PATCH rule
if [ -n "$RULE_ID_PATCH" ] && [ -n "$RULESET_ID" ]; then
    EXPRESSION=$(printf '%s' "$EXPRESSION_PATCH_B64" | base64 -d)
    log "Updating PATCH rule: $DESCRIPTION_PATCH"
    nas-manager security cloudflare \
        --zone-id="$ZONE_ID" \
        --ruleset-id="$RULESET_ID" \
        --rule-id="$RULE_ID_PATCH" \
        --action=block \
        --description="$DESCRIPTION_PATCH" \
        --enabled=true \
        --skip-unchanged=false \
        --expression="$EXPRESSION" && log "PATCH rule updated" || log "ERROR: PATCH rule failed"
fi

# Update MULTI rule
if [ -n "$RULE_ID_MULTI" ] && [ -n "$RULESET_ID" ]; then
    EXPRESSION=$(printf '%s' "$EXPRESSION_MULTI_B64" | base64 -d)
    log "Updating MULTI rule: $DESCRIPTION_MULTI"
    nas-manager security cloudflare \
        --zone-id="$ZONE_ID" \
        --ruleset-id="$RULESET_ID" \
        --rule-id="$RULE_ID_MULTI" \
        --action=block \
        --description="$DESCRIPTION_MULTI" \
        --enabled=true \
        --skip-unchanged=false \
        --expression="$EXPRESSION" && log "MULTI rule updated" || log "ERROR: MULTI rule failed"
fi

log "DynDNS update completed"
exit 0
