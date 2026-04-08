#!/usr/bin/env bash
# Umami — Post-deploy setup guide
# Run after: make deploy-app APP=umami DEPLOYMENT=...

set -euo pipefail

# Source deployment env if invoked via make app-setup
[ -n "${ENV_FILE:-}" ] && [ -f "$ENV_FILE" ] && set -a && source "$ENV_FILE" && set +a

DOMAIN="${DOMAIN:-}"
APP_SUBDOMAIN="${APP_SUBDOMAIN:-umami}"
UMAMI_URL="https://${APP_SUBDOMAIN}.${DOMAIN}"

step() { echo ""; echo "=== Step $1: $2 ==="; }
pause() { read -rp "  Press Enter when done..."; }

echo ""
echo "Umami — Post-deploy setup"
echo "  URL: ${UMAMI_URL}"
echo ""

# =============================================================================
step 1 "Wait for Umami to be ready"
# =============================================================================
echo "  Waiting for Umami (DB migrations run on startup)..."
for i in $(seq 1 24); do
    if curl -sf "${UMAMI_URL}" > /dev/null 2>&1; then
        echo "  Umami is up."
        break
    fi
    echo "  ... (${i}/24)"
    sleep 5
done

# =============================================================================
step 2 "Change the default admin password"
# =============================================================================
cat <<EOF
  Umami starts with a default admin account — change the password immediately.

  1. Open: ${UMAMI_URL}
  2. Log in with: admin / umami
  3. Go to: Settings → Profile → Change password

EOF
pause

# =============================================================================
step 3 "Add your first website"
# =============================================================================
cat <<EOF
  1. Settings → Websites → Add website
  2. Enter a name and domain (e.g. v1.vertamob.com)
  3. Copy the tracking snippet and add it to your site's <head>

  Tracker script URL: ${UMAMI_URL}/script.js
  (rename via UMAMI_TRACKER_SCRIPT_NAME in app.conf to bypass ad blockers)

EOF

echo "Umami setup complete."
echo ""
echo "  URL:    ${UMAMI_URL}"
echo "  README: apps/umami/README.md"
echo ""
