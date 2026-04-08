# Umami

Privacy-focused web analytics. Public dashboard and tracker endpoint.

- **URL:** `https://umami.<domain>`
- **Access:** Public (HTTP-01 TLS)
- **SSO:** Not available in open-source edition (in progress upstream)
- **Image:** `ghcr.io/umami-software/umami:latest` + `postgres:15-alpine`
- **Default login:** `admin` / `umami` — change immediately after first boot

## First deploy

```bash
make -f core/Makefile init-app  APP=umami DEPLOYMENT=.deployments/<name>/deployment.env
make -f core/Makefile deploy-app APP=umami DEPLOYMENT=.deployments/<name>/deployment.env
make -f core/Makefile deploy     DEPLOYMENT=.deployments/<name>/deployment.env
```

Prisma migrations run automatically on startup. No manual DB setup needed.

## Storage

Only the database needs persistence. App container is stateless.
For backups, set a bind mount in your deployment `app.conf`:

```bash
UMAMI_DB_DATA=/opt/sixnet/apps/umami/db
```

Create the directory before deploy: `mkdir -p /opt/sixnet/apps/umami/db`

## Bypassing ad blockers

The default tracker path (`/script.js` + `/api/send`) is widely blocked.
Rename both in your deployment `app.conf`:

```bash
UMAMI_TRACKER_SCRIPT_NAME=analytics.js
UMAMI_COLLECT_API_ENDPOINT=/api/collect
```

Then use the renamed script URL in your site's tracking snippet.

## CORS

Do **not** add CORS headers in Caddy for Umami — the app sets
`Access-Control-Allow-Origin: *` itself on the tracker and collect endpoints.
Adding them at the proxy level causes duplicate header errors in browsers.

## Split routing (future)

If you later want the dashboard VPN-only but the tracker public, the Caddy
snippet needs two `remote_ip` rules — one allowing all IPs for `/api/send`
and `/script.js`, and one restricting everything else to `ZT_SUBNET`.
See `caddy/TLS_STRATEGIES.md` for the pattern.
