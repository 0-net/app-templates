# Stirling-PDF

PDF tools suite. Public access, Authentik SSO via OIDC.

- **URL:** `https://pdf.<domain>`
- **Access:** Public (HTTP-01 TLS)
- **SSO:** Authentik OIDC (free tier, auto-provisioning)
- **Image:** `stirlingtools/stirling-pdf:latest`

## First deploy

```bash
make -f core/Makefile init-app  APP=stirlingpdf DEPLOYMENT=.deployments/<name>/deployment.env
make -f core/Makefile deploy     DEPLOYMENT=.deployments/<name>/deployment.env  # redeploy core: Authentik blueprint
make -f core/Makefile deploy-app APP=stirlingpdf DEPLOYMENT=.deployments/<name>/deployment.env
make -f core/Makefile deploy     DEPLOYMENT=.deployments/<name>/deployment.env  # redeploy core: Caddy snippet
```

Then run the setup guide:
```bash
make -f core/Makefile app-setup APP=stirlingpdf DEPLOYMENT=.deployments/<name>/deployment.env
```

## SSO Login Method

Controlled via `STIRLINGPDF_LOGIN_METHOD` in deployment `app.conf`:

| Value | Behaviour |
|---|---|
| `all` | Password login + SSO button (default — use during initial setup) |
| `oauth2` | SSO only — hides password login |
| `normal` | Password only — disables SSO |

Switch to `oauth2` only after SSO is confirmed working.

> **Known issue (Q1/QNAP):** SSO login fails on QNAP NAS deployments with "OAuth login failed —
> no token received". Root cause: Nimbus JOSE-JWT (used by Spring Security) has a 500ms read
> timeout; Authentik's JWKS endpoint takes 700ms–1.1s on QNAP hardware due to slow PostgreSQL
> I/O. Keep `STIRLINGPDF_LOGIN_METHOD=all` and use password login until Authentik performance
> is resolved.

## Email / SMTP

Stirling-PDF uses email for user invitations and password resets. Configure via deployment
`secrets.env`:

```bash
STIRLINGPDF_MAIL_ENABLED=true
STIRLINGPDF_SMTP_HOST=smtp.example.com
STIRLINGPDF_SMTP_PORT=587
STIRLINGPDF_SMTP_USERNAME=relay@example.com
STIRLINGPDF_SMTP_PASSWORD=<password>
STIRLINGPDF_SMTP_FROM=no-reply@example.com
STIRLINGPDF_SMTP_TLS=true
```

Without email, invite users manually via Admin Settings → User Management.

## Storage

`/configs` holds `settings.yml` and the embedded H2 database. Back this up.

For bind mounts in your deployment `app.conf`:
```bash
STIRLINGPDF_CONFIGS=/opt/sixnet/apps/stirlingpdf/configs
STIRLINGPDF_LOGS=/opt/sixnet/apps/stirlingpdf/logs
```

Create directories before deploy:
```bash
mkdir -p /opt/sixnet/apps/stirlingpdf/{configs,logs}
```

## Admin credentials

Set in deployment `app.conf` before first run:
```bash
STIRLINGPDF_ADMIN_USERNAME=admin
```
Password is auto-generated in `secrets.env` by `init-app`. Only effective before
the H2 database is first created — change via the UI after first login.

## Fat image (OCR + LibreOffice)

For full conversion support, change the image in deployment `docker-compose.yml`:
```yaml
image: stirlingtools/stirling-pdf:latest-fat
```
The fat image requires up to 6GB RAM under load.
