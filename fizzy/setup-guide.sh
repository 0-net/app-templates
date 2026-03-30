#!/usr/bin/env bash
# Fizzy — Post-deploy setup guide
# Run after: make deploy-app APP=fizzy DEPLOYMENT=...

set -euo pipefail

DOMAIN="${DOMAIN:-}"
APP_SUBDOMAIN="${APP_SUBDOMAIN:-fizzy}"
FIZZY_URL="https://${APP_SUBDOMAIN}.${DOMAIN}"

step() { echo ""; echo "=== Step $1: $2 ==="; }
pause() { read -rp "  Press Enter when done..."; }

echo ""
echo "Fizzy — Post-deploy setup"
echo "  URL: ${FIZZY_URL}"
echo ""

# =============================================================================
step 1 "Wait for Fizzy to be ready"
# =============================================================================
echo "  Waiting for Fizzy (DB migrations run on startup)..."
for i in $(seq 1 24); do
    if curl -sf "${FIZZY_URL}" > /dev/null 2>&1; then
        echo "  Fizzy is up."
        break
    fi
    echo "  ... (${i}/24)"
    sleep 5
done

# =============================================================================
step 2 "Create your account"
# =============================================================================
cat <<EOF
  Fizzy is passwordless — login is via magic link (email code) or passkey.

  1. Open: ${FIZZY_URL}
  2. Enter your email address and submit
  3. If SMTP is configured: check your inbox for the 6-character code
     If SMTP is NOT configured: check docker logs for the code:
       docker logs fizzy | grep -i "sign in code\|confirmation"
  4. Enter the code — you're in

  After your account is created, signups are closed to others.
  Invite people via: Account Settings → Invite people (share the join link)

EOF
pause

# =============================================================================
step 3 "Register a passkey (recommended)"
# =============================================================================
cat <<EOF
  Skip the email step on future logins by registering a passkey:
  Profile → Security → Add passkey (Face ID / Touch ID / hardware key)

EOF

echo "Fizzy setup complete."
echo ""
echo "  URL:    ${FIZZY_URL}"
echo "  README: apps/fizzy/README.md"
echo ""
