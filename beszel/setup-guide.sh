#!/usr/bin/env bash
#
# Beszel post-deploy setup guide
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

BESZEL_URL="https://${APP_SUBDOMAIN:-beszel}.${DOMAIN}"
AUTH_URL="https://${SUBDOMAIN_AUTH:-auth}.${DOMAIN}"
BESZEL_FQDN="${APP_SUBDOMAIN:-beszel}.${DOMAIN}"

ZT_SERVER_IP="${ZT_SERVER_IP:-}"

step()  { echo ""; echo "─── Step $1: $2 ───"; echo ""; }
pause() { read -rp "    Press Enter to continue... "; echo ""; }

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║        Beszel Setup Guide — sixnet                   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Beszel:    ${BESZEL_URL}"
echo "  Authentik: ${AUTH_URL}"
echo ""
echo "  Connect to VPN (ZeroTier) before proceeding."
echo ""
pause

# =============================================================================
step 1 "DNS record for ${BESZEL_FQDN}"
# =============================================================================
cat <<EOF
  VPN-only apps need a DNS A record pointing to the server's ZeroTier IP.

  Use the upsert script:

    aws-vault exec <profile> -- \\
      scripts/dns/route53-upsert-a.sh \\
      ${AWS_HOSTED_ZONE_ID:-<hosted-zone-id>} \\
      ${BESZEL_FQDN} \\
      ${ZT_SERVER_IP:-<zerotier-ip-of-server>}

  Skip this step if the record already exists.

EOF
pause

# =============================================================================
step 2 "Wait for Beszel to be ready"
# =============================================================================
echo "  Polling ${BESZEL_URL}/api/health ..."
echo ""
ATTEMPTS=0
MAX_ATTEMPTS=18  # 90 seconds (18 × 5s)
until curl -sf -o /dev/null "${BESZEL_URL}/api/health" 2>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [[ $ATTEMPTS -ge $MAX_ATTEMPTS ]]; then
        echo "  ✗ Beszel did not become ready after 90 seconds."
        echo ""
        echo "  Check container status:"
        echo "    make -f core/Makefile app-status APP=beszel DEPLOYMENT=<deployment.env>"
        echo ""
        echo "  Check logs:"
        echo "    docker logs beszel"
        exit 1
    fi
    printf "  Waiting... (%ds)\r" $((ATTEMPTS * 5))
    sleep 5
done
echo "  ✓ Beszel is up                                    "
echo ""
pause

# =============================================================================
step 3 "Complete PocketBase and SSO configuration"
# =============================================================================

CLIENT_ID="${BESZEL_AUTHENTIK_CLIENT_ID:-<from beszel/secrets.env>}"
CLIENT_SECRET="${BESZEL_AUTHENTIK_CLIENT_SECRET:-<from beszel/secrets.env>}"

cat <<EOF
  The remaining steps require manual configuration through PocketBase's
  admin UI. Follow the detailed instructions in the README:

    apps/beszel/README.md — "Post-Deploy Setup" section

  Quick reference (exact steps in README):

    Step 1: Create the PocketBase superuser via CLI (no setup wizard):
      docker exec beszel /beszel superuser upsert admin@yourdomain.com <password>

    Step 2: Open ${BESZEL_URL}/_/#/settings
      - Set Application URL to ${BESZEL_URL}
      - Turn OFF "Hide collection create and edit controls"

    Step 3: Collections → users → gear → Options → OAuth2
      Enable OAuth2, Add provider → OpenID Connect
        Client ID:      ${CLIENT_ID}
        Client Secret:  ${CLIENT_SECRET}
        Auth URL:       ${AUTH_URL}/application/o/authorize/
        Token URL:      ${AUTH_URL}/application/o/token/
        User info URL:  ${AUTH_URL}/application/o/userinfo/

    Step 4: Test SSO in a private window at ${BESZEL_URL}

  The README also documents all known gotchas and troubleshooting steps.

EOF

echo "✓ Beszel automated setup done — complete PocketBase config manually."
echo ""
echo "  README:    apps/beszel/README.md"
echo "  Reference: https://beszel.dev/guide/oauth"
echo ""
