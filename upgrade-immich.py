#!/usr/bin/env python3
"""
upgrade-immich.py - Automated Immich version upgrades for Podman quadlet configs

Manages version-specific upgrade paths for Immich container configurations.

Usage:
    ./upgrade-immich.py v2.2.3              # Upgrade to version 2.2.3
    ./upgrade-immich.py v2.2.3 -n           # Dry run
    ./upgrade-immich.py v2.2.3 -d           # Debug output
    ./upgrade-immich.py --list-versions     # List supported upgrade paths

Features:
* Version-specific upgrade paths
* Automatic config file updates
* Dry run mode for testing
* Beautiful console output with Rich

NOTE: Backups should be performed separately using 'just backup-immich' before upgrading.

Adding New Upgrade Paths:
    1. Add version detection logic to detect_current_version()
    2. Create upgrade function: upgrade_vX_X_X_to_vY_Y_Y()
    3. Add to UPGRADE_PATHS dictionary
    4. Document changes in hosts/ops/containers/immich/history/

Current Supported Upgrade Paths:
    - v1.135.3 -> v2.2.3 (Redis->Valkey, new DB image, volume path changes)
"""

# /// script
# dependencies = [
#     "rich>=13.0.0",
# ]
# ///

import argparse
import re
import sys
from pathlib import Path
from typing import Optional

from rich.panel import Panel
from rich.prompt import Confirm

# Import common utilities
import setup_common

# Configuration
SCRIPT_DIR = Path(__file__).parent.absolute()
IMMICH_CONFIG_DIR = SCRIPT_DIR / "hosts" / "ops" / "containers" / "immich"

# Container files
IMMICH_POD_FILE = IMMICH_CONFIG_DIR / "immich.pod"
IMMICH_SERVER_FILE = IMMICH_CONFIG_DIR / "immich-server.container"
IMMICH_ML_FILE = IMMICH_CONFIG_DIR / "immich-machine-learning.container"
IMMICH_REDIS_FILE = IMMICH_CONFIG_DIR / "immich-redis.container"
IMMICH_DATABASE_FILE = IMMICH_CONFIG_DIR / "immich-database.container"

# Global options
DRY_RUN = False
DEBUG = False

# Use console and log from setup_common
console = setup_common.console
log = setup_common.log

# Version upgrade paths
UPGRADE_PATHS = {
    ("v1.135.3", "v2.2.3"): "upgrade_v1_135_3_to_v2_2_3",
    # Future upgrade paths will be added here
    # ("v2.2.3", "v2.3.0"): "upgrade_v2_2_3_to_v2_3_0",
}


def detect_current_version() -> Optional[str]:
    """Detect current Immich version from container configs"""
    if not IMMICH_SERVER_FILE.exists():
        log.error(f"[red]Server config not found:[/] [bold]{IMMICH_SERVER_FILE}[/]")
        return None

    content = IMMICH_SERVER_FILE.read_text()

    # Look for image tag
    # Old format: Image=ghcr.io/immich-app/immich-server:release
    # Could also be: Image=ghcr.io/immich-app/immich-server:v1.135.3
    match = re.search(r'Image=ghcr\.io/immich-app/immich-server:(\S+)', content)

    if match:
        tag = match.group(1)
        if tag == "release":
            # If using "release" tag, assume old version that needs upgrading
            # Even if other changes were partially applied, we need the version tag updated
            log.warning("[yellow]Using :release tag, treating as v1.135.3[/]")
            return "v1.135.3"
        else:
            return tag if tag.startswith('v') else f'v{tag}'

    return None


def update_file_line(file_path: Path, old_pattern: str, new_line: str, description: str) -> bool:
    """Update a line in a file using regex pattern"""
    if not file_path.exists():
        log.error(f"[red]File not found:[/] [bold]{file_path}[/]")
        return False

    content = file_path.read_text()
    new_content = re.sub(old_pattern, new_line, content, flags=re.MULTILINE)

    if content == new_content:
        log.warning(f"[yellow]No change needed:[/] [dim]{description}[/]")
        return False

    if DRY_RUN:
        log.warning(f"[yellow]NORUN:[/] [dim]Update {file_path.name}: {description}[/]")
        return True

    file_path.write_text(new_content)
    log.info(f"[green]Updated {file_path.name}:[/] [bold]{description}[/]")
    return True


def add_file_line_after(file_path: Path, after_pattern: str, new_line: str, description: str) -> bool:
    """Add a new line after a pattern match"""
    if not file_path.exists():
        log.error(f"[red]File not found:[/] [bold]{file_path}[/]")
        return False

    content = file_path.read_text()

    # Check if line already exists
    if new_line.strip() in content:
        log.info(f"[dim]Already present:[/] [dim]{description}[/]")
        return False

    # Find the pattern and add after it
    lines = content.split('\n')
    new_lines = []
    added = False

    for line in lines:
        new_lines.append(line)
        if re.search(after_pattern, line) and not added:
            new_lines.append(new_line)
            added = True

    if not added:
        log.warning(f"[yellow]Pattern not found:[/] [dim]{after_pattern}[/]")
        return False

    new_content = '\n'.join(new_lines)

    if DRY_RUN:
        log.warning(f"[yellow]NORUN:[/] [dim]Add to {file_path.name}: {description}[/]")
        return True

    file_path.write_text(new_content)
    log.info(f"[green]Added to {file_path.name}:[/] [bold]{description}[/]")
    return True


def upgrade_v1_135_3_to_v2_2_3() -> bool:
    """
    Upgrade from Immich v1.135.3 to v2.2.3

    Key changes:
    - Redis -> Valkey 8
    - Database image updated with new vector extensions
    - Server upload path: /usr/src/app/upload -> /data
    - Add timezone mount to server
    - Add shared memory to database
    - Update server and ML image tags to v2.2.3
    """
    console.log(Panel("UPGRADING: v1.135.3 -> v2.2.3", style="bold green"))

    changes_made = []

    # 1. Update server image to v2.2.3
    log.info("[bold blue]1. Updating server image to v2.2.3...[/]")
    if update_file_line(
        IMMICH_SERVER_FILE,
        r'Image=ghcr\.io/immich-app/immich-server:.*',
        'Image=ghcr.io/immich-app/immich-server:v2.2.3',
        "Server image: release -> v2.2.3"
    ):
        changes_made.append("Server image updated to v2.2.3")

    # 2. Update ML image to v2.2.3
    log.info("[bold blue]2. Updating ML image to v2.2.3...[/]")
    if update_file_line(
        IMMICH_ML_FILE,
        r'Image=ghcr\.io/immich-app/immich-machine-learning:.*',
        'Image=ghcr.io/immich-app/immich-machine-learning:v2.2.3',
        "ML image: release -> v2.2.3"
    ):
        changes_made.append("ML image updated to v2.2.3")

    # 3. Update Redis to Valkey
    log.info("[bold blue]3. Updating Redis to Valkey 8...[/]")
    if update_file_line(
        IMMICH_REDIS_FILE,
        r'Image=docker\.io/redis:.*',
        'Image=docker.io/valkey/valkey:8@sha256:81db6d39e1bba3b3ff32bd3a1b19a6d69690f94a3954ec131277b9a26b95b3aa',
        "Redis -> Valkey 8"
    ):
        changes_made.append("Redis -> Valkey 8")

    # 4. Update Database image
    log.info("[bold blue]4. Updating Database image...[/]")
    if update_file_line(
        IMMICH_DATABASE_FILE,
        r'Image=docker\.io/tensorchord/pgvecto-rs:.*',
        'Image=ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23',
        "Database image update"
    ):
        changes_made.append("Database image updated")

    # 5. Add shared memory to database
    log.info("[bold blue]5. Adding shared memory to database...[/]")
    if add_file_line_after(
        IMMICH_DATABASE_FILE,
        r'Pod=immich\.pod',
        'PodmanArgs=--shm-size=128m',
        "Shared memory for database"
    ):
        changes_made.append("Database shared memory added")

    # 6. Update server volume path
    log.info("[bold blue]6. Updating server upload volume path...[/]")
    if update_file_line(
        IMMICH_SERVER_FILE,
        r'Volume=/mnt/pictures/immich:/usr/src/app/upload:Z',
        'Volume=/mnt/pictures/immich:/data:Z',
        "Upload path: /usr/src/app/upload -> /data"
    ):
        changes_made.append("Server volume path updated")

    # 7. Add timezone mount to server
    log.info("[bold blue]7. Adding timezone mount to server...[/]")
    if add_file_line_after(
        IMMICH_SERVER_FILE,
        r'Volume=/mnt/pictures/immich:/data:Z',
        'Volume=/etc/localtime:/etc/localtime:ro',
        "Timezone mount"
    ):
        changes_made.append("Timezone mount added")

    # Summary
    if changes_made:
        console.log(Panel("CHANGES APPLIED", style="bold green"))
        for change in changes_made:
            log.info(f"[green]✓[/] {change}")
        return True
    else:
        log.warning("[yellow]No changes were needed[/]")
        return False


def list_supported_versions() -> None:
    """List all supported upgrade paths"""
    console.log(Panel("SUPPORTED UPGRADE PATHS", style="bold blue"))

    if not UPGRADE_PATHS:
        log.warning("[yellow]No upgrade paths defined[/]")
        return

    log.info("[cyan]Available upgrade paths:[/]")
    for (from_ver, to_ver), func_name in UPGRADE_PATHS.items():
        log.info(f"  [bold]{from_ver}[/] [dim]->[/] [bold green]{to_ver}[/]")


def find_upgrade_path(current: str, target: str) -> Optional[str]:
    """Find upgrade function for version path"""
    key = (current, target)
    func_name = UPGRADE_PATHS.get(key)

    if func_name:
        return func_name

    log.error(f"[red]No upgrade path found:[/] [bold]{current} -> {target}[/]")
    log.info("[cyan]Supported upgrade paths:[/]")
    for (from_ver, to_ver), _ in UPGRADE_PATHS.items():
        log.info(f"  [bold]{from_ver}[/] [dim]->[/] [bold]{to_ver}[/]")

    return None


def upgrade_to_version(target_version: str) -> bool:
    """Perform upgrade to target version"""
    # Detect current version
    current_version = detect_current_version()

    if not current_version:
        log.error("[red]Could not detect current Immich version[/]")
        return False

    log.info(f"[cyan]Current version:[/] [bold]{current_version}[/]")
    log.info(f"[cyan]Target version:[/] [bold]{target_version}[/]")

    # Check if already at target version
    if current_version == target_version:
        log.warning(f"[yellow]Already at version {target_version}[/]")
        return False

    # Find upgrade path
    upgrade_func_name = find_upgrade_path(current_version, target_version)

    if not upgrade_func_name:
        return False

    # Confirm upgrade
    if not DRY_RUN:
        log.warning(f"[yellow]This will upgrade Immich from {current_version} to {target_version}[/]")
        log.warning("[yellow]Make sure you have run 'just backup-immich' first![/]")
        if not Confirm.ask("[bold]Continue with upgrade?[/]", default=False):
            log.info("[dim]Upgrade cancelled[/]")
            return False

    # Execute upgrade
    upgrade_func = globals()[upgrade_func_name]
    success = upgrade_func()

    if success:
        console.log(Panel("UPGRADE COMPLETED", style="bold green"))
        log.info("[cyan]Next steps:[/]")
        log.info("  1. Review the changes in [bold]hosts/ops/containers/immich/[/]")
        log.info("  2. Deploy configs: [bold]just install-containers[/]")
        log.info("  3. Reload systemd: [bold]systemctl --user daemon-reload[/]")
        log.info("  4. Restart Immich: [bold]podman pod restart immich[/]")
        log.info("  5. Check logs: [bold]journalctl --user -u immich-server.service -f[/]")
        return True
    else:
        log.warning("[yellow]No changes were applied[/]")
        return False


def main() -> None:
    """Main execution function"""
    global DRY_RUN, DEBUG

    parser = argparse.ArgumentParser(
        description="Automated Immich version upgrades for Podman quadlet configs",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  ./upgrade-immich.py v2.2.3           # Upgrade to v2.2.3
  ./upgrade-immich.py v2.2.3 -n        # Dry run upgrade
  ./upgrade-immich.py --list-versions  # List supported versions

IMPORTANT: Run 'just backup-immich' before upgrading!
        """
    )
    parser.add_argument("target_version", nargs="?", help="Target version to upgrade to (e.g., v2.2.3)")
    parser.add_argument("--list-versions", action="store_true", help="List supported upgrade paths")
    parser.add_argument("-n", "--dry-run", action="store_true", help="Dry run; show what would be done")
    parser.add_argument("-d", "--debug", action="store_true", help="Show debug information")

    args = parser.parse_args()

    DRY_RUN = args.dry_run
    DEBUG = args.debug

    # Set log level based on debug flag
    if not DEBUG:
        log.setLevel("INFO")

    console.log(Panel("upgrade-immich.py", style="bold green"))

    if DRY_RUN:
        console.log(Panel("DRY RUN MODE", style="bold yellow"))

    # Handle list versions
    if args.list_versions:
        list_supported_versions()
        return

    # Require target version
    if not args.target_version:
        parser.print_help()
        sys.exit(1)

    # Perform upgrade
    success = upgrade_to_version(args.target_version)

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.log("\n[yellow]Interrupted by user[/]")
        sys.exit(130)
    except Exception as e:
        console.log(f"\n[red bold]Error:[/] {e}")
        if DEBUG:
            raise
        sys.exit(1)
