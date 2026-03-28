# Jellyfin Media Server

Self-hosted media streaming with Authentik SSO integration.

## Overview

- **URL**: `https://media.${DOMAIN}` (VPN-only)
- **Port**: 8096 (internal)
- **SSO**: OIDC via SSO Authentication plugin
- **Access**: ZeroTier VPN required

## Quick Start

### 1. Configure Media Paths

```bash
cp secrets.env.example secrets.env
vi secrets.env
```

Set your media library paths:
```bash
MEDIA_PATH_1=/share/Multimedia/Movies
MEDIA_PATH_2=/share/Multimedia/TV
MEDIA_PATH_3=/share/Multimedia/Music
```

### 2. Add to Deployment

```bash
# In deployment.env
APPS=openproject,jellyfin
```

### 3. Deploy

```bash
make -f core/Makefile deploy-apps DEPLOYMENT=.deployments/Q1/deployment.env
```

### 4. Initial Setup

1. Connect to VPN
2. Visit `https://media.yourdomain.com`
3. Complete initial wizard:
   - Create admin account
   - Configure media libraries (use /media/library1, /media/library2, etc.)
   - Skip remote access (Caddy handles this)

### 5. Configure SSO (Optional)

See [SSO Setup](#sso-setup-with-authentik) below.

## Configuration

### secrets.env

| Variable | Description | Example |
|----------|-------------|---------|
| `MEDIA_PATH_1` | First media library path | `/share/Multimedia/Movies` |
| `MEDIA_PATH_2` | Second media library path | `/share/Multimedia/TV` |
| `MEDIA_PATH_3` | Third media library path | `/share/Multimedia/Music` |
| `JELLYFIN_CONFIG` | Config storage path (optional) | `/share/fast/jellyfin/config` |
| `JELLYFIN_CACHE` | Cache storage path (optional) | `/share/fast/jellyfin/cache` |

### Adding More Media Paths

Edit `docker-compose.yml` to add more media paths:

```yaml
volumes:
  - ${MEDIA_PATH_4:-/dev/null}:/media/library4:ro
  - ${MEDIA_PATH_5:-/dev/null}:/media/library5:ro
```

## SSO Setup with Authentik

Jellyfin supports OIDC authentication via the community SSO plugin.

### Step 1: Create Authentik Provider

1. Log in to Authentik admin (`https://auth.yourdomain.com/if/admin`)
2. Navigate to **Applications > Providers > Create**
3. Select **OAuth2/OpenID Provider**
4. Configure:
   - **Name**: `Jellyfin`
   - **Authorization flow**: `default-provider-authorization-implicit-consent`
   - **Client type**: `Confidential`
   - **Redirect URIs**:
     ```
     https://media.yourdomain.com/sso/OID/redirect/authentik
     ```
   - **Signing Key**: `authentik Self-signed Certificate`
5. Save and note the **Client ID** and **Client Secret**

> **Note:** The redirect URI must match the SSO plugin provider name exactly,
> including case. If the Jellyfin SSO plugin provider is named `authentik`
> (lowercase), the redirect URI must use lowercase too.

### Step 2: Create Authentik Application

1. Navigate to **Applications > Applications > Create**
2. Configure:
   - **Name**: `Jellyfin`
   - **Slug**: `jellyfin`
   - **Provider**: `Jellyfin` (select the provider created above)
   - **Launch URL**: `https://media.yourdomain.com`
3. Save

> **Note:** The launch URL must be the Jellyfin home page, not the SSO endpoint.
> The Jellyfin SSO plugin's `/sso/OID/p/` endpoint only accepts POST requests
> (triggered by the login button) — navigating to it directly returns 425.
> From the Authentik library, users click Jellyfin → land on the Jellyfin login
> page → click "Sign in with authentik" to initiate SSO from there.

### Step 3: Install Jellyfin SSO Plugin

The SSO plugin is not in the default catalog — add the repository first.

1. **Dashboard > Plugins > Repositories** → click **+** and add:
   - **Name**: `SSO-Auth`
   - **URL**: `https://raw.githubusercontent.com/9p4/jellyfin-plugin-sso/manifest-release/manifest.json`
2. **Dashboard > Plugins > Catalog** → find **SSO-Auth** → install latest version
3. Restart Jellyfin

### Step 4: Configure SSO Plugin

1. Go to **Dashboard > Plugins > SSO Authentication**
2. Add new provider:
   - **Name of the OID Provider**: `authentik` (lowercase — must match the redirect URI)
   - **OID Endpoint**: `https://auth.yourdomain.com/application/o/jellyfin/`
   - **OpenID Client ID**: (from Step 1)
   - **OpenID Client Secret**: (from Step 1)
   - **Enabled**: checked
   - **Enable Authorization by Plugin**: checked
   - **Enable All Folders**: checked (or configure per-folder)
   - **Roles**: leave empty for default
3. Save

### Step 5: Enable SSO Button on Login Page

Without these two settings the SSO button does not appear on the login page.

**5a. Login disclaimer** — Dashboard > General > Branding > Login disclaimer:

```html
<form action="https://media.yourdomain.com/sso/OID/start/authentik">
  <button class="raised block emby-button button-submit">
    Sign in with authentik
  </button>
</form>
```

**5b. Custom CSS** — Dashboard > General > Branding > Custom CSS:

```css
a.raised.emby-button {
    padding: 0.9em 1em;
    color: inherit !important;
}
.disclaimerContainer {
    display: block;
}
```

### Step 6: Test SSO Login

1. Log out of Jellyfin
2. On login page, click **Authentik** button
3. Authenticate with Authentik
4. You'll be redirected back to Jellyfin and logged in

### User Management with SSO

- **New users**: Created automatically on first SSO login
- **Existing users**: Link by matching username/email
- **Admin access**: Configure in Authentik groups or Jellyfin manually

## Hardware Transcoding

### Intel QuickSync

Uncomment in `docker-compose.yml`:

```yaml
devices:
  - /dev/dri:/dev/dri
group_add:
  - "109"  # render group - check with: getent group render
```

Then in Jellyfin: **Dashboard > Playback > Transcoding > Hardware acceleration: Intel QuickSync**

### NVIDIA GPU

1. Install nvidia-docker2 runtime
2. Add to docker-compose.yml:
   ```yaml
   runtime: nvidia
   environment:
     - NVIDIA_VISIBLE_DEVICES=all
   ```

## Troubleshooting

### Can't access from internet

Jellyfin is VPN-only by design. Connect to ZeroTier first.

### Media not found

Check that:
1. Paths in `secrets.env` are correct
2. Paths exist on the Docker host
3. Jellyfin has read permission

```bash
# Verify paths
ls -la /share/Multimedia/Movies
```

### SSO not working

**"Issuer name does not match authority"** (in Jellyfin logs) — the Authentik provider
`issuer_mode` must be `per_provider`, not `global`. With `global`, the issuer in the
discovery document is `https://auth.yourdomain.com/`, which doesn't match the OID
Endpoint `https://auth.yourdomain.com/application/o/jellyfin/` configured in the plugin.
The blueprint sets this correctly — if the provider was created manually, check this field.

**"No matching provider found"** — provider name case mismatch. The Jellyfin SSO
plugin provider name and the redirect URI in Authentik must match exactly (including
case). Use lowercase `authentik` throughout.

**"Error processing request" / ArgumentNullException** — the Authentik application
launch URL is pointing to `/sso/OID/redirect/authentik` (the callback URL) instead
of the Jellyfin home page. Fix the launch URL to `https://media.yourdomain.com`.

**425 Too Early** — navigating directly to `/sso/OID/p/authentik`. This endpoint
only accepts POST. Use the Jellyfin login page and click the SSO button instead.

1. Check Authentik provider redirect URI matches SSO plugin name exactly (case-sensitive)
2. Verify Authentik application launch URL is the Jellyfin home page
3. Verify Jellyfin SSO plugin is enabled and restarted
4. Check Jellyfin logs: `docker logs jellyfin`
5. Verify network connectivity to Authentik

### Transcoding issues

1. Check hardware device exists: `ls -la /dev/dri`
2. Verify group ID: `getent group render`
3. Check Jellyfin logs for transcoding errors

## Network Flow

```
VPN Client
   │
   └─ ZeroTier (10.147.20.0/24)
       │
       └─ Caddy (media.domain.com:443)
           │
           └─ Jellyfin (jellyfin:8096)
                   │
                   └─ /media/* (read-only mounts)
```

## Security Notes

- VPN-only access prevents public exposure
- DNS-01 certificates - no public HTTP needed
- Media mounted read-only for safety
- SSO provides centralized authentication
- Local accounts still work as fallback

---

**Last Updated:** 2026-02-16
