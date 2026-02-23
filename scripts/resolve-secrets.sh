#!/bin/sh
# Shared entrypoint wrapper that reads Docker secrets into environment variables.
# For each *_FILE env var, reads the file content into the base variable.
# Usage: resolve-secrets.sh <command> [args...]

# Blocklist of variables to skip (won't be resolved from files)
BLOCKLIST="CONFIG_FILE"

for var in $(env | grep '_FILE=' | cut -d= -f1); do
  # Check if variable is in blocklist
  skip=0
  for blocked in $BLOCKLIST; do
    if [ "$var" = "$blocked" ]; then
      skip=1
      break
    fi
  done
  
  if [ $skip -eq 1 ]; then
    echo "[entrypoint] Skipping blocklisted variable: $var"
    continue
  fi
  
  base_var="${var%_FILE}"
  eval file_path="\$$var"
  if [ -f "$file_path" ]; then
    if [ -r "$file_path" ]; then
      export "$base_var"="$(cat "$file_path")"
      echo "[entrypoint] Loaded $base_var from $file_path"
    else
      echo "[entrypoint] ERROR: Cannot read $file_path (permission denied)" >&2
    fi
  else
    echo "[entrypoint] WARNING: Secret file not found: $file_path" >&2
  fi
done

exec "$@"
