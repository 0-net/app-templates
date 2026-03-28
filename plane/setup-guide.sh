#!/usr/bin/env bash
#
# Plane post-deploy setup guide
# Interactive walkthrough for completing initial configuration and SSO setup.
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

PLANE_URL="https://${APP_SUBDOMAIN:-plane}.${DOMAIN}"
AUTH_URL="https://${SUBDOMAIN_AUTH:-auth}.${DOMAIN}"
PLANE_FQDN="${APP_SUBDOMAIN:-plane}.${DOMAIN}"

step()  { echo ""; echo "─── Step $1: $2 ───"; echo ""; }
pause() { read -rp "    Press Enter to continue... "; echo ""; }

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║        Plane Setup Guide — sixnet                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Plane:      ${PLANE_URL}"
echo "  Authentik:  ${AUTH_URL}"
echo ""
pause

# =============================================================================
step 1 "DNS record for ${PLANE_FQDN}"
# =============================================================================
cat <<EOF
  Public apps use HTTP-01 TLS — the DNS A record must point to the
  server's public IP (FRP VPS or direct), not the ZeroTier IP.

  For FRP deployments, point to the FRP VPS public IP.
  For Fritz!Box / direct port forwarding, point to your public IP.

  Skip this step if the record already exists.

EOF
pause

# =============================================================================
step 2 "Wait for Plane to be ready"
# =============================================================================
echo "  Polling ${PLANE_URL}/health/ ..."
echo ""
ATTEMPTS=0
MAX_ATTEMPTS=36  # 3 minutes (36 × 5s)
until curl -sf -o /dev/null "${PLANE_URL}/health/" 2>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [[ $ATTEMPTS -ge $MAX_ATTEMPTS ]]; then
        echo "  ✗ Plane did not become ready after 3 minutes."
        echo ""
        echo "  Check container status:"
        echo "    make -f core/Makefile app-status APP=plane DEPLOYMENT=<deployment.env>"
        echo ""
        echo "  Check logs:"
        echo "    docker logs plane-api"
        echo "    docker logs plane-migrator"
        exit 1
    fi
    printf "  Waiting... (%ds)\r" $((ATTEMPTS * 5))
    sleep 5
done
echo "  ✓ Plane is up                                        "
echo ""
pause

# =============================================================================
step 3 "Instance setup (god-mode)"
# =============================================================================
cat <<EOF
  Open god-mode to complete instance setup:

    ${PLANE_URL}/god-mode/

  1. Create the instance admin account (first visit only)
  2. Configure instance name, email settings if needed

EOF
pause

# =============================================================================
step 4 "Configure OIDC SSO via god-mode"
# =============================================================================
cat <<EOF
  Navigate to: ${PLANE_URL}/god-mode/settings/integrations/oidc/

  Fill in the OIDC settings:

    Provider Name:    Authentik
    Client ID:        ${PLANE_AUTHENTIK_CLIENT_ID:-<see secrets.env>}
    Client Secret:    ${PLANE_AUTHENTIK_CLIENT_SECRET:-<see secrets.env>}
    Issuer URL:       https://${SUBDOMAIN_AUTH:-auth}.${DOMAIN}/application/o/plane/

  Note the callback URL shown by god-mode — it must match the redirect_uri
  in the Authentik blueprint. If it differs from:
    ${APP_SSO_REDIRECT_URI:-https://${APP_SUBDOMAIN:-plane}.${DOMAIN}/auth/oidc-callback/}

  Update APP_SSO_REDIRECT_URI in app.conf and redeploy core:
    make deploy DEPLOYMENT=<deployment.env>

EOF
pause

# =============================================================================
step 5 "Test SSO Login"
# =============================================================================
cat <<EOF
  1. Open a private window and go to ${PLANE_URL}
  2. Click "Continue with SSO" or the Authentik login option
  3. Authenticate with your Authentik account
  4. You should be redirected back to Plane and logged in

  Troubleshooting:
    "Invalid redirect URI"   → callback URL mismatch (see Step 4)
    "Client not found"       → OIDC not saved in god-mode, or wrong client_id
    "Issuer URL unreachable" → check Authentik is running: docker logs authentik-server
    Redirect loops           → check TRUSTED_PROXIES and X-Forwarded-Proto headers
    "Can't reach Plane"      → DNS A record not pointing to public IP

EOF

echo "✓ Plane setup complete!"
echo ""
echo "  Reference: https://developers.plane.so/self-hosting"
echo ""
