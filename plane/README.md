# Plane Project Management

Self-hosted project management and collaboration platform.

## Overview

- **URL**: `https://plane.${DOMAIN}` (public — no VPN required)
- **Access**: HTTP-01 TLS via FRP tunnel; DNS A record → FRP VPS public IP
- **SSO**: Not supported in open-source edition (see [SSO section](#sso--authentik))

## Architecture

Plane consists of 13 containers. The entry point is `plane-proxy` — Plane's
own Caddy instance that handles path-based routing to all backends.

```
Internet → FRP VPS → sixnet Caddy (TLS) → plane-proxy:80
                                                │
                              ┌─────────────────┼──────────────────┐
                              ▼                 ▼                  ▼
                         web:3000          api:8000          space:3000
                         admin:3000        live:3000
```

### Container naming convention

Plane's internal Caddyfile hardcodes upstream hostnames: `web`, `api`, `space`,
`admin`, `live`. Docker service names in `docker-compose.yml` must match these
exactly. The `container_name` fields use a `plane-` prefix for host-level
visibility (`docker ps`), but Docker Compose DNS resolves by **service name**,
not container name.

| Service name | Container name | Role |
|---|---|---|
| `db` | `plane-db` | PostgreSQL |
| `redis` | `plane-redis` | Valkey cache |
| `mq` | `plane-mq` | RabbitMQ |
| `minio` | `plane-minio` | Object storage |
| `api` | `plane-api` | Django API |
| `worker` | `plane-worker` | Background tasks |
| `beat` | `plane-beat` | Scheduled tasks |
| `migrator` | `plane-migrator` | DB migrations (runs once) |
| `live` | `plane-live` | Real-time collaboration |
| `web` | `plane-web` | Frontend |
| `space` | `plane-space` | Public spaces frontend |
| `admin` | `plane-admin` | God-mode admin frontend |
| `plane-proxy` | `plane-proxy` | Entry point (sixnet + plane-net) |

`plane-proxy` keeps the `plane-` prefix in both service name and container name
because it's the only container that lives on the `sixnet` network.

### Networks

- `plane-net` — internal network for all Plane services; `plane-proxy` routes inward
- `sixnet` — external; only `plane-proxy` is attached; Caddy proxies to it here

### plane-proxy environment

`SITE_ADDRESS: ":80"` disables Plane's own TLS acquisition — outer Caddy handles TLS.
`TRUSTED_PROXIES: "0.0.0.0/0"` allows X-Forwarded-* headers from outer Caddy.

Do **not** set `CERT_ACME_CA`, `CERT_ACME_DNS`, or `CERT_EMAIL` to empty strings —
they're interpolated into Plane's internal Caddyfile and an empty-value directive
causes a parse error that crashes plane-proxy on startup.

## Deployment

### 1. Initialize

```bash
make -f core/Makefile init-app APP=plane DEPLOYMENT=.deployments/Q1/deployment.env
```

### 2. Configure secrets

Edit `.deployments/Q1/plane/secrets.env`:

```bash
PLANE_SECRET_KEY=          # auto-generated
PLANE_LIVE_SECRET_KEY=     # auto-generated
PLANE_DB_PASSWORD=         # auto-generated
PLANE_RABBITMQ_PASSWORD=   # auto-generated
PLANE_MINIO_ACCESS_KEY=    # auto-generated
PLANE_MINIO_SECRET_KEY=    # auto-generated
```

### 3. Add to deployment

```bash
# In .deployments/Q1/deployment.env
APPS=plane,jellyfin,...
```

### 4. Deploy core (updates Caddyfile + Authentik)

```bash
make -f core/Makefile deploy DEPLOYMENT=.deployments/Q1/deployment.env
```

### 5. Deploy Plane

```bash
make -f core/Makefile deploy-app APP=plane DEPLOYMENT=.deployments/Q1/deployment.env
```

### 6. DNS

Point `plane.${DOMAIN}` A record to the FRP VPS public IP (not ZeroTier IP).
HTTP-01 TLS challenge goes through the FRP tunnel.

### 7. Post-deploy setup

```bash
make -f core/Makefile app-setup APP=plane DEPLOYMENT=.deployments/Q1/deployment.env
```

Walks through god-mode instance setup at `https://plane.${DOMAIN}/god-mode/`.

## SSO & Authentik

**OIDC SSO is not available in the open-source edition of Plane.** It is a
commercial feature (Plane Cloud / paid self-hosted plans only).

The `authentik-provider.yaml.template` and SSO variables (`APP_SSO=true`,
`APP_SSO_REDIRECT_URI`, `PLANE_AUTHENTIK_CLIENT_ID/SECRET`) are preserved in
this repo for the day Plane adds open-source SSO or we switch to a commercial
plan. The Authentik blueprint is deployed but the provider remains unused.

If/when Plane adds SSO:
- Callback URL to configure in god-mode: `https://plane.${DOMAIN}/auth/oidc-callback/`
- Issuer URL: `https://auth.${DOMAIN}/application/o/plane/`
- Credentials: `PLANE_AUTHENTIK_CLIENT_ID` / `PLANE_AUTHENTIK_CLIENT_SECRET`

## Health check

```
GET /health/     → 200 (Plane is up)
```

Note: `/api/health/` returns 404 — the correct endpoint is `/health/`.

## Troubleshooting

### plane-proxy crashes with `acme_ca` parse error

Plane's proxy uses a Caddyfile template. Passing empty env vars like
`CERT_ACME_CA: ""` inserts a bare `acme_ca` directive with no argument,
which Caddy rejects. Remove any `CERT_ACME_*` and `CERT_EMAIL` vars entirely.

### 502 from outer Caddy: `lookup plane-proxy: no such host`

Caddy runs in `network_mode: container:zerotier` and can only resolve containers
on the `sixnet` network. Verify `plane-proxy` is attached to `sixnet`:

```bash
docker inspect plane-proxy --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}'
```

If missing, the container was started before Docker could attach the network.
Force-recreate it:

```bash
docker compose -f /opt/sixnet/apps/plane/docker-compose.yml up -d --force-recreate plane-proxy
```

### 502 from plane-proxy: `lookup web: no such host`

The `web`, `api`, `space`, `admin`, `live` service names in `docker-compose.yml`
don't match what plane-proxy's Caddyfile expects. Service names (not container
names) must use Plane's defaults. See [Container naming](#container-naming-convention).

### Caddy bind mount stale after `make deploy` (QNAP)

On QNAP, Docker bind mounts can go stale when the source file is replaced (new
inode). `caddy reload` reads the stale copy and reports "config is unchanged".
Fix with a full container restart:

```bash
docker restart caddy
```

### god-mode shows "instance not configured"

First visit to god-mode creates the instance admin account. Complete this before
any other configuration. If stuck, check `docker logs plane-api`.
