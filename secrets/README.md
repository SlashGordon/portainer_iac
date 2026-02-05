# Secrets Directory

This directory contains secret files for Docker Compose secrets feature.

## Files Required

Each file should contain ONLY the secret value (no newline at end):

### Cloudflare Auth & Identifiers
- `cf_auth_token` - Cloudflare API token
- `zone_id` - Cloudflare Zone ID
- `ruleset_id` - Cloudflare Ruleset ID
- `rule_id_patch` - Rule ID for patch operations
- `rule_id_multi` - Rule ID for multi-host operations

### Descriptions
- `description_patch` - Description for patch rule
- `description_multi` - Description for multi-host rule

### Expressions
- `expression_patch` - Expression for patch rule
- `expression_patch_b64` - Base64 encoded expression for patch rule
- `expression_multi` - Expression for multi-host rule
- `expression_multi_b64` - Base64 encoded expression for multi-host rule

### Schedules
- `schedule_patch` - Cron schedule for patch operations
- `schedule_multi` - Cron schedule for multi-host operations

### NAS Manager Config
- `nas_manager_public_ip_providers` - IP providers (e.g., fritzbox-soap,external-http)
- `nas_manager_fritzbox_wanipconn_url` - FritzBox WAN IP connection URL
- `nas_manager_fritzbox_timeout` - FritzBox timeout value

## Using Infisical to Populate Secrets

### Option 1: Export from Infisical CLI

```bash
# Install Infisical CLI
brew install infisical/get-cli/infisical

# Login and init
infisical login
infisical init

# Export all secrets to files
for secret in CF_AUTH_TOKEN ZONE_ID RULESET_ID RULE_ID_PATCH RULE_ID_MULTI \
  DESCRIPTION_PATCH DESCRIPTION_MULTI EXPRESSION_PATCH EXPRESSION_PATCH_B64 \
  EXPRESSION_MULTI EXPRESSION_MULTI_B64 SCHEDULE_PATCH SCHEDULE_MULTI \
  NAS_MANAGER_PUBLIC_IP_PROVIDERS NAS_MANAGER_FRITZBOX_WANIPCONN_URL \
  NAS_MANAGER_FRITZBOX_TIMEOUT; do
  filename=$(echo "$secret" | tr '[:upper:]' '[:lower:]')
  infisical secrets get "$secret" --plain > "$filename"
done

# Set proper permissions
chmod 600 *
```

### Option 2: Manual creation from nas_cron.env

```bash
echo -n 'your-cf-auth-token' > cf_auth_token
echo -n '92bee030cc7e26797cdcc2a41d12ba2e' > zone_id
echo -n 'fb98506653ef4122bb9c55faf8b25d24' > ruleset_id
echo -n '04b6a85d69944102b90da4adaab8870f' > rule_id_patch
echo -n '3f466c5849d949db87718847e66c926d' > rule_id_multi
echo -n 'Block all traffic but not ipv6 network' > description_patch
echo -n 'allow only my IPv6 network for specific hosts' > description_multi
echo -n '(not ip.src in {{{PUBLIC_IPV6_NETWORK/64}} {{PUBLIC_IPV4}}})' > expression_patch
echo -n 'KG5vdCBpcC5zcmMgaW4ge3t7UFVCTElDX0lQVjZfTkVUV09SSy82NH19IHt7UFVCTElDX0lQVjR9fX0p' > expression_patch_b64
echo -n '(http.host in {"gitea.dieck-labs.de" "media.dieck-labs.de" "internal.dieck-labs.de" "vm.dieck-labs.de" "docker.dieck-labs.de" "git.dieck-labs.de"} and not ip.src in {{{PUBLIC_IPV6_NETWORK/64}} {{PUBLIC_IPV4}}})' > expression_multi
echo -n 'KGh0dHAuaG9zdCBpbiB7ImdpdGVhLmRpZWNrLWxhYnMuZGUiICJtZWRpYS5kaWVjay1sYWJzLmRlIiAiaW50ZXJuYWwuZGllY2stbGFicy5kZSIgInZtLmRpZWNrLWxhYnMuZGUiICJkb2NrZXIuZGllY2stbGFicy5kZSIgImdpdC5kaWVjay1sYWJzLmRlIn0gYW5kIG5vdCBpcC5zcmMgaW4ge3t7UFVCTElDX0lQVjZfTkVUV09SSy82NH19IHt7UFVCTElDX0lQVjR9fX0p' > expression_multi_b64
echo -n '0 2 * * *' > schedule_patch
echo -n '0 3 * * *' > schedule_multi
echo -n 'fritzbox-soap,external-http' > nas_manager_public_ip_providers
echo -n 'http://fritz.box:49000/igdupnp/control/WANIPConn1' > nas_manager_fritzbox_wanipconn_url
echo -n '3s' > nas_manager_fritzbox_timeout

chmod 600 *
```

## Security Notes

- Never commit these files to git (they're in .gitignore)
- Set file permissions to 600
- The container reads secrets from `/run/secrets/<name>`
