#!/usr/bin/env bash
# Stirling-PDF — Post-deploy setup guide
# Run after: make deploy-app APP=stirlingpdf DEPLOYMENT=...

set -euo pipefail

# Source deployment env if invoked via make app-setup
[ -n "${ENV_FILE:-}" ] && [ -f "$ENV_FILE" ] && set -a && source "$ENV_FILE" && set +a

DOMAIN="${DOMAIN:-}"
APP_SUBDOMAIN="${APP_SUBDOMAIN:-pdf}"
STIRLINGPDF_URL="https://${APP_SUBDOMAIN}.${DOMAIN}"
AUTH_URL="https://${SUBDOMAIN_AUTH:-auth}.${DOMAIN}"

step() { echo ""; echo "=== Step $1: $2 ==="; }
pause() { read -rp "  Press Enter when done..."; }

echo ""
echo "Stirling-PDF — Post-deploy setup"
echo "  URL: ${STIRLINGPDF_URL}"
echo ""

# =============================================================================
step 1 "Wait for Stirling-PDF to be ready"
# =============================================================================
echo "  Waiting for Stirling-PDF... (${STIRLINGPDF_URL}/login)"
for i in $(seq 1 24); do
    if curl -sfL --connect-timeout 5 "${STIRLINGPDF_URL}/login" > /dev/null 2>&1; then
        echo "  Stirling-PDF is up."
        break
    fi
    echo "  ... (${i}/24)"
    sleep 5
done

# =============================================================================
step 2 "Log in and change admin password"
# =============================================================================
cat <<EOF
  1. Open: ${STIRLINGPDF_URL}
  2. Log in with the admin credentials from your secrets.env
  3. Go to: Admin Settings → Change Password — set a strong password

EOF
pause

# =============================================================================
step 3 "Verify Authentik SSO"
# =============================================================================
cat <<EOF
  The Authentik blueprint was applied on core deploy.
  Verify the SSO button appears on the login page and works:

  1. Open an incognito window: ${STIRLINGPDF_URL}
  2. Click "Sign in with Authentik"
  3. Log in via Authentik — you should be redirected back and logged in
  4. Check the user was auto-created: Admin Settings → User Management

  Authentik app: ${AUTH_URL}/if/admin/#/core/applications

EOF
pause

# =============================================================================
step 4 "Optionally enforce SSO-only login"
# =============================================================================
cat <<EOF
  Once SSO is confirmed working, you can remove the password login button:
  Set STIRLINGPDF_LOGIN_METHOD=oauth2 in your deployment app.conf and redeploy.

  Keep STIRLINGPDF_LOGIN_METHOD=all until SSO is verified — otherwise you
  could lock yourself out.

EOF

echo "Stirling-PDF setup complete."
echo ""
echo "  URL:    ${STIRLINGPDF_URL}"
echo "  README: apps/stirlingpdf/README.md"
echo ""
