#!/usr/bin/env python3
"""
setup-dotfiles.py - Deploy dotfiles using Python with Rich console output

Replaces the functionality of setup-dotfiles.fish but with better error handling
and beautiful console output using Rich.

Usage:
    ./setup-dotfiles.py          # Run setup
    ./setup-dotfiles.py -n       # Dry run
    ./setup-dotfiles.py -d       # Debug output
    ./setup-dotfiles.py -h       # Help
    ./setup-dotfiles.py -s       # Sync changes back to dotfiles

Features:
* Copies dotfiles to their destinations
* Shows diff when files differ, allowing user to choose whether to overwrite
* Syncs changes back to dotfiles directory when requested
* Host-specific configurations for work/personal setups
* Dry run mode for testing changes
* Beautiful console output with Rich
"""

# /// script
# dependencies = [
#     "rich>=13.0.0",
# ]
# ///

import argparse
import difflib
import json
import logging
import shutil
import socket
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from rich.console import Console
from rich.logging import RichHandler
from rich.panel import Panel
from rich.prompt import Confirm
from rich.syntax import Syntax
from rich.text import Text
from rich.theme import Theme

# Global configuration
SCRIPT_DIR = Path(__file__).parent.absolute()
DOTFILES_DIR = SCRIPT_DIR / "dotfiles"
SETUP_HOST = socket.gethostname()

# Host configuration
WORK_HOSTS = ["jesusa-lt", "jesusa-desktop", "jesusa-ws-fc29", "jump.km.nvidia.com", "jesusa-fridge"]
WORK_LT = "jesusa-lt"
PERS_LT = "neon"

# Global options
DRY_RUN = False
DEBUG = False
SYNC_MODE = False

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


def run_cmd(cmd: list[str]) -> int:
    """Execute command with output"""
    if DRY_RUN:
        log.warning(f"[yellow]NORUN:[/] [dim]{' '.join(cmd)}[/]", stacklevel=2)
        return 0
    else:
        log.info(f"[bold green]Running command:[/] [cyan]{' '.join(cmd)}[/]", stacklevel=2)

        result = subprocess.run(cmd, capture_output=False, text=True)
        exit_code = result.returncode

        log.info(f"[bold]Command returned:[/] [green]{exit_code}[/]" if exit_code == 0 else f"[bold]Command returned:[/] [red]{exit_code}[/]", stacklevel=2)
        return exit_code


def run_cmd_quiet(cmd: list[str]) -> int:
    """Execute command quietly"""
    if DRY_RUN:
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


def ensure_dir_exists(directory: Path) -> None:
    """Ensure directory exists"""
    if not directory.exists():
        log.info(f"[blue]Creating directory[/] [bold cyan]{directory}[/]", stacklevel=2)
        if not DRY_RUN:
            directory.mkdir(parents=True, exist_ok=True)
        else:
            log.warning(f"[yellow]NORUN:[/] [dim]mkdir -p '{directory}'[/]", stacklevel=2)
    else:
        log.debug(f"Directory {directory} already exists", stacklevel=2)


def file_exists(file_path: Path) -> bool:
    """Check if file exists"""
    return file_path.is_file()


def check_lazy_lock_diff(source: Path, dest: Path) -> str:
    """
    Check if the only difference between two lazy-lock.json files is the lazy.nvim plugin.
    Returns:
        'identical' - files are identical
        'only-lazy' - only lazy.nvim differs
        'other-changes' - other plugins differ
        'error' - couldn't parse or compare
    """
    try:
        with open(source, 'r') as f:
            source_data = json.load(f)
        with open(dest, 'r') as f:
            dest_data = json.load(f)

        if source_data == dest_data:
            return 'identical'

        # Get all keys from both files
        all_keys = set(source_data.keys()) | set(dest_data.keys())

        # Track which keys differ
        differing_keys = []
        for key in all_keys:
            if source_data.get(key) != dest_data.get(key):
                differing_keys.append(key)

        # If only lazy.nvim differs
        if differing_keys == ['lazy.nvim']:
            return 'only-lazy'
        else:
            return 'other-changes'

    except Exception as e:
        log.debug(f"Error checking lazy lock diff: {e}")
        return 'error'


def show_file_diff(source: Path, dest: Path) -> None:
    """Show diff between two files"""
    log.info(f"Showing diff between {source} and {dest}", stacklevel=2)

    if DRY_RUN:
        log.warning("NORUN: show diff between files", stacklevel=2)
        return

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


def ensure_copy(source: Path, dest: Path) -> None:
    """Copy file from source to destination with checks"""
    log.debug(f"ensure_copy: source={source}, dest={dest}", stacklevel=2)

    if not source.exists():
        log.error(f"[bold red]Source file does not exist:[/] [red]{source}[/]", stacklevel=2)
        sys.exit(1)

    should_copy = False

    if dest.is_symlink():
        current_target = dest.readlink()
        log.info(f"[magenta]Replacing symlink[/] [bold]{dest}[/] [dim](currently points to {current_target})[/]", stacklevel=2)
        log.debug(f"ensure_copy: Removing existing symlink: {dest}", stacklevel=2)
        if not DRY_RUN:
            dest.unlink()
        should_copy = True
    elif dest.exists():
        # Check if files are different
        if source.read_bytes() == dest.read_bytes():
            log.debug(f"File {dest} already exists and matches source", stacklevel=2)
            return
        else:
            log.warning(f"[yellow]File[/] [bold]'{dest}'[/] [yellow]exists but differs from source.[/]", stacklevel=2)
            show_file_diff(source, dest)

            if Confirm.ask("Copy source file over destination?", default=False):
                should_copy = True
            else:
                log.info(f"[dim]Skipping copy of[/] [bold]{dest}[/]", stacklevel=2)
                return
    else:
        log.info(f"[blue]File[/] [bold]{dest}[/] [blue]does not exist, will create[/]", stacklevel=2)
        should_copy = True

    if should_copy:
        log.info(f"[green]Copying[/] [bold cyan]{source}[/] [green]to[/] [bold cyan]{dest}[/]", stacklevel=2)
        # Ensure parent directory exists
        ensure_dir_exists(dest.parent)

        if DRY_RUN:
            log.warning(f"[yellow]NORUN:[/] [dim]cp '{source}' '{dest}'[/]", stacklevel=2)
        else:
            shutil.copy2(source, dest)


def is_work_host(hostname: str) -> bool:
    """Check if hostname is a work host"""
    return any(work_host in hostname for work_host in WORK_HOSTS)


def detect_file_changes(home_file: Path, dotfiles_file: Path) -> bool:
    """Detect if files have changed"""
    if not home_file.exists():
        log.debug(f"Home file does not exist: {home_file}", stacklevel=2)
        return False

    if not dotfiles_file.exists():
        log.debug(f"Dotfiles file does not exist: {dotfiles_file}", stacklevel=2)
        return False

    # Compare files
    if home_file.read_bytes() == dotfiles_file.read_bytes():
        log.debug(f"Files are identical: {home_file} and {dotfiles_file}", stacklevel=2)
        return False
    else:
        log.debug(f"Files differ: {home_file} and {dotfiles_file}", stacklevel=2)
        return True


def sync_file_back(home_file: Path, dotfiles_file: Path, description: str) -> bool:
    """Sync file back from home to dotfiles"""
    if detect_file_changes(home_file, dotfiles_file):
        log.warning(f"[yellow]File[/] [bold]'{description}'[/] [yellow]has changed in home directory[/]", stacklevel=2)
        show_file_diff(dotfiles_file, home_file)

        if Confirm.ask("Sync changes back to dotfiles?", default=False):
            log.info(f"[green]Syncing[/] [bold cyan]{home_file}[/] [green]back to[/] [bold cyan]{dotfiles_file}[/]", stacklevel=2)
            if DRY_RUN:
                log.warning(f"[yellow]NORUN:[/] [dim]cp '{home_file}' '{dotfiles_file}'[/]", stacklevel=2)
            else:
                shutil.copy2(home_file, dotfiles_file)
            return True
        else:
            log.info(f"[dim]Skipping sync of[/] [bold]{description}[/]", stacklevel=2)
    return False


def setup_general_dotfiles() -> None:
    """Setup general dotfiles"""
    console.log(Panel("GENERAL DOTFILES", style="bold green"))

    home = Path.home()

    if is_work_host(SETUP_HOST):
        log.info("[bold blue]Setup gitconfig[/] [yellow](work)[/]")
        ensure_copy(DOTFILES_DIR / "gitconfig-work", home / ".gitconfig")
    else:
        log.info("[bold blue]Setup gitconfig[/]")
        ensure_copy(DOTFILES_DIR / "gitconfig", home / ".gitconfig")

        log.info("[bold blue]Setup abcde.conf[/]")
        ensure_copy(DOTFILES_DIR / "abcde.conf", home / ".abcde.conf")

    if "km.nvidia.com" not in SETUP_HOST:
        ensure_copy(DOTFILES_DIR / "pypi.rc", home / ".pypi.rc")
        ensure_copy(DOTFILES_DIR / "language-server.json", home / ".config" / "language-server.json")

        msmtprc_dest = home / ".msmtprc"
        ensure_copy(DOTFILES_DIR / "msmtprc", msmtprc_dest)
        if not DRY_RUN:
            msmtprc_dest.chmod(0o600)
        else:
            log.warning(f"[yellow]NORUN:[/] [dim]chmod 600 '{msmtprc_dest}'[/]")


def setup_fish_dotfiles() -> None:
    """Setup fish shell dotfiles"""
    console.log(Panel("FISH DOTFILES", style="bold green"))

    home = Path.home()
    fish_config_dir = home / ".config" / "fish"
    fish_confd_dir = fish_config_dir / "conf.d"

    log.info("[bold blue]Setup fish config files[/]")
    ensure_dir_exists(fish_config_dir)
    ensure_dir_exists(fish_confd_dir)

    ensure_copy(DOTFILES_DIR / "fish-config.fish", fish_config_dir / "config.fish")
    ensure_copy(DOTFILES_DIR / "fish-config-linux.fish", fish_config_dir / "config-linux.fish")

    log.info("[bold blue]Setup fish conf.d files[/]")
    conf_files = [
        "mine-aliases-git.fish",
        "mine-arch-aliases.fish",
        "mine-python.fish",
        "mine-ssh.fish",
        "mine-work.fish"
    ]

    for conf_file in conf_files:
        ensure_copy(DOTFILES_DIR / f"fish-{conf_file}", fish_confd_dir / conf_file)

    # Check if fisher is installed
    log.info("[bold blue]Checking for fisher[/]")
    fisher_check_exit = run_cmd(["fish", "-c", "fisher -v > /dev/null 2>&1"])

    if fisher_check_exit != 0:
        log.info("[yellow]Fisher not installed, installing...[/]")
        # Download fisher installer
        fisher_url = "https://git.io/fisher"
        fisher_installer = "/tmp/fisher-install"

        log.info(f"[cyan]Downloading fisher from {fisher_url}[/]")
        run_cmd_quiet(["wget", "-q", "-O", fisher_installer, fisher_url])

        # Install fisher
        log.info("[cyan]Installing fisher[/]")
        run_cmd_quiet(["fish", "-c", f"source {fisher_installer} && fisher install jorgebucaran/fisher"])
        log.info("[green]Fisher installed successfully[/]")
    else:
        log.info("[green]Fisher is already installed[/]")

    # Install fish plugins
    log.info("[bold blue]Install fish plugins[/]")
    plugins = [
        "pure-fish/pure",
        "jethrokuan/z",
        "danhper/fish-ssh-agent"
    ]

    for plugin in plugins:
        log.info(f"[cyan]Installing plugin: {plugin}[/]")
        run_cmd_quiet(["fish", "-c", f"fisher install {plugin}"])
        log.info(f"[green]Plugin {plugin} installed successfully[/]")


def setup_kitty_dotfiles() -> None:
    """Setup kitty terminal dotfiles"""
    log.info("[bold blue]Setup kitty config[/]")
    home = Path.home()
    kitty_config_dir = home / ".config" / "kitty"
    ensure_dir_exists(kitty_config_dir)

    ensure_copy(DOTFILES_DIR / "kitty.conf", kitty_config_dir / "kitty.conf")


def setup_ssh_dotfiles() -> None:
    """Setup SSH dotfiles"""
    log.info("[bold blue]Setup SSH config[/]")
    home = Path.home()
    ssh_dir = home / ".ssh"
    ensure_dir_exists(ssh_dir)

    ssh_config = ssh_dir / "config"

    if is_work_host(SETUP_HOST):
        log.info("[bold blue]Setup SSH config[/] [yellow](work)[/]")
        ensure_copy(DOTFILES_DIR / "ssh-config-work", ssh_config)
    else:
        log.info("[bold blue]Setup SSH config[/]")
        ensure_copy(DOTFILES_DIR / "ssh-config", ssh_config)

    # Set appropriate permissions
    if not DRY_RUN:
        ssh_config.chmod(0o600)
    else:
        log.warning(f"[yellow]NORUN:[/] [dim]chmod 600 '{ssh_config}'[/]")


def setup_tmux_dotfiles() -> None:
    """Setup tmux dotfiles"""
    log.info("[bold blue]Setup tmux.conf[/]")
    home = Path.home()
    ensure_copy(DOTFILES_DIR / "tmux.conf", home / ".tmux.conf")


def setup_neovim_dotfiles() -> None:
    """Setup neovim dotfiles"""
    console.log(Panel("NEOVIM DOTFILES", style="bold green"))

    home = Path.home()
    nvim_config_dir = home / ".config" / "nvim"

    log.info("[bold blue]Creating Neovim configuration directory[/]")
    ensure_dir_exists(nvim_config_dir)

    # Create directories for backups, swapfiles, and undo
    for subdir in ["backups", "swapfiles", "undodir", "lazygit"]:
        ensure_dir_exists(nvim_config_dir / subdir)

    # Copy the existing neovim-init.lua as init.lua
    init_lua_path = nvim_config_dir / "init.lua"
    nvim_lua_path = DOTFILES_DIR / "neovim-init.lua"

    if nvim_lua_path.exists():
        log.info("[bold blue]Setup neovim-init.lua as init.lua[/]")
        ensure_copy(nvim_lua_path, init_lua_path)
    else:
        log.warning("[yellow]neovim-init.lua not found, creating minimal init.lua[/]")
        ensure_dir_exists(init_lua_path.parent)

        minimal_config = """-- Minimal Neovim configuration
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
"""

        if not DRY_RUN:
            init_lua_path.write_text(minimal_config)
        else:
            log.warning("[yellow]NORUN:[/] [dim]create minimal init.lua[/]")

    # Copy neovim-lazy-lock.json if it exists
    lazy_lock_src = DOTFILES_DIR / "neovim-lazy-lock.json"
    lazy_lock_dest = nvim_config_dir / "lazy-lock.json"
    if lazy_lock_src.exists():
        log.info("[bold blue]Setup lazy-lock.json[/]")

        # Check if destination exists and differs
        if lazy_lock_dest.exists():
            diff_type = check_lazy_lock_diff(lazy_lock_src, lazy_lock_dest)

            if diff_type == 'identical':
                log.debug("lazy-lock.json files are identical")
            elif diff_type == 'only-lazy':
                log.info("[cyan]The only difference is the lazy.nvim plugin version[/]")
                show_file_diff(lazy_lock_src, lazy_lock_dest)

                try:
                    if Confirm.ask("Update source dotfiles with newer lazy.nvim version?", default=True):
                        log.info(f"[green]Updating[/] [bold cyan]{lazy_lock_src}[/] [green]with[/] [bold cyan]{lazy_lock_dest}[/]")
                        if not DRY_RUN:
                            shutil.copy2(lazy_lock_dest, lazy_lock_src)
                        else:
                            log.warning(f"[yellow]NORUN:[/] [dim]cp '{lazy_lock_dest}' '{lazy_lock_src}'[/]")
                        return
                    else:
                        log.info("[dim]Will copy source over destination[/]")
                except KeyboardInterrupt:
                    log.info("\n[dim]Interrupted, skipping lazy-lock.json[/]")
                    return

            # If we got here, proceed with normal copy
            will_copy = lazy_lock_src.read_bytes() != lazy_lock_dest.read_bytes()
        else:
            will_copy = True

        # If we're going to copy a new lock file, delete the plugins directory
        if will_copy:
            lazy_plugins_dir = Path.home() / ".local" / "share" / "nvim" / "lazy"
            if lazy_plugins_dir.exists():
                log.info(f"[yellow]Deleting lazy plugins directory to force reinstall:[/] [bold]{lazy_plugins_dir}[/]")
                if not DRY_RUN:
                    shutil.rmtree(lazy_plugins_dir)
                else:
                    log.warning(f"[yellow]NORUN:[/] [dim]rm -rf '{lazy_plugins_dir}'[/]")

        ensure_copy(lazy_lock_src, lazy_lock_dest)
    else:
        log.info("[dim]neovim-lazy-lock.json not found, skipping[/]")

    # Copy ctags configuration
    log.info("[bold blue]Setup ctags conf[/]")
    ensure_copy(DOTFILES_DIR / "ctags", home / ".ctags")

    # Create lazygit config if it doesn't exist
    lazygit_config = nvim_config_dir / "lazygit" / "config.yml"
    if not lazygit_config.exists():
        if not DRY_RUN:
            lazygit_config.write_text("# Lazygit configuration\n")
        else:
            log.warning("[yellow]NORUN:[/] [dim]create lazygit config.yml[/]")


def sync_dotfiles_back() -> None:
    """Sync dotfiles back from home directory"""
    console.log(Panel("SYNCING BACK", style="bold green"))

    synced_count = 0
    home = Path.home()

    log.info("[bold yellow]Checking for changes to sync back to dotfiles...[/]")

    # Check general config files
    files_to_check = [
        (home / ".gitconfig", DOTFILES_DIR / "gitconfig", "gitconfig"),
        (home / ".gitconfig", DOTFILES_DIR / "gitconfig-work", "gitconfig-work"),
        (home / ".abcde.conf", DOTFILES_DIR / "abcde.conf", "abcde.conf"),
        (home / ".pypi.rc", DOTFILES_DIR / "pypi.rc", "pypi.rc"),
        (home / ".config" / "language-server.json", DOTFILES_DIR / "language-server.json", "language-server.json"),
        (home / ".msmtprc", DOTFILES_DIR / "msmtprc", "msmtprc"),
        (home / ".ssh" / "config", DOTFILES_DIR / "ssh-config", "ssh config"),
        (home / ".ssh" / "config", DOTFILES_DIR / "ssh-config-work", "ssh config-work"),
        (home / ".config" / "fish" / "config.fish", DOTFILES_DIR / "fish-config.fish", "fish config.fish"),
        (home / ".config" / "fish" / "config-linux.fish", DOTFILES_DIR / "fish-config-linux.fish", "fish config-linux.fish"),
        (home / ".config" / "kitty" / "kitty.conf", DOTFILES_DIR / "kitty.conf", "kitty.conf"),
        (home / ".tmux.conf", DOTFILES_DIR / "tmux.conf", "tmux.conf"),
        (home / ".config" / "nvim" / "init.lua", DOTFILES_DIR / "neovim-init.lua", "neovim init.lua"),
        (home / ".config" / "nvim" / "lazy-lock.json", DOTFILES_DIR / "neovim-lazy-lock.json", "neovim lazy-lock.json"),
        (home / ".ctags", DOTFILES_DIR / "ctags", "ctags"),
    ]

    # Check fish conf.d files
    for conf_file in ["mine-aliases-git.fish", "mine-arch-aliases.fish", "mine-python.fish", "mine-ssh.fish", "mine-work.fish"]:
        files_to_check.append((
            home / ".config" / "fish" / "conf.d" / conf_file,
            DOTFILES_DIR / f"fish-{conf_file}",
            f"fish conf.d/{conf_file}"
        ))

    for home_file, dotfiles_file, description in files_to_check:
        if sync_file_back(home_file, dotfiles_file, description):
            synced_count += 1

    if synced_count > 0:
        log.info(f"[green]Synced[/] [bold]{synced_count}[/] [green]files back to dotfiles directory[/]")
        log.info("[cyan]You may want to commit these changes:[/]")
        log.info(f"[dim]cd '{DOTFILES_DIR.parent}' && git add dotfiles/ && git commit -m 'Update dotfiles from home directory'[/]")
    else:
        log.info("[green]No files needed syncing[/]")


def main() -> None:
    """Main execution function"""
    global DRY_RUN, DEBUG, SYNC_MODE

    parser = argparse.ArgumentParser(description="Deploy dotfiles using Python with Rich console output")
    parser.add_argument("-n", "--dry-run", action="store_true", help="Dry run; output commands but don't execute")
    parser.add_argument("-d", "--debug", action="store_true", help="Show debug information")
    parser.add_argument("-s", "--sync", action="store_true", help="Sync mode; sync changes from home back to dotfiles")

    args = parser.parse_args()

    DRY_RUN = args.dry_run
    DEBUG = args.debug
    SYNC_MODE = args.sync

    console.log(Panel(f"setup-dotfiles.py started", style="bold green"))

    log.debug(f"SETUP_HOST: {SETUP_HOST}")
    log.debug(f"WORK_HOSTS: {', '.join(WORK_HOSTS)}")
    log.debug(f"SCRIPT_DIR: {SCRIPT_DIR}")
    log.debug(f"DOTFILES_DIR: {DOTFILES_DIR}")

    if SYNC_MODE:
        console.log(Panel("SYNC MODE", style="bold green"))
    else:
        console.log(Panel("DEPLOY MODE", style="bold green"))

    # Main deployment logic
    if SYNC_MODE:
        sync_dotfiles_back()
    else:
        if SETUP_HOST == "jump.km.nvidia.com":
            # Jump host setup
            setup_general_dotfiles()
            setup_ssh_dotfiles()
            setup_neovim_dotfiles()
            setup_fish_dotfiles()
        elif WORK_LT in SETUP_HOST:
            # Work laptop setup
            setup_general_dotfiles()
            setup_ssh_dotfiles()
            setup_neovim_dotfiles()
            setup_fish_dotfiles()
            setup_kitty_dotfiles()
        else:
            # Personal setup
            setup_general_dotfiles()
            setup_ssh_dotfiles()
            setup_neovim_dotfiles()
            setup_fish_dotfiles()
            setup_kitty_dotfiles()
            setup_tmux_dotfiles()

    log.info(f"[bold green]{datetime.now().strftime('%c')}[/] [green]::[/] [bold bright_green]All Done![/]")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.log("\n[yellow]Interrupted by user[/]")
        sys.exit(130)
