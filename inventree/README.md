# InvenTree — Inventory Management

Self-hosted inventory management with Authentik SSO integration.

## Overview

- **URL**: `https://inventory.${DOMAIN}` (VPN-only)
- **Port**: 1337 (inventree-proxy, internal to sixnet network)
- **SSO**: OIDC via django-allauth `openid_connect` provider
- **Access**: ZeroTier VPN required

## Architecture

InvenTree requires four containers working together:

```
Internet → ZeroTier VPN → sixnet Caddy (TLS) → inventree-proxy:1337 → inventree-server:8000
                                                              ↘ static files (shared volume)
```

| Container          | Role                                     | Networks        |
|--------------------|------------------------------------------|-----------------|
| `inventree-db`     | PostgreSQL database                      | backend         |
| `inventree-server` | gunicorn web server (port 8000)          | backend         |
| `inventree-worker` | django-Q background task worker          | backend         |
| `inventree-proxy`  | InvenTree's bundled Caddy proxy (1337)   | sixnet, backend |

`inventree-proxy` is required — the production InvenTree image does not use whitenoise,
so static files must be served by the bundled Caddy, not gunicorn directly.

## Quick Start

### 1. Initialize

```bash
make -f core/Makefile init-app APP=inventree DEPLOYMENT=.deployments/{NAME}/deployment.env
```

This generates all secrets (SSO credentials + DB password) and scaffolds the deployment directory.

### 2. Configure app.conf

Edit `.deployments/{NAME}/inventree/app.conf`:

```bash
# Data directory on the server (leave empty for Docker named volume)
INVENTREE_DATA=/share/fast/sixnet/inventree

# Admin account — created on first run
INVENTREE_ADMIN_EMAIL=admin@example.com
INVENTREE_ADMIN_USER=admin
INVENTREE_ADMIN_PASSWORD=<strong-password>
```

### 3. Add to deployment

In `.deployments/{NAME}/deployment.env`:

```bash
APPS=openproject,jellyfin,inventree
```

### 4. Deploy

```bash
# Redeploy core (picks up new Authentik blueprint + Caddyfile entry)
make -f core/Makefile deploy DEPLOYMENT=.deployments/{NAME}/deployment.env

# Deploy InvenTree
make -f core/Makefile deploy-app APP=inventree DEPLOYMENT=.deployments/{NAME}/deployment.env
```

### 5. Post-deploy setup

```bash
make -f core/Makefile app-setup APP=inventree DEPLOYMENT=.deployments/{NAME}/deployment.env
```

This runs an interactive walkthrough to complete the SSO configuration.

## SSO Setup with Authentik

InvenTree SSO requires a two-phase setup:

**Phase 1 — Automatic** (done by `init-app` + `deploy`):
- Authentik OAuth2 provider created via blueprint
- InvenTree backend configured via `INVENTREE_SOCIAL_BACKENDS` + `INVENTREE_SOCIAL_PROVIDERS`

**Phase 2 — Manual** (done via InvenTree admin UI after deploy):

1. Log into InvenTree at `https://inventory.{DOMAIN}/admin/`
2. **Social Applications → Add**:
   - Provider: `OpenID Connect`
   - Provider ID: `authentik` ← must match exactly (case-sensitive)
   - Name: `Authentik`
   - Client ID: (from `secrets.env: INVENTREE_AUTHENTIK_CLIENT_ID`)
   - Secret key: (from `secrets.env: INVENTREE_AUTHENTIK_CLIENT_SECRET`)
   - Sites: add your site to Chosen sites
3. **Settings → Login Settings** → enable `SSO authentication`

### Why is Provider ID "authentik"?

The provider_id `authentik` appears in the OIDC callback URL:
```
https://inventory.{DOMAIN}/accounts/oidc/authentik/login/callback/
```
It must match exactly in three places:
1. The SocialApp `provider_id` field (django-allauth registration)
2. `INVENTREE_SOCIAL_PROVIDERS` JSON (env var)
3. The Authentik blueprint's `redirect_uris`

## Configuration Reference

### app.conf

| Variable                   | Description                              | Default        |
|----------------------------|------------------------------------------|----------------|
| `APP_SUBDOMAIN`            | Subdomain for inventory URL              | `inventory`    |
| `INVENTREE_DATA`           | Host path for data volume bind mount     | (named volume) |
| `INVENTREE_ADMIN_EMAIL`    | Initial admin email                      | (required)     |
| `INVENTREE_ADMIN_USER`     | Initial admin username                   | `admin`        |
| `INVENTREE_ADMIN_PASSWORD` | Initial admin password                   | (required)     |

### secrets.env

| Variable                            | Description                         | How set        |
|-------------------------------------|-------------------------------------|----------------|
| `INVENTREE_AUTHENTIK_CLIENT_ID`     | Authentik OAuth2 client ID          | auto (init-app) |
| `INVENTREE_AUTHENTIK_CLIENT_SECRET` | Authentik OAuth2 client secret      | auto (init-app) |
| `INVENTREE_DB_PASSWORD`             | PostgreSQL password                 | manual         |

## Troubleshooting

### First-run takes too long

InvenTree runs database migrations and collects static files on first start.
This can take 2-3 minutes on low-powered hardware (Raspberry Pi, QNAP ARM).
Watch progress: `make -f core/Makefile app-logs APP=inventree DEPLOYMENT=...`

### Static files return 404

`inventree-proxy` is not running or not connected to the `sixnet` network.
The proxy container shares the data volume with the server for static files.

```bash
docker logs inventree-proxy
docker inspect inventree-proxy | grep -A5 Networks
```

### "SocialApp matching query does not exist"

The django-allauth `SocialApp` record has not been created.
Complete Step 3 of the setup guide: Django admin → Social Applications → Add.

### Admin account not created

If `INVENTREE_ADMIN_EMAIL`/`INVENTREE_ADMIN_PASSWORD` were empty on first run,
create the superuser manually:

```bash
# On the server
docker exec -it inventree-server invoke superuser
```

### SSO button not visible on login page

`LOGIN_ENABLE_SSO` is disabled. Enable it in:
InvenTree → Settings → Global Settings → Login Settings → Enable SSO authentication

### Redirect URI mismatch in Authentik

The redirect URI in the Authentik provider must be exactly:
```
https://inventory.{DOMAIN}/accounts/oidc/authentik/login/callback/
```
Verify in Authentik admin → Applications → Providers → InvenTree OAuth2 Provider.

## Network Flow

```
VPN Client
   │
   └─ ZeroTier (10.147.20.0/24)
       │
       └─ Caddy (inventory.domain.com:443)  [TLS termination, VPN IP check]
           │
           └─ inventree-proxy (1337)  [static files + reverse proxy]
               │
               └─ inventree-server (8000)  [gunicorn / Django]
                       │
                       ├─ inventree-db (5432)  [PostgreSQL]
                       └─ inventree-worker  [background tasks]
```

## Security Notes

- VPN-only access — Caddy rejects requests from non-VPN IPs (403)
- DNS-01 TLS certificate — no public HTTP needed
- Dedicated PostgreSQL instance — not shared with Authentik
- SSO via Authentik — centralized authentication and user management
- Local admin account available as fallback

---

**Last Updated:** 2026-03-03
