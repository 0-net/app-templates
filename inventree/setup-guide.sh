#!/usr/bin/env bash
#
# InvenTree post-deploy setup guide
# Interactive walkthrough for completing SSO configuration.
#
# Expects:
#   ENV_FILE - path to combined .env with all deployment + app configuration

set -euo pipefail

if [ -z "${ENV_FILE:-}" ]; then
    echo "ERROR: ENV_FILE not set"
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

INVENTORY_URL="https://${APP_SUBDOMAIN:-inventory}.${DOMAIN}"
AUTH_URL="https://${SUBDOMAIN_AUTH:-auth}.${DOMAIN}"
INVENTORY_FQDN="${APP_SUBDOMAIN:-inventory}.${DOMAIN}"

ZT_SERVER_IP="${ZT_SERVER_IP:-}"

step()  { echo ""; echo "─── Step $1: $2 ───"; echo ""; }
pause() { read -rp "    Press Enter to continue... "; echo ""; }

# Patch a global setting via the InvenTree REST API.
# $1 = setting key (e.g. EMAIL_HOST)
# $2 = JSON value  (e.g. '"localhost"' for strings, 'true' for booleans)
api_patch_setting() {
    local key="$1"
    local json_value="$2"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PATCH "${INVENTORY_URL}/api/settings/global/${key}/" \
        -u "${INVENTREE_ADMIN_USER:-admin}:${INVENTREE_ADMIN_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "{\"value\": ${json_value}}")
    if [[ "$http_code" == "200" ]]; then
        echo "  ✓ ${key} = ${json_value}"
    else
        echo "  ✗ ${key} failed (HTTP ${http_code}) — set manually at ${INVENTORY_URL}/settings/global/"
        return 1
    fi
}

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║        InvenTree Setup Guide — sixnet                ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  InvenTree:  ${INVENTORY_URL}"
echo "  Authentik:  ${AUTH_URL}"
echo ""
echo "  Connect to VPN (ZeroTier) before proceeding."
echo "  InvenTree first-run can take 2-3 minutes (migrations + static files)."
echo ""
pause

# =============================================================================
step 1 "DNS record for ${INVENTORY_FQDN}"
# =============================================================================
cat <<EOF
  VPN-only apps need a DNS A record pointing to the server's ZeroTier IP
  (not the public FRP/internet IP). VPN clients resolve the hostname to
  the ZeroTier IP and connect directly — bypassing the FRP tunnel.

  Use the upsert script:

    aws-vault exec <profile> -- \\
      scripts/dns/route53-upsert-a.sh \\
      ${AWS_HOSTED_ZONE_ID:-<hosted-zone-id>} \\
      ${INVENTORY_FQDN} \\
      ${ZT_SERVER_IP:-<zerotier-ip-of-server>}

  The ZeroTier IP of the server is the zt0 address of the ZeroTier
  container (visible in NETWORK.md or: docker exec zerotier zerotier-cli status).

  Skip this step if the record already exists.

EOF
pause

# =============================================================================
step 2 "Wait for InvenTree to be ready"
# =============================================================================
echo "  Polling ${INVENTORY_URL}/api/ ..."
echo ""
ATTEMPTS=0
MAX_ATTEMPTS=36  # 3 minutes (36 × 5s)
until curl -sf -o /dev/null "${INVENTORY_URL}/api/" 2>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [[ $ATTEMPTS -ge $MAX_ATTEMPTS ]]; then
        echo "  ✗ InvenTree did not become ready after 3 minutes."
        echo ""
        echo "  Check container status:"
        echo "    make -f core/Makefile app-status APP=inventree DEPLOYMENT=<deployment.env>"
        echo ""
        echo "  Check logs:"
        echo "    docker logs inventree-server"
        exit 1
    fi
    printf "  Waiting... (%ds)\r" $((ATTEMPTS * 5))
    sleep 5
done
echo "  ✓ InvenTree is up                                    "
echo ""
pause

# =============================================================================
step 3 "Configure global settings via API"
# =============================================================================
cat <<EOF
  Applying required settings via the InvenTree API.
  Uses admin credentials from app.conf (${INVENTREE_ADMIN_USER:-admin}).

EOF

if [[ -z "${INVENTREE_ADMIN_PASSWORD:-}" ]]; then
    echo "  ✗ INVENTREE_ADMIN_PASSWORD not set — cannot configure via API."
    echo "    Set it in app.conf and re-run, or configure manually at:"
    echo "    ${INVENTORY_URL}/settings/global/"
    echo ""
else
    # EMAIL_HOST is a Django setting (not DB-backed) — set via INVENTREE_EMAIL_HOST
    # env var in docker-compose.yml, not via the API.
    api_patch_setting "LOGIN_ENABLE_SSO"     "true"
    api_patch_setting "LOGIN_ENABLE_SSO_REG" "true"
    echo ""
fi
pause

# =============================================================================
step 4 "Test SSO Login"
# =============================================================================
cat <<EOF
  The OIDC provider is configured via INVENTREE_SOCIAL_PROVIDERS (env var) —
  no Social Application record in the admin UI is needed.

  1. Log out of InvenTree (or open a private window)
  2. On the login page, click "Login with Authentik"
  3. You will be redirected to ${AUTH_URL}
  4. Authenticate with your Authentik account
  5. You will be redirected back to InvenTree and logged in

  Troubleshooting:
    "No matching provider"   → provider_id mismatch — must be exactly "authentik" in
                               INVENTREE_SOCIAL_PROVIDERS (docker-compose.yml)
    "Redirect URI mismatch"  → check Authentik blueprint: redirect_uri must be
                               ${INVENTORY_URL}/accounts/authentik/login/callback/
    SSO button missing       → Step 3 failed — check LOGIN_ENABLE_SSO at ${INVENTORY_URL}/settings/global/
    "signup_closed"          → Step 3 failed — check LOGIN_ENABLE_SSO_REG and EMAIL_HOST settings
    "Can't reach InvenTree"  → check VPN connection (ZeroTier)
    Static files 404         → inventree-proxy not running; check: docker logs inventree-proxy

EOF

echo "✓ InvenTree setup complete!"
echo ""
echo "  Reference: https://docs.inventree.org/en/latest/settings/SSO/"
echo ""
