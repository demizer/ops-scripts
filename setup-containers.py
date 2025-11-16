#!/usr/bin/env python3
"""
setup-containers.py - Deploy container systemd units using Python with Rich console output

Deploys container configuration files and manages systemd services.

Usage:
    ./setup-containers.py          # Run setup
    ./setup-containers.py -n       # Dry run
    ./setup-containers.py -d       # Debug output
    ./setup-containers.py -h       # Help
    ./setup-containers.py -s       # Sync changes back to source

Features:
* Copies container systemd units to their destinations
* Shows diff when files differ, allowing user to choose whether to overwrite
* Syncs changes back to source directory when requested
* Stops and starts containers after updates
* Dry run mode for testing changes
* Beautiful console output with Rich
"""

# /// script
# dependencies = [
#     "rich>=13.0.0",
# ]
# ///

import argparse
import sys
from pathlib import Path

from rich.panel import Panel

# Import common utilities
import setup_common

# Global configuration
SCRIPT_DIR = Path(__file__).parent.absolute()
CONTAINERS_DIR = SCRIPT_DIR / "hosts" / "ops" / "containers"
DEST_DIR = Path.home() / ".config" / "containers" / "systemd"

# Global options
DRY_RUN = False
DEBUG = False
SYNC_MODE = False

# Use console and log from setup_common
console = setup_common.console
log = setup_common.log


def ensure_user_lingering() -> None:
    """Ensure user lingering is enabled for persistent user services"""
    import getpass
    username = getpass.getuser()

    log.info("[blue]Checking user lingering...[/]", stacklevel=2)

    # Check if lingering is already enabled
    linger_file = Path(f"/var/lib/systemd/linger/{username}")

    if linger_file.exists():
        log.info(f"[dim]User lingering already enabled for {username}[/]", stacklevel=2)
        return

    log.info(f"[yellow]Enabling user lingering for {username}...[/]", stacklevel=2)
    exit_code = setup_common.run_cmd(["sudo", "loginctl", "enable-linger", username], dry_run=DRY_RUN)

    if exit_code != 0:
        log.error("[red]Failed to enable user lingering[/]", stacklevel=2)
        sys.exit(1)


def daemon_reload() -> None:
    """Reload systemd user daemon"""
    log.info("[blue]Reloading systemd user daemon[/]", stacklevel=2)
    setup_common.run_cmd(["systemctl", "--user", "daemon-reload"], dry_run=DRY_RUN)


def setup_containers() -> None:
    """Setup container systemd units"""
    console.log(Panel("CONTAINER SYSTEMD UNITS", style="bold green"))

    # Ensure user lingering is enabled for persistent services
    ensure_user_lingering()

    setup_common.ensure_dir_exists(DEST_DIR, dry_run=DRY_RUN)

    # Get all container files (including subdirectories)
    container_files = sorted(CONTAINERS_DIR.glob("**/*.container"))
    pod_files = sorted(CONTAINERS_DIR.glob("**/*.pod"))
    network_files = sorted(CONTAINERS_DIR.glob("**/*.network"))

    all_files = container_files + pod_files + network_files

    if not all_files:
        log.error(f"[red]No container files found in[/] [bold]{CONTAINERS_DIR}[/]", stacklevel=2)
        sys.exit(1)

    log.info(f"[blue]Found[/] [bold]{len(all_files)}[/] [blue]files to deploy[/]", stacklevel=2)

    # Identify pod services from .pod files
    # Note: immich.pod becomes immich-pod.service (quadlet adds -pod suffix)
    pod_services = [p.stem + "-pod.service" for p in pod_files]

    # Identify standalone containers (not part of any pod)
    # These are .container files that don't have a matching .pod file in the same directory
    standalone_containers = []
    for container_file in container_files:
        # Check if this container is in the immich subdirectory (part of immich pod)
        if "immich" in str(container_file.parent):
            continue  # Skip containers that are part of immich pod
        standalone_containers.append(container_file)

    standalone_services = [c.stem + ".service" for c in standalone_containers]

    # Track which units were updated
    updated_units = []

    # Stop pod services (use systemd for quadlet-managed pods)
    if pod_services:
        log.info("[yellow]Stopping pod services...[/]", stacklevel=2)
        for service in pod_services:
            log.info(f"[yellow]Stopping:[/] [bold]{service}[/]", stacklevel=2)
            setup_common.run_cmd(["systemctl", "--user", "stop", service], dry_run=DRY_RUN)

    # Stop standalone container services
    if standalone_services:
        log.info("[yellow]Stopping standalone containers...[/]", stacklevel=2)
        for service in standalone_services:
            log.info(f"[yellow]Stopping:[/] [bold]{service}[/]", stacklevel=2)
            setup_common.run_cmd(["systemctl", "--user", "stop", service], dry_run=DRY_RUN)

    # Copy files
    for file in all_files:
        dest = DEST_DIR / file.name
        log.info(f"[bold blue]Processing:[/] [cyan]{file.name}[/]", stacklevel=2)

        if setup_common.ensure_copy(file, dest, dry_run=DRY_RUN):
            updated_units.append(file.name)

    # Reload systemd daemon
    daemon_reload()

    # Start pod services (use systemd for quadlet-managed pods)
    if pod_services:
        log.info("[green]Starting pod services...[/]", stacklevel=2)
        for service in pod_services:
            log.info(f"[green]Starting:[/] [bold]{service}[/]", stacklevel=2)
            setup_common.run_cmd(["systemctl", "--user", "start", service], dry_run=DRY_RUN)

    # Start standalone container services
    if standalone_services:
        log.info("[green]Starting standalone containers...[/]", stacklevel=2)
        for service in standalone_services:
            log.info(f"[green]Starting:[/] [bold]{service}[/]", stacklevel=2)
            setup_common.run_cmd(["systemctl", "--user", "start", service], dry_run=DRY_RUN)

    if updated_units:
        log.info(f"[green]Updated[/] [bold]{len(updated_units)}[/] [green]units[/]", stacklevel=2)
    else:
        log.info("[green]No units needed updating[/]", stacklevel=2)


def sync_containers_back() -> None:
    """Sync container files back from destination to source"""
    console.log(Panel("SYNCING BACK", style="bold green"))

    synced_count = 0

    log.info("[bold yellow]Checking for changes to sync back to source...[/]", stacklevel=2)

    # Get all files in destination
    if not DEST_DIR.exists():
        log.error(f"[red]Destination directory does not exist:[/] [bold]{DEST_DIR}[/]", stacklevel=2)
        sys.exit(1)

    dest_files = sorted(DEST_DIR.glob("*.container")) + sorted(DEST_DIR.glob("*.pod")) + sorted(DEST_DIR.glob("*.network"))

    # Get all source files to find matching destination
    source_files = sorted(CONTAINERS_DIR.glob("**/*.container")) + sorted(CONTAINERS_DIR.glob("**/*.pod")) + sorted(CONTAINERS_DIR.glob("**/*.network"))
    source_map = {f.name: f for f in source_files}

    for dest_file in dest_files:
        source_file = source_map.get(dest_file.name)
        if source_file:
            if setup_common.sync_file_back(dest_file, source_file, dest_file.name, dry_run=DRY_RUN):
                synced_count += 1
        else:
            log.warning(f"[yellow]No source file found for:[/] [bold]{dest_file.name}[/]")

    if synced_count > 0:
        log.info(f"[green]Synced[/] [bold]{synced_count}[/] [green]files back to source directory[/]", stacklevel=2)
        log.info("[cyan]You may want to commit these changes:[/]", stacklevel=2)
        log.info(f"[dim]cd '{SCRIPT_DIR}' && git add hosts/ops/containers/ && git commit -m 'Update containers from deployed system'[/]", stacklevel=2)
    else:
        log.info("[green]No files needed syncing[/]", stacklevel=2)


def main() -> None:
    """Main execution function"""
    global DRY_RUN, DEBUG, SYNC_MODE

    parser = argparse.ArgumentParser(description="Deploy container systemd units using Python with Rich console output")
    parser.add_argument("-n", "--dry-run", action="store_true", help="Dry run; output commands but don't execute")
    parser.add_argument("-d", "--debug", action="store_true", help="Show debug information")
    parser.add_argument("-s", "--sync", action="store_true", help="Sync mode; sync changes from destination back to source")

    args = parser.parse_args()

    DRY_RUN = args.dry_run
    DEBUG = args.debug
    SYNC_MODE = args.sync

    # Set log level based on debug flag
    if not DEBUG:
        log.setLevel("INFO")

    console.log(Panel(f"setup-containers.py started", style="bold green"))

    log.debug(f"SCRIPT_DIR: {SCRIPT_DIR}")
    log.debug(f"CONTAINERS_DIR: {CONTAINERS_DIR}")
    log.debug(f"DEST_DIR: {DEST_DIR}")

    if SYNC_MODE:
        console.log(Panel("SYNC MODE", style="bold green"))
    else:
        console.log(Panel("DEPLOY MODE", style="bold green"))

    # Main logic
    if SYNC_MODE:
        sync_containers_back()
    else:
        setup_containers()

    from datetime import datetime
    log.info(f"[bold green]{datetime.now().strftime('%c')}[/] [green]::[/] [bold bright_green]All Done![/]", stacklevel=2)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.log("\n[yellow]Interrupted by user[/]")
        sys.exit(130)
