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
from datetime import datetime
import json
import platform
import shutil
import socket
import sys
from pathlib import Path

from rich.panel import Panel
from rich.prompt import Confirm

# Import common utilities
import setup_common

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

# Use console and log from setup_common
console = setup_common.console
log = setup_common.log


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




def is_work_host(hostname: str) -> bool:
    """Check if hostname is a work host"""
    return any(work_host in hostname for work_host in WORK_HOSTS)


def check_and_install_macos_dependencies() -> None:
    """Check and install required dependencies on macOS via Homebrew"""
    if platform.system() != "Darwin":
        return

    console.log(Panel("CHECKING MACOS DEPENDENCIES", style="bold green"))

    # Check if Homebrew is installed
    log.info("[bold blue]Checking for Homebrew[/]")
    brew_check = setup_common.run_cmd_quiet_check(["which", "brew"], dry_run=DRY_RUN)
    if brew_check != 0:
        log.error("[bold red]Homebrew is not installed.[/] Install from https://brew.sh")
        sys.exit(1)

    log.info("[green]Homebrew is installed[/]")

    # List of required brew packages
    required_packages = ["fish", "atuin", "lazygit"]

    for package in required_packages:
        log.info(f"[bold blue]Checking for {package}[/]")
        check_exit = setup_common.run_cmd_quiet_check(["brew", "list", package], dry_run=DRY_RUN)

        if check_exit != 0:
            log.info(f"[yellow]{package} not installed, installing...[/]")
            setup_common.run_cmd(["brew", "install", package], dry_run=DRY_RUN)
            log.info(f"[green]{package} installed successfully[/]")
        else:
            log.info(f"[green]{package} is already installed[/]")


def setup_general_dotfiles() -> None:
    """Setup general dotfiles"""
    console.log(Panel("GENERAL DOTFILES", style="bold green"))

    home = Path.home()

    if is_work_host(SETUP_HOST):
        log.info("[bold blue]Setup gitconfig[/] [yellow](work)[/]")
        setup_common.ensure_copy(DOTFILES_DIR / "gitconfig-work", home / ".gitconfig", dry_run=DRY_RUN)
    else:
        log.info("[bold blue]Setup gitconfig[/]")
        setup_common.ensure_copy(DOTFILES_DIR / "gitconfig", home / ".gitconfig", dry_run=DRY_RUN)

        log.info("[bold blue]Setup abcde.conf[/]")
        setup_common.ensure_copy(DOTFILES_DIR / "abcde.conf", home / ".abcde.conf", dry_run=DRY_RUN)

    if "km.nvidia.com" not in SETUP_HOST:
        setup_common.ensure_copy(DOTFILES_DIR / "pypi.rc", home / ".pypi.rc", dry_run=DRY_RUN)
        setup_common.ensure_copy(DOTFILES_DIR / "language-server.json", home / ".config" / "language-server.json", dry_run=DRY_RUN)

        msmtprc_dest = home / ".msmtprc"
        setup_common.ensure_copy(DOTFILES_DIR / "msmtprc", msmtprc_dest, dry_run=DRY_RUN)
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
    setup_common.ensure_dir_exists(fish_config_dir, dry_run=DRY_RUN)
    setup_common.ensure_dir_exists(fish_confd_dir, dry_run=DRY_RUN)

    setup_common.ensure_copy(DOTFILES_DIR / "fish-config.fish", fish_config_dir / "config.fish", dry_run=DRY_RUN)
    setup_common.ensure_copy(DOTFILES_DIR / "fish-config-linux.fish", fish_config_dir / "config-linux.fish", dry_run=DRY_RUN)

    log.info("[bold blue]Setup fish conf.d files[/]")
    conf_files = [
        "mine-aliases-git.fish",
        "mine-arch-aliases.fish",
        "mine-python.fish",
        "mine-ssh.fish",
        "mine-work.fish"
    ]

    for conf_file in conf_files:
        setup_common.ensure_copy(DOTFILES_DIR / f"fish-{conf_file}", fish_confd_dir / conf_file, dry_run=DRY_RUN)

    # Check if fisher is installed
    log.info("[bold blue]Checking for fisher[/]")
    fisher_check_exit = setup_common.run_cmd(["fish", "-c", "fisher -v > /dev/null 2>&1"], dry_run=DRY_RUN)

    if fisher_check_exit != 0:
        log.info("[yellow]Fisher not installed, installing...[/]")
        # Download fisher installer
        fisher_url = "https://git.io/fisher"
        fisher_installer = "/tmp/fisher-install"

        log.info(f"[cyan]Downloading fisher from {fisher_url}[/]")
        setup_common.run_cmd_quiet(["curl", "-fsSL", "-o", fisher_installer, fisher_url], dry_run=DRY_RUN)

        # Install fisher
        log.info("[cyan]Installing fisher[/]")
        setup_common.run_cmd_quiet(["fish", "-c", f"source {fisher_installer} && fisher install jorgebucaran/fisher"], dry_run=DRY_RUN)
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
        setup_common.run_cmd_quiet(["fish", "-c", f"fisher install {plugin}"], dry_run=DRY_RUN)
        log.info(f"[green]Plugin {plugin} installed successfully[/]")


def setup_kitty_dotfiles() -> None:
    """Setup kitty terminal dotfiles"""
    log.info("[bold blue]Setup kitty config[/]")
    home = Path.home()
    kitty_config_dir = home / ".config" / "kitty"
    setup_common.ensure_dir_exists(kitty_config_dir, dry_run=DRY_RUN)

    setup_common.ensure_copy(DOTFILES_DIR / "kitty.conf", kitty_config_dir / "kitty.conf", dry_run=DRY_RUN)


def setup_ssh_dotfiles() -> None:
    """Setup SSH dotfiles"""
    log.info("[bold blue]Setup SSH config[/]")
    home = Path.home()
    ssh_dir = home / ".ssh"
    setup_common.ensure_dir_exists(ssh_dir, dry_run=DRY_RUN)

    ssh_config = ssh_dir / "config"

    if is_work_host(SETUP_HOST):
        log.info("[bold blue]Setup SSH config[/] [yellow](work)[/]")
        setup_common.ensure_copy(DOTFILES_DIR / "ssh-config-work", ssh_config, dry_run=DRY_RUN)
    else:
        log.info("[bold blue]Setup SSH config[/]")
        setup_common.ensure_copy(DOTFILES_DIR / "ssh-config", ssh_config, dry_run=DRY_RUN)

    # Set appropriate permissions
    if not DRY_RUN:
        ssh_config.chmod(0o600)
    else:
        log.warning(f"[yellow]NORUN:[/] [dim]chmod 600 '{ssh_config}'[/]")


def setup_tmux_dotfiles() -> None:
    """Setup tmux dotfiles"""
    log.info("[bold blue]Setup tmux.conf[/]")
    home = Path.home()
    setup_common.ensure_copy(DOTFILES_DIR / "tmux.conf", home / ".tmux.conf", dry_run=DRY_RUN)


def setup_neovim_dotfiles() -> None:
    """Setup neovim dotfiles"""
    console.log(Panel("NEOVIM DOTFILES", style="bold green"))

    home = Path.home()
    nvim_config_dir = home / ".config" / "nvim"

    log.info("[bold blue]Creating Neovim configuration directory[/]")
    setup_common.ensure_dir_exists(nvim_config_dir, dry_run=DRY_RUN)

    # Create directories for backups, swapfiles, and undo
    for subdir in ["backups", "swapfiles", "undodir", "lazygit"]:
        setup_common.ensure_dir_exists(nvim_config_dir / subdir, dry_run=DRY_RUN)

    # Copy the existing neovim-init.lua as init.lua
    init_lua_path = nvim_config_dir / "init.lua"
    nvim_lua_path = DOTFILES_DIR / "neovim-init.lua"

    if nvim_lua_path.exists():
        log.info("[bold blue]Setup neovim-init.lua as init.lua[/]")
        setup_common.ensure_copy(nvim_lua_path, init_lua_path, dry_run=DRY_RUN)
    else:
        log.warning("[yellow]neovim-init.lua not found, creating minimal init.lua[/]")
        setup_common.ensure_dir_exists(init_lua_path.parent, dry_run=DRY_RUN)

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
                setup_common.show_file_diff(lazy_lock_src, lazy_lock_dest, dry_run=DRY_RUN)

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

        setup_common.ensure_copy(lazy_lock_src, lazy_lock_dest, dry_run=DRY_RUN)
    else:
        log.info("[dim]neovim-lazy-lock.json not found, skipping[/]")

    # Copy ctags configuration
    log.info("[bold blue]Setup ctags conf[/]")
    setup_common.ensure_copy(DOTFILES_DIR / "ctags", home / ".ctags", dry_run=DRY_RUN)

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
        if setup_common.sync_file_back(home_file, dotfiles_file, description, dry_run=DRY_RUN):
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

    # Check and install dependencies on macOS
    check_and_install_macos_dependencies()

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
