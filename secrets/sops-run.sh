#!/bin/bash

# Configuration
IMAGE_NAME="sops-manager-alpine"
LOCAL_KEY_DIR="$HOME/.config/sops/age"

# 1. Build (passes your local user IDs to the container)
echo "🚀 Building Alpine 3.23 Image..."
docker build \
    --build-arg USER_ID=$(id -u) \
    --build-arg GROUP_ID=$(id -g) \
    -t $IMAGE_NAME .

# 2. Ensure key directory exists on host
mkdir -p "$LOCAL_KEY_DIR"

# 3. Run
# Mounts: Current Dir -> /app | Config -> /home/sopsuser/.config
docker run --rm -it \
    -v "$(pwd)":/app \
    -v "$LOCAL_KEY_DIR":"/home/sopsuser/.config/sops/age" \
    $IMAGE_NAME "$@"
