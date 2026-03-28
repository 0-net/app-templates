#!/usr/bin/env bash
#
# Jellyfin post-deploy setup guide
# Interactive walkthrough for initial Jellyfin configuration and SSO setup.
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

MEDIA_URL="https://${APP_SUBDOMAIN}.${DOMAIN}"
AUTH_URL="https://auth.${DOMAIN}"
OIDC_ENDPOINT="${AUTH_URL}/application/o/jellyfin/"

step()  { echo ""; echo "─── Step $1: $2 ───"; echo ""; }
pause() { read -rp "    Press Enter to continue... "; echo ""; }

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║        Jellyfin Setup Guide — sixnet                 ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Jellyfin:  ${MEDIA_URL}"
echo "  Authentik: ${AUTH_URL}"
echo ""
echo "  Connect to VPN (ZeroTier) before proceeding."
echo ""
pause

# =============================================================================
step 1 "Complete Initial Wizard"
# =============================================================================
cat <<EOF
  1. Open ${MEDIA_URL} in your browser
  2. Click "Get Started"
  3. Create your admin account (choose any username + password)
  4. Add media libraries — use the container paths:
       /media/library1
       /media/library2
       /media/library3
     (These map to the paths configured in your deployment secrets.env)
  5. Preferred metadata language: your choice
  6. Remote access: keep default — Caddy handles external access
  7. Finish the wizard and log in

EOF
pause

# =============================================================================
step 2 "Install SSO Authentication Plugin"
# =============================================================================
cat <<EOF
  The SSO plugin is not in the default Jellyfin catalog — add the repo first.

  1. Dashboard → Plugins → Repositories
  2. Click "+" and add:
       Name: SSO-Auth
       URL:  https://raw.githubusercontent.com/9p4/jellyfin-plugin-sso/manifest-release/manifest.json
  3. Dashboard → Plugins → Catalog → find "SSO-Auth" → Install latest version
  4. Restart Jellyfin when prompted

  Alternatively, restart from the command line:
    make -f core/Makefile app-restart APP=jellyfin DEPLOYMENT=<your deployment.env>

EOF
pause

# =============================================================================
step 3 "Configure SSO Plugin"
# =============================================================================
cat <<EOF
  1. Dashboard → Plugins → SSO Authentication
  2. Click "+" to add a new OID provider — enter these exact values:

     Provider Name:             authentik
     OID Endpoint:              ${OIDC_ENDPOINT}
     Client ID:                 ${JELLYFIN_AUTHENTIK_CLIENT_ID}
     Client Secret:             ${JELLYFIN_AUTHENTIK_CLIENT_SECRET}

     ✓ Enabled
     ✓ Enable Authorization by Plugin
     ✓ Enable All Folders

  3. Save

  NOTE: Provider name must be exactly "authentik" (lowercase).
  This must match the redirect URI path segment registered in Authentik.

EOF
pause

# =============================================================================
step 4 "Enable SSO Button on Login Page"
# =============================================================================
cat <<EOF
  Without these two settings the SSO button does not appear on the login page.

  4a. Login disclaimer (the button itself)
      Dashboard → General → Branding → Login disclaimer
      Paste this HTML:

        <form action="${MEDIA_URL}/sso/OID/start/authentik">
          <button class="raised block emby-button button-submit">
            Sign in with authentik
          </button>
        </form>

  4b. Custom CSS (makes the disclaimer container visible)
      Dashboard → General → Branding → Custom CSS
      Paste this CSS:

        a.raised.emby-button {
            padding: 0.9em 1em;
            color: inherit !important;
        }
        .disclaimerContainer {
            display: block;
        }

  Save after each section.

EOF
pause

# =============================================================================
step 5 "Test SSO Login"
# =============================================================================
cat <<EOF
  1. Log out of Jellyfin
  2. On the login page, click "Sign in with authentik"
  3. Authenticate with your Authentik account
  4. You will be redirected back to Jellyfin and logged in

  Troubleshooting:
    "No matching provider found"   → provider name case mismatch (use lowercase)
    "Error processing request"     → Authentik application launch URL must be
                                     ${MEDIA_URL}/ (not the SSO callback URL)
    425 Too Early                  → do not navigate to /sso/OID/p/ directly;
                                     use the login page button instead
    Can't reach Jellyfin           → check VPN connection (ZeroTier)

EOF

echo "✓ Jellyfin setup complete!"
echo ""
echo "  Reference: https://integrations.goauthentik.io/media/jellyfin/"
echo ""
