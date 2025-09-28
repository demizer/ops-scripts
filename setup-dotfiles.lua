#!/usr/bin/env nvim -l

-- setup-dotfiles.lua - Deploy development environments using Neovim Lua
-- Replicates the functionality of dotfiles/deploy.sh
--
-- Usage:
--   nvim -l setup-dotfiles.lua          # Run setup
--   nvim -l setup-dotfiles.lua -n       # Dry run
--   nvim -l setup-dotfiles.lua -d       # Debug output
--   nvim -l setup-dotfiles.lua -h       # Help
--
-- Features:
-- * Copies dotfiles (git, fish, kitty, tmux configs) to their destinations
-- * Shows Neovim diff when files differ, allowing user to choose whether to overwrite
-- * Creates Neovim configuration from nvim.lua
-- * Installs fonts and terminal configurations
-- * Host-specific configurations for work/personal setups
-- * Dry run mode for testing changes
--
-- Note: Uses file copies instead of symlinks for NFS compatibility.
-- This script replaces the deprecated dotfiles/nvim setup with
-- the creation of ~/.config/nvim/init.lua from the nvim.lua file.

local M = {}

-- Configuration
local config = {
    NAME = "setup-dotfiles.lua",
    SCRIPT_DIR = vim.fn.expand(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")),
    NVIMDESTDIR = vim.fn.expand("$HOME/.config/nvim"),
    OS_REL = nil,
    HOST = vim.fn.hostname(),

    WORK_HOSTS = {"jesusa-lt", "jesusa-desktop", "jesusa-ws-fc29", "jump.km.nvidia.com", "jesusa-fridge"},
    WORK_LT = "jesusa-lt",
    PERS_LT = "neon",

    NVIM_PLUGIN_UPDATE = true,
    DRY_RUN = false,
    DEBUG = false,
    FONTS_AVAILABLE = nil,
}

-- Color codes
local colors = {
    ALL_OFF = "\27[0m",
    BOLD = "\27[1m",
    BLACK = "\27[1m\27[30m",
    RED = "\27[1m\27[31m",
    GREEN = "\27[1m\27[32m",
    YELLOW = "\27[1m\27[33m",
    BLUE = "\27[1m\27[34m",
    MAGENTA = "\27[1m\27[35m",
    CYAN = "\27[1m\27[36m",
    WHITE = "\27[1m\27[37m",
    DEFAULT = "\27[1m\27[39m",
}

-- Global variables for command execution
local RUN_CMD_RETURN = 0
local RUN_CMD_OUTPUT = ""

-- Logging functions
function M.plain(mesg, ...)
    local args = {...}
    io.write(colors.ALL_OFF .. mesg .. colors.ALL_OFF .. "\n\n")
    if #args > 0 then
        for _, arg in ipairs(args) do
            io.write(arg .. " ")
        end
        io.write("\n\n")
    end
    io.flush()
end

function M.plain_one_line(mesg, ...)
    local args = {...}
    io.write(colors.ALL_OFF .. colors.ALL_OFF .. mesg)
    for _, arg in ipairs(args) do
        io.write(" " .. arg)
    end
    io.write("\n\n")
    io.flush()
end

function M.msg(mesg, ...)
    local args = {...}
    io.write(colors.GREEN .. "====" .. colors.ALL_OFF .. " " .. colors.BOLD .. mesg .. colors.ALL_OFF .. "\n\n")
    if #args > 0 then
        for _, arg in ipairs(args) do
            io.write(arg .. " ")
        end
        io.write("\n\n")
    end
    io.flush()
end

function M.msg2(mesg, ...)
    local args = {...}
    io.write(colors.BLUE .. "++++ " .. colors.ALL_OFF .. colors.BOLD .. mesg .. colors.ALL_OFF .. "\n\n")
    if #args > 0 then
        for _, arg in ipairs(args) do
            io.write(arg .. " ")
        end
        io.write("\n\n")
    end
    io.flush()
end

function M.warning(mesg, ...)
    local args = {...}
    io.stderr:write(colors.YELLOW .. "==== WARNING: " .. colors.ALL_OFF .. colors.BOLD .. mesg .. colors.ALL_OFF .. "\n\n")
    if #args > 0 then
        for _, arg in ipairs(args) do
            io.stderr:write(arg .. " ")
        end
        io.stderr:write("\n\n")
    end
    io.stderr:flush()
end

function M.error(mesg, ...)
    local args = {...}
    io.stderr:write(colors.RED .. "==== ERROR: " .. colors.ALL_OFF .. colors.RED .. colors.BOLD .. mesg .. colors.ALL_OFF .. "\n\n")
    if #args > 0 then
        for _, arg in ipairs(args) do
            io.stderr:write(arg .. " ")
        end
        io.stderr:write("\n\n")
    end
    io.stderr:flush()
end

function M.debug(mesg, ...)
    if not config.DEBUG then return end
    local args = {...}
    io.stderr:write(colors.MAGENTA .. "~~~~ DEBUG: " .. colors.ALL_OFF .. colors.BOLD .. mesg .. colors.ALL_OFF .. "\n\n")
    if #args > 0 then
        for _, arg in ipairs(args) do
            io.stderr:write(arg .. " ")
        end
        io.stderr:write("\n\n")
    end
    io.stderr:flush()
end

function M.subsection(section, subsection, ...)
    local args = {...}
    io.write(colors.CYAN .. "**** " .. colors.ALL_OFF .. colors.BOLD .. section .. ": " .. subsection .. colors.ALL_OFF .. "\n\n")
    if #args > 0 then
        for _, arg in ipairs(args) do
            io.write(arg .. " ")
        end
        io.write("\n\n")
    end
    io.flush()
end

function M.norun(mesg, ...)
    local args = {...}
    io.write(colors.MAGENTA .. "XXXX NORUN: " .. colors.ALL_OFF .. colors.BOLD .. mesg .. colors.ALL_OFF .. "\n\n")
    if #args > 0 then
        for _, arg in ipairs(args) do
            io.write(arg .. " ")
        end
        io.write("\n\n")
    end
    io.flush()
end

-- Utility functions
function M.run_cmd(cmd)
    if config.DRY_RUN then
        M.norun("CMD:", cmd)
        return 0
    else
        M.plain("Running command:", cmd)
        M.plain_one_line("Output:")

        local handle = io.popen(cmd .. " 2>&1; echo $?")
        local result = handle:read("*a")
        handle:close()

        -- Extract exit code from last line
        local lines = {}
        for line in result:gmatch("[^\r\n]+") do
            table.insert(lines, line)
        end

        local exit_code = tonumber(lines[#lines]) or 1
        table.remove(lines) -- Remove exit code line

        -- Print output
        for _, line in ipairs(lines) do
            print(line)
        end
        print()

        RUN_CMD_RETURN = exit_code
        M.plain_one_line("Command returned:", tostring(exit_code))

        return exit_code
    end
end

function M.run_cmd_quiet(cmd)
    if config.DRY_RUN then
        M.norun("CMD:", cmd)
        return 0
    else
        M.plain("Running command:", cmd)

        local handle = io.popen(cmd .. " 2>&1; echo $?")
        local result = handle:read("*a")
        handle:close()

        -- Extract exit code from last line
        local lines = {}
        for line in result:gmatch("[^\r\n]+") do
            table.insert(lines, line)
        end

        local exit_code = tonumber(lines[#lines]) or 1
        table.remove(lines) -- Remove exit code line

        RUN_CMD_OUTPUT = table.concat(lines, "\n")
        RUN_CMD_RETURN = exit_code
        M.plain_one_line("Command returned:", tostring(exit_code))

        if exit_code ~= 0 then
            M.error("Command failed with exit code", tostring(exit_code))
            os.exit(1)
        end

        return exit_code
    end
end

-- Run command that always executes (even in dry-run) for read-only operations
function M.run_cmd_always(cmd)
    M.plain("Running command:", cmd)

    local handle = io.popen(cmd .. " 2>&1; echo $?")
    local result = handle:read("*a")
    handle:close()

    -- Extract exit code from last line
    local lines = {}
    for line in result:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local exit_code = tonumber(lines[#lines]) or 1
    table.remove(lines) -- Remove exit code line

    RUN_CMD_OUTPUT = table.concat(lines, "\n")
    RUN_CMD_RETURN = exit_code
    M.plain_one_line("Command returned:", tostring(exit_code))

    return exit_code
end

function M.ensure_dir_exists(dir)
    -- Check each component of the path for symlinks
    local parts = {}
    local current_path = ""

    -- Split path into components
    for part in dir:gmatch("[^/]+") do
        table.insert(parts, part)
    end

    -- Check each path component
    for i, part in ipairs(parts) do
        if i == 1 and dir:sub(1, 1) == "/" then
            current_path = "/" .. part
        else
            current_path = current_path .. "/" .. part
        end

        local stat = vim.loop.fs_lstat(current_path)
        if stat and stat.type == "link" then
            M.msg2("Removing symlink " .. current_path)
            if not config.DRY_RUN then
                os.remove(current_path)
            else
                M.norun("CMD:", "rm '" .. current_path .. "'")
            end
        end
    end

    local stat = vim.loop.fs_lstat(dir)
    if not stat then
        M.msg2("Creating directory " .. dir)
        if not config.DRY_RUN then
            vim.fn.mkdir(dir, "p")
        else
            M.norun("CMD:", "mkdir -p '" .. dir .. "'")
        end
    elseif stat.type == "directory" then
        M.msg2("Directory " .. dir .. " already exists")
    end
end

function M.file_exists(file)
    local stat = vim.loop.fs_stat(file)
    return stat and stat.type == "file"
end

function M.ensure_symlink_exists(target, link_path)
    M.debug("ensure_symlink_exists:", "target=" .. target, "link_path=" .. link_path)

    local stat = vim.loop.fs_lstat(link_path)
    if stat and stat.type == "link" then
        local current_target = vim.loop.fs_readlink(link_path)
        M.debug("ensure_symlink_exists: current target =", current_target or "nil")

        if current_target == target then
            M.debug("ensure_symlink_exists: Valid symlink:", target, "==", current_target)
            return
        else
            M.debug("ensure_symlink_exists: Invalid symlink: deleting", link_path)
            os.remove(link_path)
        end
    elseif stat and stat.type == "file" then
        M.warning("File '" .. link_path .. "' exists and is a regular file.")
        local content = vim.fn.readfile(link_path)
        for _, line in ipairs(content) do
            io.stderr:write(line .. "\n")
        end
        io.stderr:write("\n")

        io.stderr:write("Delete this file and create symlink? [y/N]: ")
        io.stderr:flush()
        local reply = io.read()

        if not (reply:lower() == "y" or reply:lower() == "yes") then
            M.error("User chose not to delete existing file")
            os.exit(1)
        end

        os.remove(link_path)
    end

    M.msg2("Creating symlink " .. target .. " to " .. link_path)
    -- Ensure parent directory exists
    local parent = vim.fn.fnamemodify(link_path, ":h")
    M.ensure_dir_exists(parent)
    vim.loop.fs_symlink(target, link_path)
end

function M.show_file_diff(source, dest_path)
    M.msg2("Showing diff between " .. source .. " and " .. dest_path)
    if config.DRY_RUN then
        M.norun("CMD:", "nvim -d '" .. source .. "' '" .. dest_path .. "'")
    else
        M.run_cmd("nvim -d '" .. source .. "' '" .. dest_path .. "'")
    end
end

function M.ensure_copy(source, dest_path)
    M.debug("ensure_copy:", "source=" .. source, "dest_path=" .. dest_path)

    -- Check if source file exists
    if not M.file_exists(source) then
        M.error("Source file does not exist:", source)
        os.exit(1)
    end

    local stat = vim.loop.fs_lstat(dest_path)
    local should_copy = false

    if stat and stat.type == "link" then
        local current_target = vim.loop.fs_readlink(dest_path)
        M.msg2("Replacing symlink " .. dest_path .. " (currently points to " .. (current_target or "unknown") .. ")")
        M.debug("ensure_copy: Removing existing symlink:", dest_path)
        if not config.DRY_RUN then
            os.remove(dest_path)
        end
        should_copy = true
    elseif stat and stat.type == "file" then
        -- Check if files are different by comparing content
        local source_content = vim.fn.readfile(source)
        local dest_content = vim.fn.readfile(dest_path)

        if vim.deep_equal(source_content, dest_content) then
            M.msg2("File " .. dest_path .. " already exists and matches source")
            return
        else
            M.warning("File '" .. dest_path .. "' exists but differs from source.")
            M.show_file_diff(source, dest_path)

            io.stderr:write("Copy source file over destination? [y/N]: ")
            io.stderr:flush()
            local reply = io.read()

            if reply:lower() == "y" or reply:lower() == "yes" then
                should_copy = true
            else
                M.msg("Skipping copy of " .. dest_path)
                return
            end
        end
    else
        M.msg2("File " .. dest_path .. " does not exist, will create")
        should_copy = true
    end

    if should_copy then
        M.msg2("Copying " .. source .. " to " .. dest_path)
        -- Ensure parent directory exists
        local parent = vim.fn.fnamemodify(dest_path, ":h")
        M.ensure_dir_exists(parent)

        if config.DRY_RUN then
            M.norun("CMD:", "cp '" .. source .. "' '" .. dest_path .. "'")
        else
            M.run_cmd_quiet("cp '" .. source .. "' '" .. dest_path .. "'")
        end
    end
end

function M.git_clone_pull(path, repo)
    local orig = vim.fn.getcwd()
    M.debug("git_clone_pull:", "path=" .. path, "repo=" .. repo)

    if vim.fn.isdirectory(path) == 1 then
        vim.cmd("cd " .. vim.fn.fnameescape(path))
        M.msg2("Pulling into " .. vim.fn.getcwd())
        M.run_cmd("git reset --hard HEAD")
        if RUN_CMD_RETURN ~= 0 then return false end
        M.run_cmd("git pull --all")
        if RUN_CMD_RETURN ~= 0 then return false end
    else
        -- Ensure parent directory exists
        local parent = vim.fn.fnamemodify(path, ":h")
        M.ensure_dir_exists(parent)
        M.msg2("Cloning into " .. path)
        M.run_cmd("git clone --recursive " .. vim.fn.shellescape(repo) .. " " .. vim.fn.shellescape(path))
        if RUN_CMD_RETURN ~= 0 then return false end
    end

    vim.cmd("cd " .. vim.fn.fnameescape(orig))
    return true
end

-- Get OS release info
function M.get_os_release()
    local handle = io.popen("source /etc/os-release && echo \"${ID}\"")
    local result = handle:read("*a"):gsub("%s+", "")
    handle:close()
    return result
end

-- Check if hostname is in work hosts
function M.is_work_host(hostname)
    for _, work_host in ipairs(config.WORK_HOSTS) do
        if hostname:find(work_host, 1, true) then
            return true
        end
    end
    return false
end

-- Setup personal GPG key
function M.setup_personal_gpg()
    M.msg("=============================")
    M.msg("==========   GPG   ==========")
    M.msg("=============================")

    M.msg("Checking gpg private key imported...")

    -- Check if key is already imported (always run this read-only command)
    M.run_cmd_always("gpg --list-secret-keys")
    if RUN_CMD_OUTPUT:find("0EE7A126") then
        M.msg("GPG private key already imported")
    else
        -- Key not found
        M.warning("GPG private key (0EE7A126) not found!")

        if config.DRY_RUN then
            M.msg("DRY RUN: Would prompt user to paste GPG key from Bitwarden")
            return  -- Skip GPG setup in dry-run mode
        end

        -- Prompt user to get it from Bitwarden
        print("")
        print("Please get your GPG private key from Bitwarden and paste it below.")
        print("The key should be in ASCII armored format (-----BEGIN PGP PRIVATE KEY BLOCK-----).")
        print("")
        io.write("Paste your GPG private key here (press Ctrl+D when done):\n")

        -- Read the key from stdin
        local key_content = {}
        for line in io.lines() do
            table.insert(key_content, line)
        end

        if #key_content == 0 then
            M.error("No GPG key provided. Cannot continue without GPG key.")
            os.exit(1)
        end

        -- Write key to temporary file
        local temp_key_file = "/tmp/temp_gpg_key.asc"
        local file = io.open(temp_key_file, "w")
        if not file then
            M.error("Cannot create temporary key file")
            os.exit(1)
        end

        for _, line in ipairs(key_content) do
            file:write(line .. "\n")
        end
        file:close()

        -- Import the key
        M.msg("Importing GPG key...")
        M.run_cmd("gpg --import " .. temp_key_file)
        if RUN_CMD_RETURN ~= 0 then
            M.error("Failed to import GPG key!")
            os.remove(temp_key_file)
            os.exit(1)
        end

        -- Clean up temporary file
        os.remove(temp_key_file)
        M.msg("GPG key imported successfully")
    end

    -- Set up GPG agent configuration
    M.msg("Setting up gnupg agent...")
    local gpg_agent_conf = vim.fn.expand("$HOME/.gnupg/gpg-agent.conf")
    local pinentry_path = "/usr/bin/pinentry-curses"

    -- Ensure .gnupg directory exists
    M.ensure_dir_exists(vim.fn.expand("$HOME/.gnupg"))

    -- Check and add pinentry timeout if not present
    local has_timeout = false
    local has_program = false

    if M.file_exists(gpg_agent_conf) then
        local content = vim.fn.readfile(gpg_agent_conf)
        for _, line in ipairs(content) do
            if line:find("pinentry%-timeout") then
                has_timeout = true
            end
            if line:find("pinentry%-program") then
                has_program = true
            end
        end
    end

    if has_timeout then
        M.msg2("pinentry-timeout already configured in gpg-agent.conf")
    else
        M.msg2("Adding pinentry-timeout to gpg-agent.conf")
        if not config.DRY_RUN then
            M.run_cmd("echo 'pinentry-timeout 86400' >> " .. gpg_agent_conf)
        else
            M.norun("CMD:", "echo 'pinentry-timeout 86400' >> " .. gpg_agent_conf)
        end
    end

    if has_program then
        M.msg2("pinentry-program already configured in gpg-agent.conf")
    else
        M.msg2("Adding pinentry-program to gpg-agent.conf")
        if not config.DRY_RUN then
            M.run_cmd("echo 'pinentry-program " .. pinentry_path .. "' >> " .. gpg_agent_conf)
        else
            M.norun("CMD:", "echo 'pinentry-program " .. pinentry_path .. "' >> " .. gpg_agent_conf)
        end
    end

    -- Reload GPG agent
    M.msg("Reloading the gpg agent")
    M.run_cmd("gpg-connect-agent reloadagent /bye")
end

-- Usage function
function M.usage()
    print("setup-dotfiles.lua - Deploy development environments")
    print("")
    print("Usage: nvim -l setup-dotfiles.lua [options]")
    print("")
    print("Options:")
    print("")
    print("    -h:    Show help information.")
    print("    -n:    Dryrun; Output commands, but don't do anything.")
    print("    -d:    Show debug info.")
    print("    -u:    Update neovim plugins")
end

-- Parse command line arguments
function M.parse_args(args)
    for _, arg in ipairs(args) do
        if arg == "-n" or arg == "--dry-run" then
            config.DRY_RUN = true
        elseif arg == "-d" or arg == "--debug" then
            config.DEBUG = true
        elseif arg == "-u" then
            config.NVIM_PLUGIN_UPDATE = true
        elseif arg == "-h" then
            M.usage()
            os.exit(0)
        end
    end
end

-- Initialize configuration
function M.init()
    config.OS_REL = M.get_os_release()

    M.debug("OS_REL:", config.OS_REL)
    M.debug("HOST:", config.HOST)
    M.debug("WORK_HOSTS:", table.concat(config.WORK_HOSTS, ", "))
    M.debug("WORK_LT:", config.WORK_LT)
    M.debug("PERS_LT:", config.PERS_LT)
    M.debug("SCRIPT_DIR:", config.SCRIPT_DIR)
end

-- Preflight checks
function M.preflight_checks()
    M.msg("=============================")
    M.msg("======= Sanity Checks =======")
    M.msg("=============================")

    M.msg("Checking for hostname tool...")
    local hostname_check = os.execute("which hostname > /dev/null 2>&1")
    if hostname_check ~= 0 then
        M.error("'hostname' command not found! (install with: pacman -Sy inetutils)")
        os.exit(1)
    end

    M.msg("Checking for wget...")
    local wget_check = os.execute("which wget > /dev/null 2>&1")
    if wget_check ~= 0 then
        M.error("'wget' command not found! (install with: pacman -Sy wget)")
        os.exit(1)
    end

    M.msg("Checking if running in Neovim...")
    if not vim then
        M.error("This script must be run with 'nvim -l setup-dotfiles.lua'")
        os.exit(1)
    end
end

-- Setup fonts
function M.setup_fonts()
    M.subsection("GENERAL", "FONTS")

    local fonts_dir = vim.fn.expand("$HOME/.fonts")
    M.ensure_dir_exists(fonts_dir)

    -- Check for fonts in /mnt/backups/fonts first
    local backup_fonts_dir = "/mnt/backups/fonts"
    local font_src = backup_fonts_dir .. "/Berkeley Mono Regular Nerd Font Complete.ttf"
    local font_dest = fonts_dir .. "/Berkeley Mono Regular Nerd Font Complete.ttf"

    if vim.fn.isdirectory(backup_fonts_dir) == 1 and M.file_exists(font_src) then
        M.msg("Setup Berkeley Mono font from backup location")
        M.ensure_copy(font_src, font_dest)
        return true -- Successfully copied fonts
    else
        M.debug("Backup fonts directory not available or font not found:", backup_fonts_dir)
        return false -- Fonts not available
    end
end

-- Setup general configuration
function M.setup_general()
    M.msg("=============================")
    M.msg("========== GENERAL ==========")
    M.msg("=============================")

    -- Store font setup result for later warning
    config.FONTS_AVAILABLE = M.setup_fonts()

    local dotfiles_dir = config.SCRIPT_DIR .. "/dotfiles"

    if M.is_work_host(config.HOST) then
        M.msg("Setup gitconfig (work)")
        M.ensure_copy(dotfiles_dir .. "/gitconfig-work", vim.fn.expand("$HOME/.gitconfig"))
    else
        M.msg("Setup gitconfig")
        M.ensure_copy(dotfiles_dir .. "/gitconfig", vim.fn.expand("$HOME/.gitconfig"))

        M.msg("Setup abcde.conf")
        M.ensure_copy(dotfiles_dir .. "/abcde.conf", vim.fn.expand("$HOME/.abcde.conf"))
    end

    if not config.HOST:find("km.nvidia.com") then
        M.ensure_copy(dotfiles_dir .. "/pypi.rc", vim.fn.expand("$HOME/.pypi.rc"))
        M.ensure_copy(dotfiles_dir .. "/language-server.json", vim.fn.expand("$HOME/.config/language-server.json"))

        local msmtprc_dest = vim.fn.expand("$HOME/.msmtprc")
        M.ensure_copy(dotfiles_dir .. "/msmtprc", msmtprc_dest)
        M.run_cmd_quiet("chmod 600 '" .. msmtprc_dest .. "'")
    end
end

-- Setup fish shell
function M.setup_fish()
    M.msg("==============================")
    M.msg("==========   FISH   ==========")
    M.msg("==============================")

    M.msg("Setup fish config files")
    local fish_config_dir = vim.fn.expand("$HOME/.config/fish")
    local fish_confd_dir = fish_config_dir .. "/conf.d"
    local dotfiles_dir = config.SCRIPT_DIR .. "/dotfiles"

    M.ensure_dir_exists(fish_config_dir)
    M.ensure_dir_exists(fish_confd_dir)

    M.ensure_copy(dotfiles_dir .. "/fish-config.fish", fish_config_dir .. "/config.fish")
    M.ensure_copy(dotfiles_dir .. "/fish-config-linux.fish", fish_config_dir .. "/config-linux.fish")

    M.msg("Setup fish conf.d files")
    M.ensure_copy(dotfiles_dir .. "/fish-mine-aliases-git.fish", fish_confd_dir .. "/mine-aliases-git.fish")
    M.ensure_copy(dotfiles_dir .. "/fish-mine-arch-aliases.fish", fish_confd_dir .. "/mine-arch-aliases.fish")
    M.ensure_copy(dotfiles_dir .. "/fish-mine-python.fish", fish_confd_dir .. "/mine-python.fish")
    M.ensure_copy(dotfiles_dir .. "/fish-mine-ssh.fish", fish_confd_dir .. "/mine-ssh.fish")
    M.ensure_copy(dotfiles_dir .. "/fish-mine-work.fish", fish_confd_dir .. "/mine-work.fish")

    -- Check if we should set fish as default shell
    local handle = io.popen("getent passwd $(id -un) | awk -F : '{print $NF}'")
    local current_shell = handle:read("*a"):gsub("%s+", "")
    handle:close()

    handle = io.popen("which fish")
    local fish_path = handle:read("*a"):gsub("%s+", "")
    handle:close()

    if current_shell ~= fish_path then
        M.msg("Set fish as the login shell")
        M.run_cmd_quiet("sudo chsh -s " .. fish_path .. " " .. os.getenv("USER"))
    else
        M.msg("Shell is already set to fish!")
    end

    -- Install fisher if not present
    M.msg("Checking for fisher")
    local fisher_check = os.execute("fish -c 'fisher -v > /dev/null 2>&1'")
    if fisher_check ~= 0 then
        M.run_cmd("wget -q -O /tmp/fisher-install https://git.io/fisher && fish -c 'source /tmp/fisher-install && fisher install jorgebucaran/fisher'")
    else
        M.msg2("Fisher is already installed")
    end

    M.msg("Install fish plugins")
    M.run_cmd("fish -c 'fisher install pure-fish/pure'")
    M.run_cmd("fish -c 'fisher install jethrokuan/z'")
    M.run_cmd("fish -c 'fisher install danhper/fish-ssh-agent'")
end

-- Setup kitty terminal
function M.setup_kitty()
    M.msg("Setup kitty Config")
    local kitty_config_dir = vim.fn.expand("$HOME/.config/kitty")
    M.ensure_dir_exists(kitty_config_dir)

    M.ensure_copy(config.SCRIPT_DIR .. "/dotfiles/kitty.conf", kitty_config_dir .. "/kitty.conf")

    local themes_path = kitty_config_dir .. "/kitty-themes"
    M.git_clone_pull(themes_path, "https://github.com/dexpota/kitty-themes.git")
end

-- Setup tmux
function M.setup_tmux()
    M.msg("=============================")
    M.msg("==========   TMUX  ==========")
    M.msg("=============================")

    M.msg("Pull tpm")
    local tpm_path = vim.fn.expand("$HOME/.tmux/plugins/tpm")
    M.git_clone_pull(tpm_path, "https://github.com/tmux-plugins/tpm")

    M.msg("Setup tmux.conf")
    M.ensure_copy(config.SCRIPT_DIR .. "/dotfiles/tmux.conf", vim.fn.expand("$HOME/.tmux.conf"))
end

-- Create neovim configuration (replaces deprecated nvim.lua functionality)
function M.create_nvim_config()
    M.msg("=============================")
    M.msg("=====  NEOVIM CONFIG  =======")
    M.msg("=============================")

    M.msg("Creating Neovim configuration directory")
    M.ensure_dir_exists(config.NVIMDESTDIR)

    -- Create directories for backups, swapfiles, and undo
    M.ensure_dir_exists(config.NVIMDESTDIR .. "/backups")
    M.ensure_dir_exists(config.NVIMDESTDIR .. "/swapfiles")
    M.ensure_dir_exists(config.NVIMDESTDIR .. "/undodir")
    M.ensure_dir_exists(config.NVIMDESTDIR .. "/lazygit")

    -- Copy the existing neovim-init.lua as init.lua
    local init_lua_path = config.NVIMDESTDIR .. "/init.lua"
    local nvim_lua_path = config.SCRIPT_DIR .. "/dotfiles/neovim-init.lua"

    if M.file_exists(nvim_lua_path) then
        M.msg("Setup nvim.lua as init.lua")
        M.ensure_copy(nvim_lua_path, init_lua_path)
    else
        M.warning("neovim-init.lua not found, creating minimal init.lua")
        -- Ensure the parent directory exists before creating the file
        local parent = vim.fn.fnamemodify(init_lua_path, ":h")
        M.ensure_dir_exists(parent)

        local minimal_config = [[-- Minimal Neovim configuration
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
]]
        local file = io.open(init_lua_path, "w")
        file:write(minimal_config)
        file:close()
    end

    -- Copy neovim-lazy-lock.json if it exists
    local lazy_lock_src = config.SCRIPT_DIR .. "/dotfiles/neovim-lazy-lock.json"
    local lazy_lock_dest = config.NVIMDESTDIR .. "/lazy-lock.json"
    if M.file_exists(lazy_lock_src) then
        M.msg("Setup lazy-lock.json")
        M.ensure_copy(lazy_lock_src, lazy_lock_dest)
    else
        M.msg("neovim-lazy-lock.json not found, skipping")
    end

    -- Copy ctags configuration
    M.msg("Setup ctags conf")
    M.ensure_copy(config.SCRIPT_DIR .. "/dotfiles/ctags", vim.fn.expand("$HOME/.ctags"))

    -- Create lazygit config if it doesn't exist
    local lazygit_config = config.NVIMDESTDIR .. "/lazygit/config.yml"
    if not M.file_exists(lazygit_config) then
        local file = io.open(lazygit_config, "w")
        file:write("# Lazygit configuration\n")
        file:close()
    end
end

-- Main execution function
function M.main(args)
    M.parse_args(args or {})
    M.init()
    M.preflight_checks()

    if config.HOST == "jump.km.nvidia.com" then
        -- Jump host setup
        M.setup_general()
        M.create_nvim_config()
        M.setup_fish()
    elseif config.HOST:find(config.WORK_LT) then
        -- Work laptop setup
        M.setup_general()
        M.setup_personal_gpg()
        M.create_nvim_config()
        M.setup_fish()
        M.setup_kitty()
    else
        -- Personal setup
        M.setup_general()
        M.setup_personal_gpg()
        M.create_nvim_config()
        M.setup_fish()
        M.setup_kitty()
        M.setup_tmux()
    end

    M.msg(os.date("%c") .. " :: All Done!")

    -- Show warning if fonts were not available
    if config.FONTS_AVAILABLE == false then
        M.warning("Fonts were not copied! The /mnt/backups/fonts directory was not available.")
        M.warning("Please ensure /mnt/backups/fonts is mounted and contains Berkeley Mono font.")
    end
end

-- Auto-run if script is executed directly
if arg then
    M.main(arg)
end

return M