# Justfile for ops-scripts repository
# Requires: uv (https://github.com/astral-sh/uv)

# Default target - show available tasks
default:
    @just --list

# Set up pre-commit environment using uv
setup:
    uv tool install pre-commit
    pre-commit install

# Run audit checks (pre-commit with useful hooks)
audit:
    @echo "Setting up pre-commit environment with uv..."
    uv tool install pre-commit || true
    @echo "Running pre-commit audit checks..."
    pre-commit run --all-files

# Run specific pre-commit checks
check-whitespace:
    uv tool run pre-commit run trailing-whitespace --all-files

check-yaml:
    uv tool run pre-commit run check-yaml --all-files

check-json:
    uv tool run pre-commit run check-json --all-files

check-bash:
    uv tool run pre-commit run check-executables-have-shebangs --all-files

# Install pre-commit hooks
install-hooks:
    uv tool install pre-commit
    pre-commit install

# Update pre-commit hooks
update-hooks:
    pre-commit autoupdate

# Clean pre-commit cache
clean:
    pre-commit clean

# Fix shell scripts permissions and formatting
fix-scripts:
    find . -name "*.sh" -type f -exec chmod +x {} \;
    @echo "Made all .sh files executable"

# Comprehensive check for the repository
full-audit: audit fix-scripts
    @echo "Full audit completed!"

# ============================================================================
# Dotfiles Management
# ============================================================================

# Install dotfiles using setup-dotfiles.py
dotfiles-install:
    uv run ./setup-dotfiles.py

# Dry run dotfiles installation (preview changes without applying)
dotfiles-preview:
    uv run ./setup-dotfiles.py -d -n

# Sync changes from home directory back to dotfiles
dotfiles-sync:
    uv run ./setup-dotfiles.py -s

# Show help for dotfiles setup script
dotfiles-help:
    uv run ./setup-dotfiles.py -h

# ============================================================================
# Container Management
# ============================================================================

# Install container systemd units using setup-containers.py
install-containers:
    uv run ./setup-containers.py

# Dry run container installation (preview changes without applying)
containers-preview:
    uv run ./setup-containers.py -d -n

# Sync changes from deployed system back to container sources
containers-sync:
    uv run ./setup-containers.py -s

# Show help for container setup script
containers-help:
    uv run ./setup-containers.py -h

# ============================================================================
# Backup Management
# ============================================================================

# Backup all Immich data (database, volumes, caches, configs)
backup-immich:
    uv run ./manage-backups.py backup-immich

# Dry run Immich backup (preview without executing)
backup-immich-preview:
    uv run ./manage-backups.py backup-immich -d -n

# List available Immich backups
list-backups:
    uv run ./manage-backups.py list-backups

# ============================================================================
# Immich Upgrade Management
# ============================================================================

# Upgrade Immich to specified version (e.g., just upgrade-immich v2.2.3)
upgrade-immich VERSION:
    uv run ./upgrade-immich.py {{VERSION}}

# Dry run Immich upgrade (preview changes without applying)
upgrade-immich-preview VERSION:
    uv run ./upgrade-immich.py {{VERSION}} -d -n

# List supported Immich upgrade paths
upgrade-immich-list:
    uv run ./upgrade-immich.py --list-versions
