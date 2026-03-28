#!/usr/bin/env bash
# Twenty CRM — Post-deploy setup guide
# Run after: make deploy-app APP=twenty DEPLOYMENT=...

set -euo pipefail

DOMAIN="${DOMAIN:-}"
APP_SUBDOMAIN="${APP_SUBDOMAIN:-crm}"
TWENTY_URL="https://${APP_SUBDOMAIN}.${DOMAIN}"

step() { echo ""; echo "=== Step $1: $2 ==="; }
pause() { read -rp "  Press Enter when done..."; }

echo ""
echo "Twenty CRM — Post-deploy setup"
echo "  URL: ${TWENTY_URL}"
echo ""

# =============================================================================
step 1 "Wait for Twenty to be ready"
# =============================================================================
echo "  Waiting for Twenty server to pass health check..."
for i in $(seq 1 24); do
    if curl -sf "${TWENTY_URL}/healthz" > /dev/null 2>&1; then
        echo "  Twenty is up."
        break
    fi
    echo "  ... (${i}/24)"
    sleep 5
done

# =============================================================================
step 2 "Create admin account"
# =============================================================================
cat <<EOF
  On first load, Twenty prompts you to create a workspace and admin account.

  1. Open: ${TWENTY_URL}
  2. Sign up with your email and password
  3. Create your workspace name

  This is the local admin account — not Authentik. Keep the password safe.

EOF
pause

# =============================================================================
step 3 "Configure workspace settings"
# =============================================================================
cat <<EOF
  1. Go to: ${TWENTY_URL}/settings/workspace
  2. Set your workspace name, logo, and timezone
  3. Invite other users if needed: Settings → Members → Invite

  See README.md for SSO transition steps when you're ready to add
  Authentik OIDC (enterprise key required).

EOF

echo "Twenty setup complete."
echo ""
echo "  URL:    ${TWENTY_URL}"
echo "  README: apps/twenty/README.md"
echo ""
