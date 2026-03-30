# Docmost

Collaborative wiki and docs. Public, password auth by default.

- **URL:** `https://docmost.<domain>`
- **Access:** Public (HTTP-01 TLS)
- **SSO:** Not configured — requires Enterprise license (see below)
- **Image:** `docmost/docmost:latest` + `postgres:18` + `redis:8`

## First deploy

```bash
make -f core/Makefile init-app  APP=docmost DEPLOYMENT=.deployments/<name>/deployment.env
make -f core/Makefile deploy-app APP=docmost DEPLOYMENT=.deployments/<name>/deployment.env
make -f core/Makefile deploy     DEPLOYMENT=.deployments/<name>/deployment.env
```

Then run the setup guide:
```bash
bash apps/docmost/setup-guide.sh
```

On first load, a one-time setup wizard creates the workspace and admin account.
The setup endpoint is locked after completion.

## Storage

By default, Docker named volumes are used (easy try-out).
For backups, set bind mount paths in your deployment `app.conf`:

```bash
DOCMOST_DATA=/opt/sixnet/apps/docmost/data
DOCMOST_DB_DATA=/opt/sixnet/apps/docmost/db
```

Create the directories before deploy:
```bash
mkdir -p /opt/sixnet/apps/docmost/{data,db}
```

## SMTP

Required for invitations and password resets. Fill in your deployment `app.conf`:

```bash
DOCMOST_SMTP_HOST=smtp.office365.com
DOCMOST_SMTP_PORT=587
DOCMOST_SMTP_USERNAME=smtp-relay@example.com
DOCMOST_MAIL_FROM=no-reply@example.com
```

`DOCMOST_SMTP_PASSWORD` goes in `secrets.env`.

## SSO → Authentik (Enterprise)

Docmost OIDC SSO requires a paid Enterprise license. Once you have a license key:

1. Apply it: Settings → License & Edition → Enter license key
2. Create an OIDC provider in Authentik with:
   - Redirect URI: `https://docmost.<domain>/api/auth/sso/<provider-id>/callback`
   - Scopes: `openid`, `profile`, `email`
3. Configure in Docmost: Settings → Security & SSO → Create SSO → OpenID
   - Issuer URL: `https://auth.<domain>/application/o/docmost/`
   - Client ID / Secret from Authentik
   - Enable "Allow Signup" for JIT user provisioning
4. Test with a non-admin account before enabling "Enforce SSO"

Emergency bypass if SSO breaks: `https://docmost.<domain>/login?sso=false` (local login).
