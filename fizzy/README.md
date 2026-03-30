# Fizzy

Kanban issue and idea tracker by 37signals. Public, passwordless auth (magic links + passkeys).

- **URL:** `https://fizzy.<domain>`
- **Access:** Public (HTTP-01 TLS)
- **SSO:** Not possible — no OIDC/OAuth2 support in Fizzy
- **Image:** `ghcr.io/basecamp/fizzy:main` (no versioned tags)

## Auth

Fizzy is passwordless — no password field exists:

- **Magic link / code** — enter email, get a 6-character code by email (or in docker logs if SMTP not configured)
- **Passkey** — register Face ID / Touch ID / hardware key after first login for instant future access

## First deploy

```bash
make -f core/Makefile init-app  APP=fizzy DEPLOYMENT=.deployments/<name>/deployment.env
make -f core/Makefile deploy-app APP=fizzy DEPLOYMENT=.deployments/<name>/deployment.env
make -f core/Makefile deploy     DEPLOYMENT=.deployments/<name>/deployment.env
```

After deploy, open the URL and sign up. The first signup creates your account — after that, signups are closed.

## Inviting others

No email invitations — Fizzy uses a **join link**:

1. Account Settings → Invite people
2. Share the join link (or QR code) with whoever you want to admit
3. Regenerate the code to invalidate old links

There is no per-email or per-domain access control.

## Storage

By default, Docker named volume (SQLite databases + file uploads at `/rails/storage`).
For backups, set a bind mount in your deployment `app.conf`:

```bash
FIZZY_DATA=/opt/sixnet/apps/fizzy/data
```

Create the directory before deploy: `mkdir -p /opt/sixnet/apps/fizzy/data`

## SMTP

SMTP is important — without it, magic link codes only appear in docker logs.

```bash
FIZZY_SMTP_ADDRESS=smtp.office365.com
FIZZY_SMTP_PORT=587
FIZZY_SMTP_USERNAME=smtp-relay@example.com
FIZZY_MAILER_FROM=no-reply@example.com
```

`FIZZY_SMTP_PASSWORD` goes in `secrets.env`.
