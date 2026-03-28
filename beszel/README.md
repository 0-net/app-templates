# Beszel — Server Monitoring

Lightweight server monitoring with Authentik SSO integration.

## Overview

- **URL**: `https://beszel.${DOMAIN}` (VPN-only)
- **Port**: 8090 (internal to sixnet Docker network)
- **SSO**: OIDC via PocketBase OAuth2 (Beszel's embedded auth backend)
- **Access**: ZeroTier VPN required

## Architecture

Beszel is a single container — the hub embeds PocketBase for its database and auth.
Agents (monitored servers) connect back to the hub via SSH over ZeroTier.

```
VPN Client → ZeroTier → sixnet Caddy (TLS) → beszel:8090
                                                    │
                                              PocketBase DB
                                              (SQLite, /beszel_data)
```

## Quick Start

### 1. Initialize

```bash
make -f core/Makefile init-app APP=beszel DEPLOYMENT=.deployments/{NAME}/deployment.env
```

Generates SSO credentials and scaffolds the deployment directory.

### 2. Configure app.conf

Edit `.deployments/{NAME}/beszel/app.conf`:

```bash
# Data directory on the server (leave empty for Docker named volume)
BESZEL_DATA=/share/fast/sixnet/beszel
```

### 3. Add to deployment

In `.deployments/{NAME}/deployment.env`:

```bash
APPS=plane,jellyfin,dash,beszel
```

### 4. Deploy

```bash
# Redeploy core (picks up Authentik blueprint + Caddyfile entry)
make -f core/Makefile deploy DEPLOYMENT=.deployments/{NAME}/deployment.env

# Deploy Beszel container
make -f core/Makefile deploy-app APP=beszel DEPLOYMENT=.deployments/{NAME}/deployment.env
```

### 5. Post-deploy setup

Read the sections below in order — the setup-guide script handles DNS and
health checks but the PocketBase and SSO configuration must be done manually.

```bash
make -f core/Makefile app-setup APP=beszel DEPLOYMENT=.deployments/{NAME}/deployment.env
```

---

## Post-Deploy Setup (Detailed)

### Step 1 — DNS record

VPN-only apps need a DNS A record pointing to the server's ZeroTier IP:

```bash
aws-vault exec <profile> -- \
  scripts/dns/route53-upsert-a.sh \
  <hosted-zone-id> \
  beszel.{DOMAIN} \
  <zerotier-ip-of-server>
```

### Step 2 — Create the PocketBase superuser (first run only)

Beszel embeds PocketBase as its auth backend. On a fresh install, PocketBase
does NOT show a setup wizard — it immediately shows a login form at `/_/#/`.

Create the superuser via CLI:

```bash
docker exec beszel /beszel superuser upsert admin@yourdomain.com yourpassword
```

This is the **break-glass admin** — separate from regular Beszel user accounts.
Keep the password safe. Log into `/_/#/` with these credentials to configure OAuth2.

> **Note**: `/_/#/` is PocketBase's admin panel. The main Beszel UI is at `/`.

### Step 3 — Configure PocketBase for OAuth2

Beszel's OAuth2 is configured entirely through PocketBase's admin UI — there
are no environment variables for provider configuration.

1. Open `https://beszel.{DOMAIN}/_/#/settings`
2. Verify **Application URL** is set to `https://beszel.{DOMAIN}` (not `localhost:8090`)
3. **Turn off** "Hide collection create and edit controls" — this toggle hides
   the collection edit icons; you need it off to reach the OAuth2 settings

4. Go to **Collections** (database icon in left sidebar)
5. Click **users** → gear icon → **Options** tab → expand **OAuth2** section
6. Toggle **Enable** on
7. Click **+ Add provider** → select **OpenID Connect (oidc)**

Fill in:

| Field | Value |
|-------|-------|
| Client ID | from `.deployments/{NAME}/beszel/secrets.env` |
| Client secret | from `.deployments/{NAME}/beszel/secrets.env` |
| Display name | `Authentik` |
| Auth URL | `https://auth.{DOMAIN}/application/o/authorize/` |
| Token URL | `https://auth.{DOMAIN}/application/o/token/` |
| User info URL | `https://auth.{DOMAIN}/application/o/userinfo/` |
| Fetch user info from | `User info URL` |

Click **Set provider config** → save.

> **Why no Discovery URL field?** PocketBase's OIDC form in v0.36.x requires
> individual endpoint URLs — it does not support auto-discovery. The endpoints
> above match Authentik's standard paths.

### Step 4 — Test SSO login

Open a private/incognito window, go to `https://beszel.{DOMAIN}`, click the
Authentik button. The first user to log in via SSO does NOT automatically
become admin — promote them manually in the Beszel UI after first login.

---

## Known Issues and Gotchas

### Authentik 2025.10+ — email_verified breaks PocketBase user creation

**Symptom**: SSO flow completes (user authenticates on Authentik, gets
redirected back) but Beszel shows a white screen. Browser console shows:

```json
{ "message": "Failed to create record.", "data": { "email": { "code": "validation_required" } } }
```

**Root cause**: PocketBase v0.36.x silently drops the email when
`email_verified: false` is returned by the OIDC provider. Starting with
Authentik 2025.10, the built-in `email` scope mapping returns the user's
actual `email_verified` attribute rather than hardcoded `True`. Users created
via the admin UI are not automatically email-verified, so `email_verified:
false` is returned, and PocketBase treats the email as blank.

**Fix**: The Authentik blueprint for Beszel (in this repo) creates a custom
scope mapping `beszel-email-verified` that hardcodes `email_verified: True`.
This mapping is automatically used instead of the built-in email mapping when
you deploy with `make deploy`.

If you encounter this on an existing deployment where the blueprint has already
run with the old mapping, update the Beszel provider manually:

1. Authentik admin → Customization → Property Mappings → Create → **Scope Mapping**
   - Name: `beszel-email-verified`
   - Scope name: `email`
   - Expression:
     ```python
     return {
         "email": request.user.email,
         "email_verified": True
     }
     ```
2. Applications → Providers → Beszel provider → Edit
3. In **Scopes**, move `authentik default OAuth Mapping: OpenID 'email'` back to
   Available, and move `beszel-email-verified` to Selected
4. Save

### PocketBase admin UI — "Hide collection create and edit controls" toggle

PocketBase's settings page has a toggle "Hide collection create and edit
controls" that is **on by default**. When on, the gear icon on the `users`
collection is invisible and you cannot reach the OAuth2 configuration.

Turn it off in Settings → Application before trying to configure OAuth2.

### PocketBase first-run — no setup wizard

Contrary to some documentation, recent PocketBase versions do NOT show a
superuser setup wizard at `/_/#/`. They immediately show a login form. The
only way to create the first superuser is via the CLI:

```bash
docker exec beszel /beszel superuser upsert email@domain password
```

### PocketBase OAuth2 field map — email not mappable

The "Optional users create fields map" in the users collection Options tab
shows `OAuth2 username`, `OAuth2 full name`, `OAuth2 avatar`, `OAuth2 id` —
but NOT `OAuth2 email`. The email field is handled separately by PocketBase
as the unique identity field. This means you cannot work around email issues
by remapping another claim to the email field.

### docker compose restart vs up --force-recreate

`docker compose restart` restarts the container process but does NOT re-read
environment variable changes from `docker-compose.yml`. Use:

```bash
docker compose up -d --force-recreate
```

to apply environment changes. Use `docker inspect beszel` to verify env vars
(the `env` binary is not available in the minimal Beszel image).

### Checking env vars in minimal container

The Beszel image has no standard Unix tools. Use:

```bash
docker inspect beszel | grep -A 20 '"Env"'
```

---

## Adding Agents

Agents are lightweight processes on monitored servers. They connect **to** the
hub over SSH — the hub initiates no outbound connections.

After deploying the hub, add agents from the Beszel UI:
- **Systems → Add system**
- Enter the server's ZeroTier IP and SSH port
- Beszel generates a public key — add it to `~/.ssh/authorized_keys` on the target

See: https://beszel.dev/guide/agent-installation

---

## Configuration Reference

### app.conf

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_SUBDOMAIN` | Subdomain for Beszel URL | `beszel` |
| `BESZEL_DATA` | Host path for data volume | (named volume) |
| `BESZEL_DISABLE_PASSWORD_AUTH` | Force SSO-only login | `false` |

### secrets.env

| Variable | Description | How set |
|----------|-------------|---------|
| `BESZEL_AUTHENTIK_CLIENT_ID` | Authentik OAuth2 client ID | auto (init-app) |
| `BESZEL_AUTHENTIK_CLIENT_SECRET` | Authentik OAuth2 client secret | auto (init-app) |

---

## Troubleshooting

### White screen after Authentik redirect

See "Authentik 2025.10+ — email_verified" gotcha above.

### Cannot find OAuth2 settings in PocketBase

The gear icon on the users collection is hidden. Turn off "Hide collection
create and edit controls" in Settings → Application.

### Discovery URL not supported

PocketBase v0.36.x OIDC form does not have a Discovery URL field. Enter
Auth URL, Token URL, and User info URL individually (see Step 3 above).

### SSO button not appearing on login page

The OIDC provider was not saved in PocketBase. Repeat Step 3 — make sure to
click "Set provider config" and then save the collection options.

### Redirect URI mismatch in Authentik

The redirect URI in the Authentik provider must be exactly:
```
https://beszel.{DOMAIN}/api/oauth2-redirect
```
This is set automatically by the blueprint. Verify in Authentik admin →
Applications → Providers → Beszel OAuth2 Provider.

---

**Last Updated:** 2026-03-20
