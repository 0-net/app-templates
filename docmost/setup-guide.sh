#!/usr/bin/env bash
# Docmost — Post-deploy setup guide
# Run after: make deploy-app APP=docmost DEPLOYMENT=...

set -euo pipefail

DOMAIN="${DOMAIN:-}"
APP_SUBDOMAIN="${APP_SUBDOMAIN:-docmost}"
DOCMOST_URL="https://${APP_SUBDOMAIN}.${DOMAIN}"

step() { echo ""; echo "=== Step $1: $2 ==="; }
pause() { read -rp "  Press Enter when done..."; }

echo ""
echo "Docmost — Post-deploy setup"
echo "  URL: ${DOCMOST_URL}"
echo ""

# =============================================================================
step 1 "Wait for Docmost to be ready"
# =============================================================================
echo "  Waiting for Docmost (DB migrations may take ~30s)..."
for i in $(seq 1 24); do
    if curl -sf "${DOCMOST_URL}" > /dev/null 2>&1; then
        echo "  Docmost is up."
        break
    fi
    echo "  ... (${i}/24)"
    sleep 5
done

# =============================================================================
step 2 "Complete the setup wizard"
# =============================================================================
cat <<EOF
  On first load, Docmost shows a one-time setup page.

  1. Open: ${DOCMOST_URL}
  2. Enter: workspace name, your name, email, password
  3. The first user becomes workspace owner.

  The setup endpoint is locked after this — it cannot be re-run.

EOF
pause

# =============================================================================
step 3 "Configure SMTP (optional)"
# =============================================================================
cat <<EOF
  If SMTP is configured, test it via Settings → General → Email settings.
  SMTP is needed for invitations and password resets.

  See README.md for:
  - SSO transition (requires Docmost Enterprise license)

EOF

echo "Docmost setup complete."
echo ""
echo "  URL:    ${DOCMOST_URL}"
echo "  README: apps/docmost/README.md"
echo ""
