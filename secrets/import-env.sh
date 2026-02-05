#!/bin/bash
# Imports environment variables from an .env file into individual secret files
# Usage: ./import-env.sh <path/to/env-file> <output-dir>

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <env-file> <output-dir>"
  echo ""
  echo "Arguments:"
  echo "  env-file    Path to the .env file to import"
  echo "  output-dir  Directory to write secret files to"
  echo ""
  echo "Example:"
  echo "  $0 ../env/nas_cron.env ./secrets"
  exit 1
fi

ENV_FILE="$1"
OUTPUT_DIR="$2"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: Environment file not found: $ENV_FILE"
  exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

echo "Importing secrets from: $ENV_FILE"
echo "Writing to: $OUTPUT_DIR"
echo ""

count=0

while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip empty lines and comments
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  
  # Parse KEY=VALUE (handle values with = in them)
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    
    # Remove surrounding quotes if present
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    
    # Convert key to lowercase for filename
    filename=$(echo "$key" | tr '[:upper:]' '[:lower:]')
    filepath="$OUTPUT_DIR/$filename"
    
    # Write value to file without trailing newline
    printf '%s' "$value" > "$filepath"
    chmod 600 "$filepath"
    
    echo "✓ $filename"
    count=$((count + 1))
  fi
done < "$ENV_FILE"

echo ""
echo "Done! Imported $count secrets."
echo ""
echo "Files created:"
ls -la "$OUTPUT_DIR" | grep -v -E '^\.|import-env\.sh|README\.md|total'
