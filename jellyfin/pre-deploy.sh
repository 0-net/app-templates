#!/usr/bin/env bash
#
# Jellyfin pre-deploy script
# Creates subdirectories for config, cache, and media
#
# Expects:
#   ENV_FILE - path to .env file with configuration
#   SSH_HOST - user@host for remote commands
#
# Note: Top-level directories (e.g., /share/fast/sixnet/jellyfin) must exist.
#       This script only creates subdirectories.

set -euo pipefail

# Load configuration
if [ -z "${ENV_FILE:-}" ]; then
    echo "ERROR: ENV_FILE not set"
    exit 1
fi

if [ -z "${SSH_HOST:-}" ]; then
    echo "ERROR: SSH_HOST not set"
    exit 1
fi

# Source the env file to get variables
set -a
source "$ENV_FILE"
set +a

echo "Creating Jellyfin directories on remote host..."

# Create config and cache directories
for var in JELLYFIN_CONFIG JELLYFIN_CACHE; do
    dir="${!var:-}"
    if [ -n "$dir" ] && [ "$dir" != "/dev/null" ]; then
        echo "  $dir"
        ssh "$SSH_HOST" "mkdir -p '$dir'" || echo "  WARNING: Could not create $dir"
    fi
done

# Create media directories
for var in MEDIA_PATH_1 MEDIA_PATH_2 MEDIA_PATH_3 MEDIA_PATH_4 MEDIA_PATH_5; do
    dir="${!var:-}"
    if [ -n "$dir" ] && [ "$dir" != "/dev/null" ]; then
        echo "  $dir"
        ssh "$SSH_HOST" "mkdir -p '$dir'" || echo "  WARNING: Could not create $dir"
    fi
done

echo "Directories ready."
