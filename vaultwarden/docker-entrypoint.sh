#!/bin/sh
# Entrypoint wrapper that reads Docker secrets into environment variables
# For each VAR_FILE env, read the file content into VAR

for var in $(env | grep '_FILE=' | cut -d= -f1); do
  # Get the file path
  eval file_path=\$$var
  
  # Derive the actual variable name (remove _FILE suffix)
  var_name="${var%_FILE}"
  
  if [ -f "$file_path" ]; then
    # Read the secret file and export as env var
    export "$var_name"="$(cat "$file_path")"
    unset "$var"
  fi
done

# Execute the original entrypoint
exec "$@"
