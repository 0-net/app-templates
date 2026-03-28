#!/usr/bin/env bash
#
# InvenTree pre-deploy script
# Creates the InvenTree data directory on the remote host if INVENTREE_DATA is set.
#
# Expects:
#   ENV_FILE - path to .env file with configuration
#   SSH_HOST - user@host for remote commands
#
# If INVENTREE_DATA is empty, a Docker named volume is used (no directory needed).

set -euo pipefail

if [ -z "${ENV_FILE:-}" ]; then
    echo "ERROR: ENV_FILE not set"
    exit 1
fi

if [ -z "${SSH_HOST:-}" ]; then
    echo "ERROR: SSH_HOST not set"
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

if [ -n "${INVENTREE_DATA:-}" ]; then
    echo "Creating InvenTree data directory on remote host..."
    echo "  ${INVENTREE_DATA}"
    ssh "$SSH_HOST" "mkdir -p '${INVENTREE_DATA}'" || echo "  WARNING: Could not create ${INVENTREE_DATA}"
    echo "Directory ready."
else
    echo "INVENTREE_DATA not set — using Docker named volume (no directory to create)."
fi
