#!/usr/bin/env python3
"""
FritzBox DynDNS Webhook Handler
Triggered by FritzBox on IP change - updates Cloudflare Zero Trust policy directly via API

Required environment variables:
  CF_AUTH_TOKEN, CF_ACCOUNT_ID, CF_POLICY_ID
"""

import ipaddress
import json
import os
import sys
import time
import urllib.request
from datetime import datetime

LOG_FILE = "/var/log/dyndns-update.log"

# Retry configuration
MAX_RETRIES = 5
RETRY_DELAY_SECONDS = 2  # Initial delay, doubles each retry


def log(msg: str):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {msg}"
    print(line)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def fetch_ip(services: list[str]) -> str:
    """Fetch IP from first responding service."""
    for service in services:
        try:
            with urllib.request.urlopen(service, timeout=5) as resp:
                return resp.read().decode().strip()
        except Exception:
            continue
    return ""


def fetch_ipv4_once() -> str:
    return fetch_ip(
        [
            "https://api.ipify.org",
            "https://api4.my-ip.io/ip",
            "https://v4.ident.me",
        ]
    )


def fetch_ipv6_once() -> str:
    return fetch_ip(
        [
            "https://api6.ipify.org",
            "https://api6.my-ip.io/ip",
            "https://v6.ident.me",
        ]
    )


def fetch_with_retry(fetch_func, ip_version: str) -> str:
    """Fetch IP with exponential backoff retry."""
    delay = RETRY_DELAY_SECONDS
    for attempt in range(1, MAX_RETRIES + 1):
        result = fetch_func()
        if result:
            return result
        if attempt < MAX_RETRIES:
            log(
                f"Failed to fetch {ip_version}, retrying in {delay}s ({attempt}/{MAX_RETRIES})..."
            )
            time.sleep(delay)
            delay *= 2  # Exponential backoff
    return ""


def fetch_ipv4() -> str:
    return fetch_with_retry(fetch_ipv4_once, "IPv4")


def fetch_ipv6() -> str:
    return fetch_with_retry(fetch_ipv6_once, "IPv6")


def get_ipv6_network(ipv6: str) -> str:
    """Calculate /64 network prefix from IPv6 address."""
    if not ipv6:
        return ""
    try:
        return str(ipaddress.ip_network(f"{ipv6}/64", strict=False))
    except Exception:
        return ""


def cloudflare_request(method: str, url: str, token: str, data: dict = None) -> dict:
    """Make Cloudflare API request."""
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def main():
    log("FritzBox DynDNS webhook triggered")

    # Validate required environment variables
    cf_token = os.environ.get("CF_AUTH_TOKEN", "")
    cf_account_id = os.environ.get("CF_ACCOUNT_ID", "")
    cf_policy_id = os.environ.get("CF_POLICY_ID", "")

    if not cf_token:
        log("ERROR: CF_AUTH_TOKEN not set")
        sys.exit(1)
    if not cf_account_id:
        log("ERROR: CF_ACCOUNT_ID not set")
        sys.exit(1)
    if not cf_policy_id:
        log("ERROR: CF_POLICY_ID not set")
        sys.exit(1)

    # Fetch public IPs
    log("Fetching public IP addresses...")
    ipv4 = fetch_ipv4()
    ipv6 = fetch_ipv6()
    log(f"Fetched IPv4: {ipv4}, IPv6: {ipv6}")

    if not ipv4:
        log("ERROR: Could not fetch public IPv4 address")
        sys.exit(1)

    # Calculate IPv6 /64 network
    ipv6_network = get_ipv6_network(ipv6)
    if ipv6_network:
        log(f"Calculated IPv6 network: {ipv6_network}")

    log("Updating Cloudflare Zero Trust policy...")

    api_base = "https://api.cloudflare.com/client/v4"
    policy_url = f"{api_base}/accounts/{cf_account_id}/access/policies/{cf_policy_id}"

    # Fetch existing policy
    log("Fetching existing policy...")
    try:
        response = cloudflare_request("GET", policy_url, cf_token)
    except Exception as e:
        log(f"ERROR: Failed to fetch existing policy: {e}")
        sys.exit(1)

    if not response.get("success"):
        error_msg = response.get("errors", [{}])[0].get("message", "Unknown error")
        log(f"ERROR: Failed to fetch existing policy: {error_msg}")
        sys.exit(1)

    policy = response["result"]
    log(f"Current policy: name={policy['name']}, decision={policy['decision']}")

    # Build new include rules with IPs
    include_rules = [{"ip": {"ip": ipv4}}]
    if ipv6_network:
        include_rules.append({"ip": {"ip": ipv6_network}})

    # Build update payload
    update_payload = {
        "name": policy["name"],
        "decision": policy["decision"],
        "precedence": policy.get("precedence", 0),
        "include": include_rules,
        "exclude": policy.get("exclude", []),
        "require": policy.get("require", []),
    }

    log("Updating policy with new IPs...")
    try:
        response = cloudflare_request("PUT", policy_url, cf_token, update_payload)
    except Exception as e:
        log(f"ERROR: Zero Trust policy update failed: {e}")
        sys.exit(1)

    if response.get("success"):
        log("Zero Trust policy updated successfully")
        log(f"New include rules: {json.dumps(response['result']['include'])}")
    else:
        error_msg = response.get("errors", [{}])[0].get("message", "Unknown error")
        log(f"ERROR: Zero Trust policy update failed: {error_msg}")
        sys.exit(1)

    log("DynDNS update completed")


if __name__ == "__main__":
    main()
