# Immich v2 Upgrade Analysis

Comparison between current Podman quadlet configuration and new Immich v2 docker-compose.yml.

new docker-compose.yml:

```
#
# WARNING: To install Immich, follow our guide: https://docs.immich.app/install/docker-compose
#
# Make sure to use the docker-compose.yml of the current release:
#
# https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
#
# The compose file on main may not be compatible with the latest release.

name: immich

services:
  immich-server:
    container_name: immich_server
    image: ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-release}
    # extends:
    #   file: hwaccel.transcoding.yml
    #   service: cpu # set to one of [nvenc, quicksync, rkmpp, vaapi, vaapi-wsl] for accelerated transcoding
    volumes:
      # Do not edit the next line. If you want to change the media storage location on your system, edit the value of UPLOAD_LOCATION in the .env file
      - ${UPLOAD_LOCATION}:/data
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env
    ports:
      - '2283:2283'
    depends_on:
      - redis
      - database
    restart: always
    healthcheck:
      disable: false

  immich-machine-learning:
    container_name: immich_machine_learning
    # For hardware acceleration, add one of -[armnn, cuda, rocm, openvino, rknn] to the image tag.
    # Example tag: ${IMMICH_VERSION:-release}-cuda
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION:-release}
    # extends: # uncomment this section for hardware acceleration - see https://docs.immich.app/features/ml-hardware-acceleration
    #   file: hwaccel.ml.yml
    #   service: cpu # set to one of [armnn, cuda, rocm, openvino, openvino-wsl, rknn] for accelerated inference - use the `-wsl` version for WSL2 where applicable
    volumes:
      - model-cache:/cache
    env_file:
      - .env
    restart: always
    healthcheck:
      disable: false

  redis:
    container_name: immich_redis
    image: docker.io/valkey/valkey:8@sha256:81db6d39e1bba3b3ff32bd3a1b19a6d69690f94a3954ec131277b9a26b95b3aa
    healthcheck:
      test: redis-cli ping || exit 1
    restart: always

  database:
    container_name: immich_postgres
    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_DB: ${DB_DATABASE_NAME}
      POSTGRES_INITDB_ARGS: '--data-checksums'
      # Uncomment the DB_STORAGE_TYPE: 'HDD' var if your database isn't stored on SSDs
      # DB_STORAGE_TYPE: 'HDD'
    volumes:
      # Do not edit the next line. If you want to change the database storage location on your system, edit the value of DB_DATA_LOCATION in the .env file
      - ${DB_DATA_LOCATION}:/var/lib/postgresql/data
    shm_size: 128mb
    restart: always

volumes:
  model-cache:
```

**Analysis Date**: 2025-11-15
**Current Config**: `hosts/ops/containers/immich-*.{container,pod}`
**Target Version**: Immich v2 (docker-compose.yml from official release)

## 🔴 Critical Changes Required

### 1. Redis Image - BREAKING CHANGE

- **Current**: `docker.io/redis:6.2-alpine`
- **New**: `docker.io/valkey/valkey:8@sha256:81db6d39e1bba3b3ff32bd3a1b19a6d69690f94a3954ec131277b9a26b95b3aa`
- **File**: `immich-redis.container`
- **Impact**: Valkey is a Redis fork. Need to verify compatibility and migration path.
- **Action**: Update image, test compatibility with existing data

### 2. Database Image - BREAKING CHANGE

- **Current**: `docker.io/tensorchord/pgvecto-rs:pg14-v0.2.0`
- **New**: `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23`
- **File**: `immich-database.container`
- **Impact**: New official Immich PostgreSQL image with updated vector extensions (vectorchord0.4.3 + pgvectors0.2.0 vs pgvecto-rs v0.2.0). Likely requires database migration.
- **Action**: Plan database backup and migration strategy

### 3. Upload Volume Path - BREAKING CHANGE

- **Current**: `/mnt/pictures/immich:/usr/src/app/upload:Z`
- **New**: `${UPLOAD_LOCATION}:/data`
- **File**: `immich-server.container`
- **Impact**: The mount point inside the container changed from `/usr/src/app/upload` to `/data`. Your existing uploads at `/usr/src/app/upload` won't be found after upgrade.
- **Action**: Update volume mount to use `/data` as the container-side path

## 🟡 Important Changes

### 4. Shared Memory for Database

- **Current**: Not set
- **New**: `shm_size: 128mb`
- **File**: `immich-database.container`
- **Impact**: PostgreSQL needs shared memory for performance. Without it, may experience reduced performance or stability issues.
- **Action**: Add to `immich-database.container`:
  ```ini
  PodmanArgs=--shm-size=128m
  ```

### 5. Database Port Exposure

- **Current**: `immich.pod` exposes `PublishPort=5432:5432`
- **New**: Database port is NOT exposed (only internal to pod/network)
- **File**: `immich.pod`
- **Impact**: If you're accessing the database externally for backups or management, you'll lose that access.
- **Action**: Leave port exposed in upgraded config.

### 6. Timezone Mount

- **Current**: Missing
- **New**: `- /etc/localtime:/etc/localtime:ro`
- **File**: `immich-server.container`
- **Impact**: Container timezone won't match host system. May cause timestamp issues in logs and metadata.
- **Action**: Add to `immich-server.container`:
  ```ini
  Volume=/etc/localtime:/etc/localtime:ro
  ```

## 🟢 Minor Differences

### 7. Port Mapping

- **Current**: `PublishPort=8080:2283` (pod exposes on host port 8080)
- **New**: `2283:2283` (standard port)
- **File**: `immich.pod`
- **Impact**: You'll need to change your reverse proxy or access URL from `:8080` to `:2283`
- **Action**: Keep port 8080 mapped.

### 8. Container Naming Convention

- **Current**: Hyphens (immich-server, immich-redis, immich-database)
- **New**: Underscores (immich_server, immich_redis, immich_postgres)
- **File**: All `.container` files
- **Impact**: Cosmetic only. Doesn't affect functionality in pods.
- **Action**: Keep current naming.

### 9. Environment Variables

- **Current**: Hardcoded in `.container` files
  ```ini
  Environment=DB_HOSTNAME=localhost
  Environment=DB_USERNAME=postgres
  Environment=DB_PASSWORD=postgres
  Environment=DB_DATABASE_NAME=immich
  Environment=REDIS_HOSTNAME=localhost
  Environment=IMMICH_VERSION={filled-by-update-script}
  ```
- **New**: References `.env` file with variables like `${IMMICH_VERSION:-release}`, `${UPLOAD_LOCATION}`, `${DB_PASSWORD}`
- **File**: All `.container` files
- **Impact**: More flexible configuration, but Podman quadlet doesn't support `.env` files natively.
- **Action**: Use `EnvironmentFile=/path/to/immich.env` directive in quadlet files

### 10. Database Storage Type

- **Current**: Not specified
- **New**: Optional `DB_STORAGE_TYPE: 'HDD'` for non-SSD storage
- **File**: `immich-database.container`
- **Impact**: If your database volume (`immich-database`) is on HDD, PostgreSQL should tune accordingly
- **Action**: Do not adjust, db is on SSD

### 11. Container Restart Policy

- **Current**: Not explicitly set (systemd handles restarts)
- **New**: `restart: always` on all services
- **File**: All `.container` files
- **Impact**: Systemd already handles this via `WantedBy=default.target`
- **Action**: No change needed (systemd behavior is equivalent)

### 12. Health Checks

- **Current**: Set on redis and database:
  ```ini
  HealthCmd=redis-cli ping || exit 1
  HealthInterval=5s
  HealthTimeout=3s
  HealthRetries=5
  ```
- **New**: `healthcheck.disable: false` (meaning enabled, which is default)
- **File**: `immich-redis.container`, `immich-database.container`
- **Impact**: Your config is actually more detailed
- **Action**: Keep existing health checks (they're good!)

## 📋 Migration Checklist

### Migration Steps

1. [ ] Stop all Immich services:
   ```bash
   podman pod stop immich
   ```

2. [ ] Update `immich-redis.container`:
   ```ini
   Image=docker.io/valkey/valkey:8@sha256:81db6d39e1bba3b3ff32bd3a1b19a6d69690f94a3954ec131277b9a26b95b3aa
   ```

3. [ ] Update `immich-database.container`:
   ```ini
   Image=ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23
   PodmanArgs=--shm-size=128m
   # Add if on HDD:
   # Environment=DB_STORAGE_TYPE=HDD
   ```

4. [ ] Update `immich-server.container`:
   ```ini
   Volume=/mnt/pictures/immich:/data:Z
   Volume=/etc/localtime:/etc/localtime:ro
   ```

5. [ ] Update `immich.pod` (optional):
   ```ini
   # Change from:
   PublishPort=8080:2283
   # To (if you want standard port):
   PublishPort=2283:2283

   # Remove if not needed:
   # PublishPort=5432:5432
   ```

6. [ ] Deploy updated configs:
   ```bash
   just install-containers
   ```

7. [ ] Reload systemd daemon:
   ```bash
   systemctl --user daemon-reload
   ```

8. [ ] Start services in order:
   ```bash
   podman pod start immich
   ```

9. [ ] Verify services are running:
   ```bash
   systemctl --user status immich-server.service
   podman pod ps
   podman ps --filter pod=immich
   ```

10. [ ] Check logs for errors:
    ```bash
    journalctl --user -u immich-server.service -f
    ```

## 📚 References

- [Immich v2 Release](https://github.com/immich-app/immich/releases)
- [Immich Docker Compose](https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml)
- [Immich Documentation](https://docs.immich.app/)
- [Podman Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
