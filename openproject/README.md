# OpenProject Setup Guide

OpenProject deployment with VPN-only access using split-horizon DNS and IP whitelisting.

## Overview

**What this achieves:**
- OpenProject accessible only from VPN (projects.0x03.de)
- Valid Let's Encrypt TLS certificates (no browser warnings)
- Split-horizon DNS: VPN clients route internally, Let's Encrypt verifies via public DNS
- IP whitelisting blocks non-VPN traffic (HTTP 403)

**Architecture:**
- VPN clients resolve projects.0x03.de → 100.64.0.3 (internal VPN IP)
- Non-VPN clients resolve projects.0x03.de → public IP (for Let's Encrypt only)
- Traffic from VPN stays within VPN mesh (no internet hairpin)
- Caddy uses network_mode: host to see real client IPs for IP-based access control

## Deployment Status

**Deployed:** 2026-01-25
**Version:** OpenProject v17 (official Docker Compose stack)
**URL:** https://projects.0x03.de
**Access:** VPN-only (IP whitelisted to 100.64.0.0/10)

## Prerequisites

1. **VPN running** - Headscale operational with MagicDNS enabled
2. **Route 53 DNS** - CNAME record for projects.0x03.de
3. **Caddy with host networking** - Required for IP whitelisting
4. **VPN IP range** - 100.64.0.0/10 (Headscale default)

## Configuration Files

### 1. docker-compose.yml

**Location:** `deploy/openproject/docker-compose.yml`

**Key changes from official compose:**
- Backend network marked as `internal: true` (database not accessible externally)
- Web service exposed on `localhost:8090` (not public)
- Removed sixnet network (using host networking via Caddy)
- `OPENPROJECT_HTTPS=false` (Caddy terminates TLS)

### 2. secrets.env

**Location:** `deploy/openproject/secrets.env` (gitignored)

**Generated secrets:**
```bash
# PostgreSQL password
openssl rand -base64 36 | tr -d '\n'

# Collaborative editing secret
openssl rand -base64 32 | tr -d '\n'
```

**Environment variables:**
- `POSTGRES_PASSWORD` - Database password
- `COLLABORATIVE_SERVER_SECRET` - Hocuspocus collaboration secret
- `OPENPROJECT_HOST__NAME=projects.0x03.de`
- `OPENPROJECT_HTTPS=false` (critical - Caddy handles TLS)

### 3. Caddyfile Configuration

**Location:** `deploy/caddy/Caddyfile`

**OpenProject block:**
```caddyfile
projects.0x03.de {
    # Block non-VPN HTTPS traffic
    @not_vpn {
        not remote_ip 100.64.0.0/10
    }
    handle @not_vpn {
        respond "VPN access required" 403
    }

    # VPN traffic gets proxied to OpenProject
    handle {
        reverse_proxy localhost:8090
    }

    # Security headers
    header {
        Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "strict-origin-when-cross-origin"
    }

    encode gzip

    log {
        output file /var/log/caddy/projects.0x03.de.log
        format json
    }
}
```

**Key features:**
- `@not_vpn` matcher blocks non-VPN IPs with 403
- VPN IP range: 100.64.0.0/10 (Headscale default)
- Logging monitors access attempts and blocks

### 4. Headscale Split-Horizon DNS

**Location:** `deploy/headscale/config.yaml`

**DNS configuration:**
```yaml
dns_config:
  magic_dns: true
  base_domain: "headscale.six.net"

  nameservers:
    global:
      - 1.1.1.1
      - 8.8.8.8

  # Split-horizon DNS - VPN clients resolve to internal IP
  extra_records:
    - name: "projects.0x03.de"
      type: "A"
      value: "100.64.0.3"  # six-ra-2's VPN IP
```

**What this does:**
- VPN clients resolve projects.0x03.de → 100.64.0.3 (internal routing)
- Non-VPN clients resolve via public DNS → Fritz!Box IP (for Let's Encrypt)
- Traffic from VPN stays in VPN mesh (never touches internet)

## Deployment Steps

### 1. DNS Configuration

**Add Route 53 CNAME:**
```
projects.0x03.de CNAME sixnet-t1.dynv6.net.
```

**Verify propagation:**
```bash
dig projects.0x03.de
# Should resolve to Fritz!Box public IP via dynv6
```

### 2. Generate Secrets

```bash
cd deploy/openproject

cat > secrets.env << EOF
POSTGRES_PASSWORD=$(openssl rand -base64 36 | tr -d '\n')
COLLABORATIVE_SERVER_SECRET=$(openssl rand -base64 32 | tr -d '\n')
OPENPROJECT_HOST__NAME=projects.0x03.de
OPENPROJECT_HTTPS=false
EOF

chmod 600 secrets.env
```

### 3. Deploy to Server

```bash
# Sync files
make sync

# SSH to server and start services
ssh dluesebrink@six-ra-2
cd /opt/sixnet/openproject
docker compose up -d

# Monitor startup (takes 2-5 minutes for DB migrations)
docker compose logs -f
```

### 4. Reload Caddy

```bash
cd /opt/sixnet/caddy
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

### 5. Update Headscale DNS

After updating `deploy/headscale/config.yaml` with extra_records:

```bash
make sync
make restart-headscale

# Reconnect VPN clients to receive updated DNS
tailscale down
tailscale up --login-server https://vpn.0x03.de
```

## Verification

### Split-Horizon DNS

**Test from VPN client:**
```bash
tailscale up --login-server https://vpn.0x03.de
dig projects.0x03.de +short
# Expected: 100.64.0.3 (six-ra-2 VPN IP)
```

**Test from non-VPN:**
```bash
tailscale down
dig projects.0x03.de +short
# Expected: Fritz!Box public IP
```

### IP Whitelisting

**Test without VPN (should be blocked):**
```bash
tailscale down
curl -I https://projects.0x03.de
# Expected: HTTP/2 403 Forbidden
```

**Test with VPN (should work):**
```bash
tailscale up --login-server https://vpn.0x03.de
curl -I https://projects.0x03.de
# Expected: HTTP/2 302 (redirect to OpenProject)
```

**Test in browser:**
```bash
tailscale up
open https://projects.0x03.de
# Should load OpenProject login page
```

### Service Health

**Check containers:**
```bash
docker ps --filter "name=openproject" --format "table {{.Names}}\t{{.Status}}"
# All should show "Up" with (healthy) status
```

**Check database:**
```bash
docker exec openproject-db pg_isready -U openproject -d openproject
# Expected: "accepting connections"
```

**Check logs:**
```bash
docker logs caddy 2>&1 | grep projects.0x03.de | tail -10
# Look for VPN IPs (100.64.0.x) getting 200/302, non-VPN getting 403
```

## Troubleshooting

### Issue: 403 Forbidden when accessing from VPN

**Symptoms:** Getting 403 even when connected to VPN

**Causes & Solutions:**

1. **VPN IP not in whitelist range**
   ```bash
   # Check your VPN IP
   tailscale status | grep "$(hostname)"
   # Should be in 100.64.0.0/10 range

   # Verify Caddyfile has correct IP range
   grep "remote_ip" /opt/sixnet/caddy/Caddyfile
   ```

2. **MagicDNS not working**
   ```bash
   # Check Headscale DNS config
   docker logs headscale | grep -i dns

   # Verify client using MagicDNS
   scutil --dns | grep nameserver  # macOS
   resolvectl status               # Linux
   ```

3. **DNS resolving to public IP instead of VPN IP**
   ```bash
   # VPN clients should get 100.64.0.3
   dig projects.0x03.de +short

   # If getting public IP, check Headscale extra_records
   # Reconnect VPN client after config changes
   ```

### Issue: Let's Encrypt certificate renewal fails

**Symptoms:** Caddy logs show certificate renewal errors

**Solution:** Verify public DNS works:
```bash
# From outside your network (mobile data)
dig projects.0x03.de @8.8.8.8
# Should resolve to Fritz!Box public IP

# Test HTTP challenge path is accessible
curl http://projects.0x03.de/.well-known/acme-challenge/test
# Should NOT be 403 (404 is fine)
```

### Issue: OpenProject containers won't start

**Database initialization issues:**
```bash
# Check disk space
df -h
# Needs ~20GB free

# Check database logs
docker logs openproject-db

# Check database health
docker ps | grep openproject-db
```

**High memory usage:**
```bash
# Monitor resources
docker stats

# Reduce web workers if needed (in docker-compose.yml)
environment:
  RAILS_MIN_THREADS: 2  # Reduce from 4
  RAILS_MAX_THREADS: 8  # Reduce from 16
```

### Issue: Slow performance

**Solutions:**

1. **Verify Memcached running:**
   ```bash
   docker ps | grep openproject-cache
   ```

2. **Check database performance:**
   ```bash
   docker logs openproject-db | grep -i slow
   ```

3. **Monitor resource usage:**
   ```bash
   docker stats --no-stream
   ```

## Resource Usage

**Expected memory usage:**
- PostgreSQL: 300MB
- Memcached: 64MB
- Web (4 workers): 1.5GB
- Worker: 300MB
- Other services: 350MB
- **Total:** ~2.5GB

**System impact (Pi 4 with 8GB):**
- Combined with existing services: ~3.5GB / 8GB (44% utilization)
- Headroom: ~4.5GB for workload spikes

## Initial Configuration

**Default credentials:** admin/admin (change immediately!)

**First-time setup:**
1. Access https://projects.0x03.de (VPN required)
2. Complete setup wizard
3. Change admin password
4. Set organization name
5. Create test project

## Security Notes

1. **No port exposure:** OpenProject only exposed on localhost:8090
2. **Defense in depth:**
   - Layer 1: Split-horizon DNS (VPN clients route internally)
   - Layer 2: IP whitelisting (Caddy blocks non-VPN)
   - Layer 3: Let's Encrypt exception (certificates still work)
   - Layer 4: Application authentication (OpenProject login)

3. **Secrets management:**
   - secrets.env is gitignored
   - File permissions: 600 (owner read/write only)
   - Secrets generated with cryptographically secure random

## Future Enhancements

1. **SSO Integration** (requires OpenProject Enterprise Edition)
   - Authentik OAuth2/OIDC integration
   - Single sign-on across all six.net services
   - Guide: https://integrations.goauthentik.io/chat-communication-collaboration/openproject/

2. **SMTP Email Notifications**
   - Configure in secrets.env
   - Enable work package notifications
   - Password reset functionality

3. **Automated Backups**
   - Daily PostgreSQL dumps
   - Weekly opdata volume snapshots
   - Backup to Synology NAS via NFS

4. **Performance Monitoring**
   - Prometheus + Grafana (future service)
   - Track query performance, worker queue depth

## Known Limitations

1. **OpenProject Community Edition**
   - No OIDC/SAML SSO (Enterprise only)
   - No LDAP/Active Directory (Enterprise only)
   - Manual user creation required

2. **VPN-Only Access**
   - Users must be connected to VPN to access
   - Mobile access requires VPN app installed
   - No guest/public access possible

## References

- **Official OpenProject Docker Guide:** https://www.openproject.org/docs/installation-and-operations/installation/docker/
- **Authentik Integration:** https://integrations.goauthentik.io/chat-communication-collaboration/openproject/
- **Split-Horizon DNS:** See plan at `.claude/plans/zippy-launching-hopper.md`
- **Network Architecture:** `deploy/NETWORK.md`
