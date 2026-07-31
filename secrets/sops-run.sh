#!/bin/bash

# Configuration
IMAGE_NAME="sops-manager-alpine"

# If called via sudo, keep using the invoking user's home + UID/GID.
HOST_UID="${SUDO_UID:-$(id -u)}"
HOST_GID="${SUDO_GID:-$(id -g)}"

CONTAINER_CLI="${CONTAINER_CLI:-docker}"

echo "🧩 Running with UID: ${HOST_UID}, GID: ${HOST_GID}"
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    LOCAL_HOME="$(eval echo "~${SUDO_USER}")"
else
    LOCAL_HOME="$HOME"
fi

LOCAL_KEY_DIR="$LOCAL_HOME/.config/sops/age"

# 1. Build (passes your local user IDs to the container)
echo "🚀 Building Alpine 3.23 Image..."
$CONTAINER_CLI build \
    --build-arg USER_ID="$HOST_UID" \
    --build-arg GROUP_ID="$HOST_GID" \
    -t $IMAGE_NAME .

# 2. Ensure key directory exists on host
mkdir -p "$LOCAL_KEY_DIR"

# 3. Run
# Mounts: Current Dir -> /app | Config -> /home/sopsuser/.config
# --userns=keep-id maps host UID/GID into the container (needed for Podman on macOS)
$CONTAINER_CLI run --rm -it \
    --userns=keep-id \
    -v "$(pwd)":/app \
    -v "$LOCAL_KEY_DIR":"/home/sopsuser/.config/sops/age" \
    $IMAGE_NAME "$@"
