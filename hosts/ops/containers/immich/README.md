# Immich Container Configuration

This directory contains the Podman quadlet configuration files for Immich photo management system.

## Files

- `immich.pod` - Pod definition for all Immich containers
- `immich-server.container` - Main Immich application server
- `immich-machine-learning.container` - ML service for face detection, object recognition
- `immich-redis.container` - Redis/Valkey cache service
- `immich-database.container` - PostgreSQL database with vector extensions

## Current Version

**Version**: v1.135.3 → v2.2.3 (pending upgrade)

## Upgrade History

See `history/` directory for upgrade documentation:
- `upgrade-1.135.3-to-2.2.3.md` - Analysis and migration notes for v2 upgrade

## Deployment

Deploy these configs using:

```bash
# Deploy all container configs
just install-containers

# Preview changes
just containers-preview
```

## Upgrade Procedure

1. **Backup first!**
   ```bash
   just backup-immich
   ```

2. **Preview the upgrade**
   ```bash
   just upgrade-immich-preview v2.2.3
   ```

3. **Apply the upgrade**
   ```bash
   just upgrade-immich v2.2.3
   ```

4. **Deploy updated configs**
   ```bash
   just install-containers
   ```

5. **Reload systemd and restart**
   ```bash
   systemctl --user daemon-reload
   podman pod restart immich
   ```

6. **Monitor logs**
   ```bash
   journalctl --user -u immich-server.service -f
   ```

## Storage Locations

- **Uploads**: `/mnt/pictures/immich` → mounted to `/data` in container (v2+)
- **Database**: `immich-database` volume
- **Model Cache**: `immich-model-cache` volume

## Ports

- **Web UI**: `8080` (host) → `2283` (container)
- **Database**: `5432` (exposed for backups)

## Network

All containers run in the `immich` pod and share the pod network namespace, allowing them to communicate via `localhost`.
