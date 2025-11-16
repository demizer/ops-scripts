#!/usr/bin/env python3
"""
manage-backups.py - Backup management for containerized services

Handles backup and restore operations for Immich and other services.

Usage:
    ./manage-backups.py backup-immich           # Backup all Immich data
    ./manage-backups.py backup-immich -n        # Dry run
    ./manage-backups.py backup-immich -d        # Debug output
    ./manage-backups.py restore-immich DATE     # Restore from specific backup
    ./manage-backups.py list-backups            # List available backups

Features:
* Backs up database, volumes, caches, and configs
* Timestamped backup directories
* Compression support
* Dry run mode for testing
* Beautiful console output with Rich
"""

# /// script
# dependencies = [
#     "rich>=13.0.0",
# ]
# ///

import argparse
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn

# Import common utilities
import setup_common

# Backup configuration
BACKUP_BASE = Path("/mnt/backups/immich")
DATABASE_BACKUP_DIR = BACKUP_BASE / "database"
CACHES_BACKUP_DIR = BACKUP_BASE / "caches"
VOLUMES_BACKUP_DIR = BACKUP_BASE / "volumes"
CONFIG_BACKUP_DIR = BACKUP_BASE / "config"

# Container/volume names
IMMICH_DATABASE_CONTAINER = "immich-database"
IMMICH_MODEL_CACHE_VOLUME = "immich-model-cache"
IMMICH_DATABASE_VOLUME = "immich-database"

# Config source
CONFIG_SOURCE_DIR = Path.home() / ".config" / "containers" / "systemd"

# Global options
DRY_RUN = False
DEBUG = False

# Use console and log from setup_common
console = setup_common.console
log = setup_common.log


def ensure_backup_dirs() -> None:
    """Ensure all backup directories exist"""
    for backup_dir in [DATABASE_BACKUP_DIR, CACHES_BACKUP_DIR, VOLUMES_BACKUP_DIR, CONFIG_BACKUP_DIR]:
        setup_common.ensure_dir_exists(backup_dir, dry_run=DRY_RUN)


def get_timestamp() -> str:
    """Get timestamp for backup directory"""
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def compress_file(file_path: Path) -> None:
    """Compress a file using gzip"""
    if DRY_RUN:
        log.info(f"[yellow]NORUN:[/] [dim]gzip '{file_path}'[/]")
        return

    log.info(f"[blue]Compressing[/] [bold]{file_path}[/]")
    result = subprocess.run(["gzip", "-f", str(file_path)], capture_output=True, text=True)

    if result.returncode != 0:
        log.error(f"[red]Failed to compress {file_path}:[/] {result.stderr}")
        sys.exit(1)


def backup_database(timestamp: str) -> Path:
    """Backup Immich PostgreSQL database"""
    console.log(Panel("DATABASE BACKUP", style="bold blue"))

    backup_file = DATABASE_BACKUP_DIR / f"immich-database-{timestamp}.sql"

    log.info(f"[blue]Backing up database to[/] [bold cyan]{backup_file}[/]")

    if DRY_RUN:
        log.warning(f"[yellow]NORUN:[/] [dim]podman exec {IMMICH_DATABASE_CONTAINER} pg_dump -U postgres immich > {backup_file}[/]")
        return backup_file

    # Execute pg_dump
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        task = progress.add_task("Dumping database...", total=None)

        result = subprocess.run(
            ["podman", "exec", IMMICH_DATABASE_CONTAINER, "pg_dump", "-U", "postgres", "immich"],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            log.error(f"[red]Database backup failed:[/] {result.stderr}")
            sys.exit(1)

        # Write to file
        backup_file.write_text(result.stdout)
        progress.update(task, completed=True)

    log.info(f"[green]Database backup completed:[/] [bold]{backup_file}[/]")

    # Compress the backup
    compress_file(backup_file)
    compressed_file = Path(str(backup_file) + ".gz")

    # Show size
    if compressed_file.exists():
        size_mb = compressed_file.stat().st_size / (1024 * 1024)
        log.info(f"[green]Compressed size:[/] [bold]{size_mb:.2f} MB[/]")

    return compressed_file


def backup_volume(volume_name: str, backup_dir: Path, timestamp: str, description: str) -> Path:
    """Backup a Podman volume"""
    backup_file = backup_dir / f"{volume_name}-{timestamp}.tar"

    log.info(f"[blue]Backing up {description}:[/] [bold cyan]{volume_name}[/]")

    if DRY_RUN:
        log.warning(f"[yellow]NORUN:[/] [dim]podman volume export {volume_name} -o {backup_file}[/]")
        return backup_file

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        task = progress.add_task(f"Exporting {description}...", total=None)

        result = subprocess.run(
            ["podman", "volume", "export", volume_name, "-o", str(backup_file)],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            log.error(f"[red]Volume backup failed:[/] {result.stderr}")
            sys.exit(1)

        progress.update(task, completed=True)

    log.info(f"[green]Volume backup completed:[/] [bold]{backup_file}[/]")

    # Compress the backup
    compress_file(backup_file)
    compressed_file = Path(str(backup_file) + ".gz")

    # Show size
    if compressed_file.exists():
        size_mb = compressed_file.stat().st_size / (1024 * 1024)
        log.info(f"[green]Compressed size:[/] [bold]{size_mb:.2f} MB[/]")

    return compressed_file


def backup_configs(timestamp: str) -> Path:
    """Backup container configuration files"""
    console.log(Panel("CONFIGURATION BACKUP", style="bold blue"))

    backup_dir = CONFIG_BACKUP_DIR / timestamp
    setup_common.ensure_dir_exists(backup_dir, dry_run=DRY_RUN)

    log.info(f"[blue]Backing up configs to[/] [bold cyan]{backup_dir}[/]")

    # Find all immich-related config files
    config_files = list(CONFIG_SOURCE_DIR.glob("immich*"))

    if not config_files:
        log.warning("[yellow]No Immich config files found[/]")
        return backup_dir

    log.info(f"[blue]Found[/] [bold]{len(config_files)}[/] [blue]config files[/]")

    for config_file in config_files:
        dest_file = backup_dir / config_file.name

        if DRY_RUN:
            log.warning(f"[yellow]NORUN:[/] [dim]cp '{config_file}' '{dest_file}'[/]")
        else:
            log.debug(f"Copying {config_file.name}")
            dest_file.write_text(config_file.read_text())

    log.info(f"[green]Config backup completed:[/] [bold]{backup_dir}[/]")

    return backup_dir


def backup_immich() -> None:
    """Perform complete Immich backup"""
    console.log(Panel("IMMICH BACKUP STARTED", style="bold green"))

    timestamp = get_timestamp()
    log.info(f"[cyan]Backup timestamp:[/] [bold]{timestamp}[/]")

    # Ensure backup directories exist
    ensure_backup_dirs()

    # 1. Backup database
    db_backup = backup_database(timestamp)

    # 2. Backup model cache
    console.log(Panel("CACHE BACKUP", style="bold blue"))
    cache_backup = backup_volume(
        IMMICH_MODEL_CACHE_VOLUME,
        CACHES_BACKUP_DIR,
        timestamp,
        "model cache"
    )

    # 3. Backup database volume
    console.log(Panel("VOLUME BACKUP", style="bold blue"))
    volume_backup = backup_volume(
        IMMICH_DATABASE_VOLUME,
        VOLUMES_BACKUP_DIR,
        timestamp,
        "database volume"
    )

    # 4. Backup configs
    config_backup = backup_configs(timestamp)

    # Summary
    console.log(Panel("BACKUP SUMMARY", style="bold green"))
    log.info(f"[green]✓ Database:[/] [bold]{db_backup}[/]")
    log.info(f"[green]✓ Cache:[/] [bold]{cache_backup}[/]")
    log.info(f"[green]✓ Volume:[/] [bold]{volume_backup}[/]")
    log.info(f"[green]✓ Config:[/] [bold]{config_backup}[/]")

    log.info(f"[bold green]{datetime.now().strftime('%c')}[/] [green]::[/] [bold bright_green]Backup Complete![/]")


def list_backups() -> None:
    """List available backups"""
    console.log(Panel("AVAILABLE BACKUPS", style="bold blue"))

    if not BACKUP_BASE.exists():
        log.warning(f"[yellow]Backup directory does not exist:[/] [bold]{BACKUP_BASE}[/]")
        return

    # Get all timestamped backups
    timestamps = set()

    for backup_dir in [DATABASE_BACKUP_DIR, CACHES_BACKUP_DIR, VOLUMES_BACKUP_DIR]:
        if backup_dir.exists():
            for file in backup_dir.glob("*"):
                # Extract timestamp from filename (format: name-YYYYMMDD-HHMMSS.ext)
                parts = file.stem.split("-")
                if len(parts) >= 3:
                    timestamp = f"{parts[-2]}-{parts[-1]}"
                    timestamps.add(timestamp)

    if not timestamps:
        log.info("[yellow]No backups found[/]")
        return

    log.info(f"[blue]Found[/] [bold]{len(timestamps)}[/] [blue]backup(s)[/]")

    for timestamp in sorted(timestamps, reverse=True):
        log.info(f"  [cyan]•[/] [bold]{timestamp}[/]")

        # Show what exists for this timestamp
        db_file = DATABASE_BACKUP_DIR / f"immich-database-{timestamp}.sql.gz"
        cache_file = CACHES_BACKUP_DIR / f"{IMMICH_MODEL_CACHE_VOLUME}-{timestamp}.tar.gz"
        volume_file = VOLUMES_BACKUP_DIR / f"{IMMICH_DATABASE_VOLUME}-{timestamp}.tar.gz"

        if db_file.exists():
            size_mb = db_file.stat().st_size / (1024 * 1024)
            log.info(f"    [dim]Database: {size_mb:.2f} MB[/]")
        if cache_file.exists():
            size_mb = cache_file.stat().st_size / (1024 * 1024)
            log.info(f"    [dim]Cache: {size_mb:.2f} MB[/]")
        if volume_file.exists():
            size_mb = volume_file.stat().st_size / (1024 * 1024)
            log.info(f"    [dim]Volume: {size_mb:.2f} MB[/]")


def main() -> None:
    """Main execution function"""
    global DRY_RUN, DEBUG

    parser = argparse.ArgumentParser(description="Backup management for containerized services")
    parser.add_argument("command", choices=["backup-immich", "list-backups"], help="Command to execute")
    parser.add_argument("-n", "--dry-run", action="store_true", help="Dry run; show what would be done")
    parser.add_argument("-d", "--debug", action="store_true", help="Show debug information")

    args = parser.parse_args()

    DRY_RUN = args.dry_run
    DEBUG = args.debug

    # Set log level based on debug flag
    if not DEBUG:
        log.setLevel("INFO")

    console.log(Panel(f"manage-backups.py - {args.command}", style="bold green"))

    if DRY_RUN:
        console.log(Panel("DRY RUN MODE", style="bold yellow"))

    # Execute command
    if args.command == "backup-immich":
        backup_immich()
    elif args.command == "list-backups":
        list_backups()


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
