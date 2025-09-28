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

# Install dotfiles using setup-dotfiles.lua
dotfiles-install:
    nvim -l setup-dotfiles.lua

# Dry run dotfiles installation (preview changes without applying)
dotfiles-preview:
    nvim -l setup-dotfiles.lua -n

# Install dotfiles with debug output
dotfiles-debug:
    nvim -l setup-dotfiles.lua -d

# Show help for dotfiles setup script
dotfiles-help:
    nvim -l setup-dotfiles.lua -h
