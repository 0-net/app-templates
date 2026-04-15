# Creating a New App Template

This guide walks through authoring a new app template for the 0-net platform.

For **deploying** an existing template to a deployment, see
[core-stack: deploying-apps](https://github.com/0-net/core-stack/blob/main/docs/development/deploying-apps.md).

## Template structure

Each app is a directory in this repo:

```
{appname}/
├── README.md                          # App notes, gotchas, SSO steps
├── app.conf                           # Identity, access mode, SSO config, deployment vars
├── docker-compose.yml                 # Service definition
├── caddy.snippet                      # Reverse proxy config (injected at deploy time)
├── secrets.env.example                # Template for generated secrets
├── setup-guide.sh                     # Interactive post-deploy walkthrough (optional)
└── authentik-provider.yaml.template   # Authentik OAuth2/OIDC blueprint (SSO apps only)
```

## Template variable syntaxes

Three distinct notations appear across these files. They resolve at different times —
using the wrong one is a silent bug:

| Notation | Resolved by | When | Use in |
|---|---|---|---|
| `{{ .Env.VAR }}` | gomplate | deploy time (`make build-config`) | `caddy.snippet`, `authentik-provider.yaml.template` |
| `${VAR}` | Docker Compose | container start | `docker-compose.yml` only |
| `{$VAR}` / `{env.VAR}` | Caddy | Caddy startup | rendered `Caddyfile` (for runtime secrets) |
| `!Env VAR` | Authentik | Authentik startup | `authentik-provider.yaml.template` (runtime secrets) |

## Step-by-Step

### 1. Create the directory

```bash
mkdir <appname>
cd <appname>
```

### 2. Write `app.conf`

Metadata the deploy tooling reads:

```bash
APP_NAME=myapp               # Must match directory name
APP_SUBDOMAIN=myapp          # Results in myapp.<domain>
APP_ACCESS=public            # public | vpn
APP_SSO=false                # true = auto-provision Authentik OAuth2 provider
APP_DESCRIPTION="My application"
```

**Access modes:**
- `public` — HTTP-01 TLS challenge (needs port 80 reachable). No IP filtering.
- `vpn` — DNS-01 TLS via Route 53. IP-filtered to the ZeroTier subnet.

App-specific config vars (e.g. image tags, storage paths) can also go here with sensible
defaults; users override in the deployment-local copy.

### 3. Write `docker-compose.yml`

```yaml
networks:
  sixnet:
    external: true
    name: ${DOCKER_NETWORK_NAME:-sixnet}

services:
  myapp:
    image: myapp:latest
    container_name: myapp
    restart: unless-stopped
    networks:
      - sixnet
    environment:
      - APP_URL=https://${APP_SUBDOMAIN:-myapp}.${DOMAIN}
    env_file:
      - ./secrets.env
```

**Conventions:**
- Join the `sixnet` network (external) — Caddy routes by container name.
- `container_name` matches `APP_NAME` for single-service apps; use `<app>-db`, `<app>-redis`
  etc. for supporting services.
- Don't publish ports — Caddy handles external access.
- `${VAR}` is Docker Compose's own env-var substitution (from the combined `.env` the
  Makefile builds). Use it freely here.

### 4. Write `caddy.snippet`

The snippet gets injected into the core Caddyfile at deploy time (gomplate renders it,
then the Makefile appends it). Use `{{ .Env.VAR }}` for deploy-time values.

#### Public app

```caddyfile
{{ .Env.APP_SUBDOMAIN }}.{{ .Env.DOMAIN }} {
    reverse_proxy myapp:8080 {
        header_up X-Forwarded-Proto https
        header_up Host {host}
        header_up X-Forwarded-For {remote_host}
    }

    encode gzip

    log {
        output file /var/log/caddy/myapp.log
        format json
    }
}
```

#### VPN-only app

```caddyfile
{{ .Env.APP_SUBDOMAIN }}.{{ .Env.DOMAIN }} {
    # DNS-01 certificate via Route 53
    tls {
        dns route53 {
            hosted_zone_id {$AWS_HOSTED_ZONE_ID}
        }
    }

    # VPN-only access control
    @vpn remote_ip {{ .Env.ZT_SUBNET }}
    @blocked not remote_ip {{ .Env.ZT_SUBNET }}
    respond @blocked "VPN access required" 403

    reverse_proxy @vpn myapp:8080

    header {
        Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "strict-origin-when-cross-origin"
    }

    encode gzip

    log {
        output file /var/log/caddy/myapp.log
        format json
    }
}
```

Notes:
- `{$AWS_HOSTED_ZONE_ID}` is Caddy's own runtime placeholder — the value lives in
  Caddy's container environment (passed in from `core/secrets.env` via docker-compose).
  The Route53 plugin also picks up `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` from the
  environment automatically — no need to configure them in the `tls` block.
- `{{ .Env.ZT_SUBNET }}` comes from `defaults.env` (or is set by the deployment).

### 5. Write `secrets.env.example`

Template showing required secrets; users copy → fill in real values:

```bash
# apps/myapp/secrets.env.example
# Copy to secrets.env and fill in values

# Database
DB_PASSWORD=CHANGEME

# API keys
API_SECRET=CHANGEME
```

`secrets.env` itself is gitignored.

### 6. Write `authentik-provider.yaml.template` (SSO apps only)

Required when `APP_SSO=true`. Describes the OAuth2 provider and application that Authentik
should auto-provision at deploy time. Two template syntaxes coexist:

- `{{ .Env.VAR }}` — gomplate, resolved at build time (e.g. redirect URI, app slug)
- `!Env VAR` — Authentik, resolved at Authentik startup from the container env_file

Example skeleton:

```yaml
version: 1
metadata:
  name: MyApp OAuth2 Provider
  labels:
    blueprints.goauthentik.io/instantiate: "true"

entries:
  - identifiers:
      name: myapp-oauth2-provider
    id: myapp-provider
    model: authentik_providers_oauth2.oauth2provider
    attrs:
      name: myapp-oauth2-provider
      client_id: !Env MYAPP_AUTHENTIK_CLIENT_ID
      client_secret: !Env MYAPP_AUTHENTIK_CLIENT_SECRET
      client_type: confidential
      authorization_flow: !Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]
      invalidation_flow: !Find [authentik_flows.flow, [slug, default-provider-invalidation-flow]]
      redirect_uris:
        - url: "{{ .Env.APP_SSO_REDIRECT_URI }}"
          matching_mode: strict
      signing_key: !Find [authentik_crypto.certificatekeypair, [name, "authentik Self-signed Certificate"]]
      property_mappings:
        - !Find [authentik_providers_oauth2.scopemapping, [scope_name, openid]]
        - !Find [authentik_providers_oauth2.scopemapping, [scope_name, email]]
        - !Find [authentik_providers_oauth2.scopemapping, [scope_name, profile]]
      sub_mode: hashed_user_id
      include_claims_in_id_token: true
      issuer_mode: per_provider

  - identifiers:
      slug: myapp
    id: myapp-app
    model: authentik_core.application
    attrs:
      name: MyApp
      slug: myapp
      provider: !KeyOf myapp-provider
      meta_launch_url: "https://{{ .Env.APP_SUBDOMAIN }}.{{ .Env.DOMAIN }}/"
```

`APP_SSO_REDIRECT_URI` is set in `app.conf` since the path is app-specific (e.g.
`/login/oauth2/code/authentik` for Spring Security, `/oauth2/callback` for others).

Client credentials are generated by `init-app` and appear in two places: the app's
`secrets.env` and `core/authentik/secrets.env`.

### 7. Write `setup-guide.sh` (optional but recommended)

Interactive post-deploy walkthrough, invoked via `make app-setup APP=myapp`. The Makefile
passes `ENV_FILE` pointing at the combined `.env` so the guide can read deployment vars.

Minimal skeleton:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Source deployment env if invoked via make app-setup
[ -n "${ENV_FILE:-}" ] && [ -f "$ENV_FILE" ] && set -a && source "$ENV_FILE" && set +a

DOMAIN="${DOMAIN:-}"
APP_SUBDOMAIN="${APP_SUBDOMAIN:-myapp}"
URL="https://${APP_SUBDOMAIN}.${DOMAIN}"

step() { echo ""; echo "=== Step $1: $2 ==="; }
pause() { read -rp "  Press Enter when done..."; }

echo ""
echo "MyApp — Post-deploy setup"
echo "  URL: ${URL}"
echo ""

step 1 "Log in and change default password"
cat <<EOF
  1. Open: ${URL}
  2. Log in with the default credentials
  3. Change the password immediately
EOF
pause

echo "Setup complete."
```

### 8. Write `README.md`

Document the app. At a minimum:

- Brief description
- Required `secrets.env` values
- SSO notes (edition, known issues)
- App-specific gotchas and troubleshooting

## App configuration variables

Available in `docker-compose.yml` via `${VAR}` and in `caddy.snippet` /
`authentik-provider.yaml.template` via `{{ .Env.VAR }}`:

| Variable | Source | Example |
|----------|--------|---------|
| `DOMAIN` | deployment.env | `q1.example.com` |
| `APP_SUBDOMAIN` | app.conf | `projects` |
| `APP_NAME` | app.conf | `myapp` |
| `DOCKER_NETWORK_NAME` | defaults.env | `sixnet` |
| `ZT_SUBNET` | defaults.env / deployment.env | `10.147.20.0/24` |
| `APP_SSO_REDIRECT_URI` | app.conf (SSO apps) | `https://.../login/oauth2/code/authentik` |

## Examples

### Minimal public app

```yaml
# whoami/docker-compose.yml
networks:
  sixnet:
    external: true

services:
  whoami:
    image: traefik/whoami
    container_name: whoami
    networks:
      - sixnet
```

```caddyfile
# whoami/caddy.snippet
whoami.{{ .Env.DOMAIN }} {
    reverse_proxy whoami:80
}
```

```bash
# whoami/app.conf
APP_NAME=whoami
APP_SUBDOMAIN=whoami
APP_ACCESS=public
APP_SSO=false
```

### App with database

```yaml
# wiki/docker-compose.yml
networks:
  sixnet:
    external: true
  wiki-net:
    internal: true

volumes:
  wiki-db:
  wiki-data:

services:
  wiki:
    image: requarks/wiki:2
    container_name: wiki
    restart: unless-stopped
    networks:
      - sixnet
      - wiki-net
    environment:
      DB_TYPE: postgres
      DB_HOST: wiki-db
      DB_PORT: 5432
      DB_USER: postgres
      DB_PASS: ${WIKI_DB_PASSWORD}
      DB_NAME: wiki
    depends_on:
      - wiki-db

  wiki-db:
    image: postgres:15
    container_name: wiki-db
    restart: unless-stopped
    networks:
      - wiki-net
    volumes:
      - wiki-db:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: ${WIKI_DB_PASSWORD}
      POSTGRES_DB: wiki
```

## Checklist

- [ ] `app.conf` — correct `APP_NAME`, `APP_SUBDOMAIN`, `APP_ACCESS`, `APP_SSO`
- [ ] `docker-compose.yml` — joins `sixnet`, container name matches `APP_NAME`, no port publishing
- [ ] `caddy.snippet` — public or VPN-only variant, uses `{{ .Env.VAR }}`
- [ ] `secrets.env.example` — documents required secrets
- [ ] `authentik-provider.yaml.template` — if `APP_SSO=true`
- [ ] `setup-guide.sh` — post-deploy walkthrough (optional but standard)
- [ ] `README.md` — description, secrets, SSO notes, gotchas
- [ ] Tested end-to-end via `init-app` + `deploy-app` in a real deployment

## Troubleshooting

### App not reachable

1. Check container is running: `docker ps | grep <appname>`
2. Check container joined the `sixnet` network: `docker network inspect sixnet`
3. Check Caddy logs: `docker logs caddy`
4. Verify the rendered Caddyfile has your snippet:
   `grep <appname> .deployments/<name>/core/caddy/Caddyfile`

### 502 Bad Gateway

- Container name mismatch between `caddy.snippet` and `docker-compose.yml`
- App not listening on the expected port
- App still starting up — check logs with `make app-logs APP=<name>`

### VPN-only app accessible from internet

- Check IP filter in `caddy.snippet` uses `{{ .Env.ZT_SUBNET }}`
- Verify public DNS points to the ZeroTier IP, not the FRP/public IP

### TLS certificate errors

- **Public apps:** HTTP-01 needs port 80 reachable — check FRP tunnel or port forwarding.
- **VPN-only apps:** DNS-01 needs Route 53 credentials in the Caddy environment
  (see `core/secrets.env` → `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
  `AWS_HOSTED_ZONE_ID`).

### Variable shows up literally in the rendered Caddyfile

Check you used the right syntax for `caddy.snippet`:
- `{{ .Env.VAR }}` — gomplate, resolved at build time (this is what you want for most vars)
- `${VAR}` — passes through unchanged, ends up literal in the output ← wrong syntax
- `{$VAR}` — Caddy runtime, only for values that must stay dynamic (e.g. AWS keys)

## Relation to core-stack

This repo is consumed by the [core-stack](https://github.com/0-net/core-stack) Makefile.
The deploy flow (`make init-app`, `make deploy-app`) combines:

```
defaults.env + deployment.env + app.conf + secrets.env  →  .env (runtime)
caddy.snippet                                            →  injected into Caddyfile via gomplate
authentik-provider.yaml.template                         →  core/authentik/blueprints/ via gomplate
```

See the [core-stack deploy guide](https://github.com/0-net/core-stack/blob/main/docs/development/deploying-apps.md)
for the full deploy workflow.
