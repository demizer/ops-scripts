"""
setup_common.py - Common utilities for setup scripts

Shared functions used by setup-dotfiles.py, setup-containers.py, etc.
"""

import difflib
import logging
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from rich.console import Console
from rich.logging import RichHandler
from rich.panel import Panel
from rich.prompt import Confirm
from rich.syntax import Syntax
from rich.theme import Theme

# Create custom theme with specific colors for log levels
custom_theme = Theme({
    "logging.level.debug": "cyan",
    "logging.level.info": "green",
    "logging.level.warning": "yellow",
    "logging.level.error": "red bold",
    "logging.level.critical": "red on white bold"
})

# Create console with custom theme
console = Console(theme=custom_theme)

# Use themed console in RichHandler with markup enabled
handler = RichHandler(console=console, markup=True)

logging.basicConfig(
    level="DEBUG",
    format="%(message)s",
    handlers=[handler]
)

log = logging.getLogger(__name__)


def run_cmd(cmd: list[str], dry_run: bool = False) -> int:
    """Execute command with output"""
    if dry_run:
        log.warning(f"[yellow]NORUN:[/] [dim]{' '.join(cmd)}[/]", stacklevel=2)
        return 0
    else:
        log.info(f"[bold green]Running command:[/] [cyan]{' '.join(cmd)}[/]", stacklevel=2)

        result = subprocess.run(cmd, capture_output=False, text=True)
        exit_code = result.returncode

        log.info(f"[bold]Command returned:[/] [green]{exit_code}[/]" if exit_code == 0 else f"[bold]Command returned:[/] [red]{exit_code}[/]", stacklevel=2)
        return exit_code


def run_cmd_quiet(cmd: list[str], dry_run: bool = False) -> int:
    """Execute command quietly"""
    if dry_run:
        log.warning(f"[yellow]NORUN:[/] [dim]{' '.join(cmd)}[/]", stacklevel=2)
        return 0
    else:
        log.info(f"[bold green]Running command:[/] [cyan]{' '.join(cmd)}[/]", stacklevel=2)

        result = subprocess.run(cmd, capture_output=True, text=True)
        exit_code = result.returncode

        log.info(f"[bold]Command returned:[/] [green]{exit_code}[/]" if exit_code == 0 else f"[bold]Command returned:[/] [red]{exit_code}[/]", stacklevel=2)

        if exit_code != 0:
            log.error(f"[bold red]Command failed with exit code[/] [red on white]{exit_code}[/]", stacklevel=2)
            if result.stderr:
                log.error(result.stderr, stacklevel=2)
            sys.exit(1)

        return exit_code


def run_cmd_quiet_check(cmd: list[str], dry_run: bool = False) -> int:
    """Execute command quietly and return exit code without failing"""
    if dry_run:
        log.warning(f"[yellow]NORUN:[/] [dim]{' '.join(cmd)}[/]", stacklevel=2)
        return 0
    else:
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.returncode


def ensure_dir_exists(directory: Path, dry_run: bool = False) -> None:
    """Ensure directory exists"""
    if not directory.exists():
        log.info(f"[blue]Creating directory[/] [bold cyan]{directory}[/]", stacklevel=2)
        if not dry_run:
            directory.mkdir(parents=True, exist_ok=True)
        else:
            log.warning(f"[yellow]NORUN:[/] [dim]mkdir -p '{directory}'[/]", stacklevel=2)
    else:
        log.debug(f"Directory {directory} already exists", stacklevel=2)


def show_file_diff(source: Path, dest: Path, dry_run: bool = False) -> None:
    """Show diff between two files"""
    log.info(f"Showing diff between {source} and {dest}", stacklevel=2)

    if not dest.exists():
        log.warning(f"Destination file {dest} does not exist", stacklevel=2)
        return

    try:
        # Get modification times
        source_mtime = source.stat().st_mtime
        dest_mtime = dest.stat().st_mtime
        source_time = datetime.fromtimestamp(source_mtime).strftime('%Y-%m-%d %H:%M:%S')
        dest_time = datetime.fromtimestamp(dest_mtime).strftime('%Y-%m-%d %H:%M:%S')

        if source_mtime > dest_mtime:
            log.info(f"[cyan]Source[/] [bold]{source}[/] [cyan]is newer[/] [dim]({source_time})[/]", stacklevel=2)
            log.info(f"[cyan]Dest[/] [bold]{dest}[/] [cyan]is older[/] [dim]({dest_time})[/]", stacklevel=2)
        elif dest_mtime > source_mtime:
            log.info(f"[cyan]Dest[/] [bold]{dest}[/] [cyan]is newer[/] [dim]({dest_time})[/]", stacklevel=2)
            log.info(f"[cyan]Source[/] [bold]{source}[/] [cyan]is older[/] [dim]({source_time})[/]", stacklevel=2)
        else:
            log.info(f"[cyan]Both files have same modification time[/] [dim]({source_time})[/]", stacklevel=2)

        with open(source, 'r') as f:
            source_lines = f.readlines()
        with open(dest, 'r') as f:
            dest_lines = f.readlines()

        diff = list(difflib.unified_diff(
            dest_lines, source_lines,
            fromfile=str(dest), tofile=str(source),
            lineterm=''
        ))

        if diff:
            diff_text = '\n'.join(diff)
            syntax = Syntax(diff_text, "diff", theme="monokai", line_numbers=False)
            console.log(Panel(syntax, title="File Differences", border_style="bold blue"))
        else:
            console.log("Files are identical", style="green")

    except Exception as e:
        log.error(f"Could not show diff: {e}", stacklevel=2)


def ensure_copy(source: Path, dest: Path, dry_run: bool = False) -> bool:
    """
    Copy file from source to destination with checks.
    Returns True if file was copied, False otherwise.
    """
    log.debug(f"ensure_copy: source={source}, dest={dest}", stacklevel=2)

    if not source.exists():
        log.error(f"[bold red]Source file does not exist:[/] [red]{source}[/]", stacklevel=2)
        sys.exit(1)

    should_copy = False

    if dest.is_symlink():
        current_target = dest.readlink()
        log.info(f"[magenta]Replacing symlink[/] [bold]{dest}[/] [dim](currently points to {current_target})[/]", stacklevel=2)
        log.debug(f"ensure_copy: Removing existing symlink: {dest}", stacklevel=2)
        if not dry_run:
            dest.unlink()
        should_copy = True
    elif dest.exists():
        # Check if files are different
        if source.read_bytes() == dest.read_bytes():
            log.debug(f"File {dest} already exists and matches source", stacklevel=2)
            return False
        else:
            log.warning(f"[yellow]File[/] [bold]'{dest}'[/] [yellow]exists but differs from source.[/]", stacklevel=2)
            show_file_diff(source, dest, dry_run)

            if dry_run:
                # In dry-run mode, assume we would copy
                should_copy = True
            elif Confirm.ask("Copy source file over destination?", default=False):
                should_copy = True
            else:
                log.info(f"[dim]Skipping copy of[/] [bold]{dest}[/]", stacklevel=2)
                return False
    else:
        log.info(f"[blue]File[/] [bold]{dest}[/] [blue]does not exist, will create[/]", stacklevel=2)
        should_copy = True

    if should_copy:
        log.info(f"[green]Copying[/] [bold cyan]{source}[/] [green]to[/] [bold cyan]{dest}[/]", stacklevel=2)
        # Ensure parent directory exists
        ensure_dir_exists(dest.parent, dry_run)

        if dry_run:
            log.warning(f"[yellow]NORUN:[/] [dim]cp '{source}' '{dest}'[/]", stacklevel=2)
        else:
            shutil.copy2(source, dest)
        return True

    return False


def detect_file_changes(file1: Path, file2: Path) -> bool:
    """Detect if files have changed"""
    if not file1.exists():
        log.debug(f"File does not exist: {file1}", stacklevel=2)
        return False

    if not file2.exists():
        log.debug(f"File does not exist: {file2}", stacklevel=2)
        return False

    # Compare files
    if file1.read_bytes() == file2.read_bytes():
        log.debug(f"Files are identical: {file1} and {file2}", stacklevel=2)
        return False
    else:
        log.debug(f"Files differ: {file1} and {file2}", stacklevel=2)
        return True


def sync_file_back(home_file: Path, dotfiles_file: Path, description: str, dry_run: bool = False) -> bool:
    """Sync file back from home to dotfiles"""
    if detect_file_changes(home_file, dotfiles_file):
        log.warning(f"[yellow]File[/] [bold]'{description}'[/] [yellow]has changed in home directory[/]", stacklevel=2)
        show_file_diff(dotfiles_file, home_file, dry_run)

        if dry_run or Confirm.ask("Sync changes back to dotfiles?", default=False):
            log.info(f"[green]Syncing[/] [bold cyan]{home_file}[/] [green]back to[/] [bold cyan]{dotfiles_file}[/]", stacklevel=2)
            if dry_run:
                log.warning(f"[yellow]NORUN:[/] [dim]cp '{home_file}' '{dotfiles_file}'[/]", stacklevel=2)
            else:
                shutil.copy2(home_file, dotfiles_file)
            return True
        else:
            log.info(f"[dim]Skipping sync of[/] [bold]{description}[/]", stacklevel=2)
    return False
