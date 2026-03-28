# Twenty CRM

Open-source CRM. https://twenty.com

## Stack

| Container | Role |
|---|---|
| `twenty-server` | API + React frontend (port 3000) |
| `twenty-worker` | Background job processor |
| `twenty-db` | PostgreSQL 16 |
| `twenty-redis` | Redis (session, queues) |

`twenty-server` and `twenty-worker` share the same image and the same local storage volume (file uploads). The worker runs with `DISABLE_DB_MIGRATIONS=true` — migrations run in the server container on startup.

## Quick Start

```bash
# Add twenty to APPS in deployment.env
make init-app APP=twenty DEPLOYMENT=.deployments/Q1/deployment.env
make deploy-app APP=twenty DEPLOYMENT=.deployments/Q1/deployment.env
```

Then run the setup guide:
```bash
bash apps/twenty/setup-guide.sh
```

## Configuration

All configurable vars live in `app.conf` (template) and `.deployments/{NAME}/twenty/app.conf` (deployment).

| Variable | Default | Notes |
|---|---|---|
| `APP_SUBDOMAIN` | `crm` | Subdomain: `crm.yourdomain.com` |
| `TWENTY_DB_DATA` | Docker volume | Bind mount path for Postgres data |
| `TWENTY_SERVER_DATA` | Docker volume | Bind mount path for file uploads |
| `TWENTY_AUTH_PASSWORD_ENABLED` | `true` | Set false after SSO is working |
| `TWENTY_SMTP_HOST` | (empty) | Leave empty to disable email |

Generated secrets (never edit by hand):
- `TWENTY_APP_SECRET` — JWT signing key
- `TWENTY_DB_PASSWORD` — Postgres password

## SSO Transition (future)

Twenty's generic OIDC SSO requires an enterprise key. Password auth is the default. When you're ready to add Authentik SSO:

1. Set in `app.conf`:
   ```bash
   APP_SSO=true
   TWENTY_AUTH_SSO_ENABLED=true
   TWENTY_ENTERPRISE_KEY=<key or any string while unenforced>
   ```

2. Run `make init-app` → generates Authentik OAuth2 credentials and renders the blueprint

3. In Twenty admin UI → Settings → Security → SSO: add the OIDC provider:
   - Issuer: `https://auth.yourdomain.com/application/o/twenty/`
   - Client ID / Secret: from `secrets.env`

4. Test SSO in a private window, then set `TWENTY_AUTH_PASSWORD_ENABLED=false`

No data migration required — SSO is additive.

## Known Issues

**SERVER_URL must be exact.** Must match the external HTTPS URL exactly (`https://crm.yourdomain.com`, no trailing slash). Mismatch breaks OAuth callbacks and API requests from the frontend.

**First startup is slow.** The server runs DB migrations on startup. Allow 30–60 seconds before the UI is responsive.

**Memory.** Twenty needs ~2GB RAM in practice with all containers. Not suitable for the G9 Raspberry Pi deployment.
