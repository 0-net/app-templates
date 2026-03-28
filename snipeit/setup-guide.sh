#!/usr/bin/env bash
# Snipe-IT — Post-deploy setup guide
# Run after: make deploy-app APP=snipeit DEPLOYMENT=...

set -euo pipefail

DOMAIN="${DOMAIN:-}"
APP_SUBDOMAIN="${APP_SUBDOMAIN:-assets}"
SNIPEIT_URL="https://${APP_SUBDOMAIN}.${DOMAIN}"

step() { echo ""; echo "=== Step $1: $2 ==="; }
pause() { read -rp "  Press Enter when done..."; }

echo ""
echo "Snipe-IT — Post-deploy setup"
echo "  URL: ${SNIPEIT_URL}"
echo ""

# =============================================================================
step 1 "Verify APP_KEY is set"
# =============================================================================
cat <<EOF
  Snipe-IT requires a Laravel APP_KEY before it will start.
  init-app generates one automatically (base64-encoded random key).

  If the app shows a blank page or key error, regenerate manually:
    docker compose run --rm snipeit php artisan key:generate --show
  Copy the output (base64:...) into your deployment's secrets.env as SNIPEIT_APP_KEY,
  then restart: docker compose up -d snipeit

EOF
pause

# =============================================================================
step 2 "Wait for Snipe-IT to be ready"
# =============================================================================
echo "  Waiting for Snipe-IT to pass health check (migrations may take ~60s)..."
for i in $(seq 1 30); do
    if curl -sf "${SNIPEIT_URL}" > /dev/null 2>&1; then
        echo "  Snipe-IT is up."
        break
    fi
    echo "  ... (${i}/30)"
    sleep 5
done

# =============================================================================
step 3 "Complete the setup wizard"
# =============================================================================
cat <<EOF
  On first load, Snipe-IT runs a web-based setup wizard.

  1. Open: ${SNIPEIT_URL}
  2. The wizard walks through: pre-flight checks → database → admin account → site settings
  3. Create your admin account (local auth — not Authentik)

  See README.md for:
  - SMTP configuration for password resets and notifications
  - SAML + LDAP path to Authentik SSO (when needed)

EOF

echo "Snipe-IT setup complete."
echo ""
echo "  URL:    ${SNIPEIT_URL}"
echo "  README: apps/snipeit/README.md"
echo ""
