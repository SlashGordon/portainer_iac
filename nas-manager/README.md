# NAS Manager Webhook - FritzBox DynDNS Configuration

This webhook endpoint receives DynDNS updates from a FritzBox router and updates Cloudflare security rules via `nas-manager`.

## How It Works

1. FritzBox detects an IP address change (IPv4 or IPv6)
2. FritzBox calls the webhook URL with the new IP addresses
3. The webhook script updates Cloudflare WAF rules to allow traffic from your current IP

## FritzBox Configuration

### Step 1: Access DynDNS Settings

1. Open your FritzBox web interface (usually `http://fritz.box`)
2. Navigate to: **Internet** → **Freigaben** → **DynDNS**
3. Enable **DynDNS benutzen**

### Step 2: Configure Custom Provider

Select **Benutzerdefiniert** (Custom) as the DynDNS provider and enter the following:

| Field | Value |
|-------|-------|
| **Update-URL** | See below |
| **Domainname** | Your domain (e.g., `home.example.com`) |
| **Benutzername** | Any value (not used, but required by FritzBox) |
| **Kennwort** | Any value (not used, but required by FritzBox) |

### Step 3: Update-URL

#### Basic (IPv4 only):
```
http://<NAS-IP>:9000/hooks/fritzbox-dyndns-update?domain=<domain>&ipaddr=<ipaddr>
```

#### IPv4 + IPv6:
```
http://<NAS-IP>:9000/hooks/fritzbox-dyndns-update?domain=<domain>&ipaddr=<ipaddr>&ip6addr=<ip6addr>
```

#### Full (all parameters):
```
http://<NAS-IP>:9000/hooks/fritzbox-dyndns-update?domain=<domain>&ipaddr=<ipaddr>&ip6addr=<ip6addr>&ip6lanprefix=<ip6lanprefix>&username=<username>&pass=<pass>
```

### FritzBox Placeholders

The FritzBox automatically replaces these placeholders with actual values:

| Placeholder | Description |
|-------------|-------------|
| `<domain>` | Domain name configured in FritzBox |
| `<ipaddr>` | Current public IPv4 address |
| `<ip6addr>` | Current public IPv6 address |
| `<ip6lanprefix>` | IPv6 LAN prefix |
| `<username>` | Configured username |
| `<pass>` | Configured password |
| `<dualstack>` | Dualstack flag |

**Important:** The angle brackets `< >` are part of the placeholder syntax and must be included!

## Example Configuration

If your NAS IP is `192.168.1.100`:

```
http://192.168.1.100:9000/hooks/fritzbox-dyndns-update?domain=<domain>&ipaddr=<ipaddr>&ip6addr=<ip6addr>
```

## Environment Variables

The following environment variables must be set in `env/nas_cron.env`:

```bash
# Cloudflare Authentication
CF_AUTH_TOKEN=your_cloudflare_api_token

# Zone and Ruleset IDs
ZONE_ID=your_zone_id
RULESET_ID=your_ruleset_id

# Rule IDs to update
RULE_ID_PATCH=your_patch_rule_id
RULE_ID_MULTI=your_multi_rule_id

# Rule descriptions
DESCRIPTION_PATCH=Block all traffic but not ipv6 network
DESCRIPTION_MULTI=allow only my IPv6 network for specific hosts

# Expressions (base64 encoded)
EXPRESSION_PATCH_B64=base64_encoded_expression
EXPRESSION_MULTI_B64=base64_encoded_expression
```

## Testing

### Manual Test
```bash
curl "http://localhost:9000/hooks/fritzbox-dyndns-update?domain=test.example.com&ipaddr=1.2.3.4&ip6addr=2001:db8::1"
```

### Expected Response
```
good
```

### Check Logs
```bash
docker logs nas-manager-hooks
# or
docker exec nas-manager-hooks cat /var/log/dyndns-update.log
```

## Deployment

```bash
# Start the webhook service
docker compose -f hooks.yml up -d

# View logs
docker compose -f hooks.yml logs -f

# Rebuild after changes
docker compose -f hooks.yml up -d --build
```

## Troubleshooting

### Webhook not responding
- Check if container is running: `docker ps | grep nas-manager-hooks`
- Check container logs: `docker compose -f hooks.yml logs`
- Verify port 9000 is accessible from your FritzBox

### Cloudflare rules not updating
- Verify `CF_AUTH_TOKEN` has correct permissions (Zone WAF:Edit)
- Check if `ZONE_ID`, `RULESET_ID`, and `RULE_ID_*` are correct
- Test manually: `docker exec nas-manager-hooks nas-manager security cloudflare --help`

### FritzBox shows error
- Ensure the webhook responds with `good` (check with curl)
- FritzBox expects HTTP 200 response
- Check FritzBox system logs for details
