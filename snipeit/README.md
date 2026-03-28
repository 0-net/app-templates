# Snipe-IT

IT asset management. VPN-only, password auth by default.

- **URL:** `https://assets.<domain>`
- **Access:** VPN-only (ZeroTier subnet filter)
- **SSO:** Not configured — see [SAML + Authentik](#saml--authentik-sso) below
- **Image:** `snipe/snipe-it:v8-latest` + `mariadb:11`

## First deploy

```bash
make -f core/Makefile init-app  APP=snipeit DEPLOYMENT=.deployments/<name>/deployment.env
make -f core/Makefile deploy-app APP=snipeit DEPLOYMENT=.deployments/<name>/deployment.env
```

Then run the setup guide:
```bash
bash apps/snipeit/setup-guide.sh
```

On first load, the web wizard creates the database schema and admin account.

## APP_KEY

Snipe-IT requires a Laravel encryption key (`APP_KEY`). `init-app` generates one as
`base64:<random>`. If you need to regenerate:

```bash
docker compose run --rm snipeit php artisan key:generate --show
```

Store the output in your deployment's `secrets.env` as `SNIPEIT_APP_KEY`, then restart.

## Storage

By default, Docker named volumes are used (easy try-out, no path decision).
For production with backups, set bind mount paths in your deployment `app.conf`:

```bash
SNIPEIT_DATA=/share/fast/sixnet/snipeit/data
SNIPEIT_DB_DATA=/share/fast/sixnet/snipeit/db
```

The host directories must exist before deploy:
```bash
mkdir -p /share/fast/sixnet/snipeit/{data,db}
```

## SMTP

Fill in the SMTP vars in your deployment `app.conf` for password resets, audit
alerts, and asset assignment notifications. Without SMTP, password resets won't work.

```bash
SNIPEIT_MAIL_DRIVER=smtp
SNIPEIT_MAIL_HOST=smtp.example.com
SNIPEIT_MAIL_PORT=587
SNIPEIT_MAIL_USERNAME=user@example.com
SNIPEIT_MAIL_FROM_ADDR=assets@example.com
```

`SNIPEIT_MAIL_PASSWORD` goes in `secrets.env`.

## SAML + Authentik SSO

Snipe-IT open-source supports **SAML 2.0** — not OIDC. The transition requires:

1. **Authentik LDAP outpost** — Snipe-IT has no JIT user provisioning. Users must
   exist in Snipe-IT before they can log in via SAML. Authentik's LDAP outpost syncs
   users from Authentik into Snipe-IT via Settings → Integrations → LDAP.
2. **Authentik SAML provider** — create a SAML provider in Authentik pointing at
   `https://assets.<domain>/saml/acs` as the ACS URL.
3. **Snipe-IT SAML config** — Settings → Security → SAML Settings. Paste Authentik's
   IdP metadata XML.

Emergency bypass if SSO breaks: `https://assets.<domain>/login?nosaml`

This is significantly more complex than the OIDC path used by other apps. Only worth
it if you have many users — for a single admin, local password auth is fine.
