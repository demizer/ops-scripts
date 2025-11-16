#!/bin/bash

# Configuration script for ops host
# Manages host configuration for already-installed system

# Load common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib.sh"

# Configuration
HOSTNAME="ops"
TARGET_USER="jesusa"

# Setup logging
LOG_FILE="configure-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure ops host system settings

OPTIONS:
    -h, --help              Show this help message
    --help-long             Show detailed descriptions of each step
    -f, --force             Skip confirmation prompts

STEP OPTIONS (run individual or multiple steps):
    --journal               Configure persistent journal logging for user services

    Note: Multiple steps can be combined and will run in correct logical order

    --steps-from STEP       Run from specified step to end

EXAMPLES:
    $0                                          # Full configuration
    $0 --force                                  # Full configuration, skip prompts

    # Single steps:
    $0 --journal                                # Only configure journal logging

    # Range of steps:
    $0 --steps-from journal                     # Run from journal config to end

EOF
}

show_help_long() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure ops host system settings

OPTIONS:
    -h, --help              Show this help message
    --help-long             Show detailed descriptions of each step
    -f, --force             Skip confirmation prompts

STEP OPTIONS (run individual or multiple steps):

DETAILED STEP DESCRIPTIONS:

1. --journal
   Configures persistent journal logging for systemd user services:
   - Enables Storage=persistent in /etc/systemd/journald.conf
   - Creates journal directory structure
   - Restarts systemd-journald service
   - Restarts user systemd instance for $TARGET_USER

   This allows viewing logs with: journalctl --user -u <service-name>

    --steps-from STEP       Run from specified step to end

EXAMPLES:
    $0                                          # Full configuration
    $0 --force                                  # Full configuration, skip prompts

    # Single steps:
    $0 --journal                                # Only configure journal logging

    # Range of steps:
    $0 --steps-from journal                     # Run from journal config to end

EOF
}

# Parse command line arguments
FORCE=false
STEPS_FROM=""

# Step flags
STEP_JOURNAL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h | --help)
            show_help
            exit 0
            ;;
        --help-long)
            show_help_long
            exit 0
            ;;
        -f | --force)
            FORCE=true
            shift
            ;;
        --journal)
            STEP_JOURNAL=true
            shift
            ;;
        --steps-from)
            if [[ -z "$2" ]]; then
                err "--steps-from requires a step name"
            fi
            STEPS_FROM="$2"
            shift 2
            ;;
        *)
            err "Unknown option: $1"
            ;;
    esac
done

# Check if running as root (after help parsing)
if [[ "$(id -u)" != "0" ]]; then
    err "This script must be run as root"
fi

# Handle --steps-from flag
if [[ -n "$STEPS_FROM" ]]; then
    case "$STEPS_FROM" in
        journal)
            STEP_JOURNAL=true
            ;;
        *)
            err "Invalid step name: $STEPS_FROM"
            ;;
    esac
fi

msg "Configuration script for ops host"
msg "All output is being logged to: $PWD/$LOG_FILE"

# Check if any step flags are set
ANY_STEP_FLAG=false
for flag in "$STEP_JOURNAL"; do
    if [[ "$flag" == true ]]; then
        ANY_STEP_FLAG=true
        break
    fi
done

# Only run confirmations for full configuration
if [[ "$ANY_STEP_FLAG" != true ]]; then
    # Confirmation unless --force
    if [[ "$FORCE" != true ]]; then
        echo
        msg "This will configure system settings on $HOSTNAME for user $TARGET_USER"
        read -p "Are you sure you want to continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            msg "Operation cancelled"
            exit 0
        fi
    fi
fi

# Helper function for step signposting
step_begin() {
    local step_name="$1"
    local restart_option="$2"
    echo
    msg "═══════════════════════════════════════════════════════════════"
    msg "🔄 STARTING: $step_name"
    msg "💡 To restart from this step: ./configure.sh --steps-from $restart_option"
    msg "═══════════════════════════════════════════════════════════════"
}

step_complete() {
    local step_name="$1"
    echo
    msg "═══════════════════════════════════════════════════════════════"
    msg "✅ COMPLETED: $step_name"
    msg "═══════════════════════════════════════════════════════════════"
    echo
}

# Step 1: Configure persistent journal logging
configure_journal() {
    msg "Configuring persistent journal logging..."

    # Check if journal script exists
    if [[ ! -f "$SCRIPT_DIR/07_sanity.sh" ]]; then
        err "07_sanity.sh not found at $SCRIPT_DIR/07_sanity.sh"
        return 1
    fi

    # Run journal configuration
    "$SCRIPT_DIR/07_sanity.sh" -u "$TARGET_USER" || {
        err "Journal configuration failed"
        return 1
    }

    msg "Journal configuration completed"
}

# Execute configuration steps
if [[ "$ANY_STEP_FLAG" == true ]]; then
    msg "Running selected configuration steps in correct order..."

    # Count selected steps for progress tracking
    selected_steps=()
    [[ "$STEP_JOURNAL" == true ]] && selected_steps+=("journal")

    msg "Selected steps (${#selected_steps[@]}): ${selected_steps[*]}"
    echo

    # Run individual steps in correct order (always run in logical sequence)
    [[ "$STEP_JOURNAL" == true ]] && {
        msg "Step 1: Configuring persistent journal logging..."
        configure_journal || exit 1
        msg "✓ Journal configuration completed"
        echo
    }

    msg "All selected steps completed successfully!"
else
    msg "Starting ops host configuration..."

    # Step 1: Configure journal logging
    step_begin "Step 1: Configuring persistent journal logging" "journal"
    configure_journal || {
        err "Journal configuration failed"
        exit 1
    }
    step_complete "Step 1: Configuring persistent journal logging"
fi

msg "Configuration completed successfully!"
msg "System features:"
msg "  - Hostname: $HOSTNAME"
msg "  - User: $TARGET_USER"
msg "  - Persistent journal logging: enabled"
echo
msg "Configuration log saved to: $PWD/$LOG_FILE"

exit 0
