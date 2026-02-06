#!/bin/sh
# FritzBox DynDNS Webhook Handler
# Triggered by FritzBox on IP change - updates Cloudflare Zero Trust policy via nas-manager
# nas-manager fetches current public IPs externally
#
# Required environment variables:
#   CF_AUTH_TOKEN, CF_ACCOUNT_ID, CF_POLICY_ID
#   NAS_MANAGER_PUBLIC_IP_PROVIDERS (optional, defaults to fritzbox-soap)

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

# Validate required environment variables
if [ -z "$CF_AUTH_TOKEN" ]; then
    log "ERROR: CF_AUTH_TOKEN not set"
    exit 1
fi

if [ -z "$CF_ACCOUNT_ID" ]; then
    log "ERROR: CF_ACCOUNT_ID not set"
    exit 1
fi

if [ -z "$CF_POLICY_ID" ]; then
    log "ERROR: CF_POLICY_ID not set"
    exit 1
fi

# Set defaults
NAS_MANAGER_PUBLIC_IP_PROVIDERS="${NAS_MANAGER_PUBLIC_IP_PROVIDERS:-fritzbox-soap}"

log "Updating Cloudflare Zero Trust policy..."

# Update Zero Trust policy with current IPs
nas-manager security cloudflare zerotrust-policy \
    --account-id="$CF_ACCOUNT_ID" \
    --policy-id="$CF_POLICY_ID" \
    --reusable \
    --include-ip="{{PUBLIC_IPV4}}" \
    --include-ip="{{PUBLIC_IPV6_NETWORK/64}}" \
    --decision=bypass \
    && log "Zero Trust policy updated successfully" \
    || { log "ERROR: Zero Trust policy update failed"; exit 1; }

log "DynDNS update completed"
exit 0
