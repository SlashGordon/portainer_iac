#!/bin/bash
# 1. Reset for a clean slate
sudo ufw --force reset

# 2. Defaults
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 3. Secure SSH (Limit to your local machine range)
sudo ufw allow from 192.168.50.0/24 to any port 22 proto tcp comment 'Secure SSH'

# 4. The "Master" Local Rule 
# This covers Jellyfin, Gitea, Vaultwarden, and Traefik in one go
sudo ufw allow from 192.168.50.0/24 comment 'Trust Local Subnet'

# 5. Enable
echo "y" | sudo ufw enable