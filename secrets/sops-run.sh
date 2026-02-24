#!/bin/bash

# Configuration
IMAGE_NAME="sops-manager-alpine"

# If called via sudo, keep using the invoking user's home + UID/GID.
HOST_UID="${SUDO_UID:-$(id -u)}"
HOST_GID="${SUDO_GID:-$(id -g)}"

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    LOCAL_HOME="$(eval echo "~${SUDO_USER}")"
else
    LOCAL_HOME="$HOME"
fi

LOCAL_KEY_DIR="$LOCAL_HOME/.config/sops/age"

# 1. Build (passes your local user IDs to the container)
echo "🚀 Building Alpine 3.23 Image..."
docker build \
    --build-arg USER_ID="$HOST_UID" \
    --build-arg GROUP_ID="$HOST_GID" \
    -t $IMAGE_NAME .

# 2. Ensure key directory exists on host
mkdir -p "$LOCAL_KEY_DIR"

# 3. Run
# Mounts: Current Dir -> /app | Config -> /home/sopsuser/.config
docker run --rm -it \
    -v "$(pwd)":/app \
    -v "$LOCAL_KEY_DIR":"/home/sopsuser/.config/sops/age" \
    $IMAGE_NAME "$@"
