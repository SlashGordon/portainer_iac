#!/bin/bash

# 1. Reset UFW to default (Warning: this clears existing rules)
sudo ufw --force reset

# 2. Set default policies: Deny everything coming in, allow everything going out
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 3. ALLOW LOCAL NETWORK ACCESS (192.168.50.x)
# This ensures you don't get locked out and your local devices can see the apps.
sudo ufw allow from 192.168.50.0/24 comment 'Allow Local Network'

# 4. ALLOW SPECIFIC PORTS (Based on your Compose files)
# [cite_start]Gitea Web and SSH [cite: 1]
sudo ufw allow from 192.168.50.0/24 to any port 3000 proto tcp comment 'Gitea Web'
sudo ufw allow from 192.168.50.0/24 to any port 2222 proto tcp comment 'Gitea SSH'

# [cite_start]Jellyfin Media Server [cite: 3]
sudo ufw allow from 192.168.50.0/24 to any port 8096 proto tcp comment 'Jellyfin'

# Vaultwarden
sudo ufw allow from 192.168.50.0/24 to any port 3231 proto tcp comment 'Vaultwarden'

# [cite_start]Webhooks (nas-manager-hooks) [cite: 2]
sudo ufw allow from 192.168.50.0/24 to any port 9000 proto tcp comment 'Webhooks'

# Traefik HTTP (For local routing)
sudo ufw allow from 192.168.50.0/24 to any port 80 proto tcp comment 'Traefik HTTP'

# 5. Enable UFW
echo "y" | sudo ufw enable

# 6. Show status
sudo ufw status verbose