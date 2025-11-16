#!/bin/bash

# Journal configuration script for ops host (AlmaLinux 10)
# Enables persistent journal logging for systemd user services

# Load common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib.sh"

# Pre-populated configuration
TARGET_USER="${TARGET_USER:-jesusa}"
JOURNALD_CONF="/etc/systemd/journald.conf"

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure persistent journal logging for systemd user services on ops (AlmaLinux 10)

OPTIONS:
    -h, --help              Show this help message
    -u, --user USERNAME     Target user (default: jesusa)

CHECKS PERFORMED:
    - User exists on system
    - Journal configuration is updated
    - Journal directories are created
    - systemd-journald is restarted and operational
    - User systemd instance is restarted
    - Journal files are created or will be created on next log

EXAMPLES:
    $0
    $0 -u jesusa
    $0 --help

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h | --help)
            show_help
            exit 0
            ;;
        -u | --user)
            TARGET_USER="$2"
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

# Verify target user exists
if ! id "$TARGET_USER" &> /dev/null; then
    err "User $TARGET_USER does not exist"
fi

msg "Configuring persistent journal logging for user $TARGET_USER on AlmaLinux 10"

# Track failed checks
FAILED_CHECKS=0

# Helper function to report check results
check_result() {
    local check_name="$1"
    local success="$2"
    local details="$3"

    if [[ "$success" == "true" ]]; then
        msg "✓ $check_name"
        [[ -n "$details" ]] && msg "  $details"
    else
        warn "✗ $check_name"
        [[ -n "$details" ]] && warn "  $details"
        ((FAILED_CHECKS++))
    fi
}

# Step 1: Check current journal configuration
msg "Step 1: Checking current journal configuration..."
current_storage=$(cat "$JOURNALD_CONF" | grep -E "^Storage=" 2> /dev/null || echo "")

if [[ -n "$current_storage" ]]; then
    msg "Current configuration: $current_storage"
else
    msg "Storage setting is commented out or not present (using default)"
fi

# Step 2: Enable persistent user journals
msg "Step 2: Enabling persistent user journals..."

# Create journal directory
msg "Creating journal directory..."
machine_id=$(systemd-id128 machine-id)
msg "Machine ID: $machine_id"

if run_cmd_no_subshell mkdir -p "/var/log/journal/$machine_id"; then
    check_result "Journal directory created" "true" "/var/log/journal/$machine_id"
else
    check_result "Journal directory created" "false" "Failed to create directory"
fi

# Run systemd-tmpfiles to create proper structure
msg "Running systemd-tmpfiles to create journal structure..."
if run_cmd_no_subshell systemd-tmpfiles --create --prefix /var/log/journal; then
    check_result "systemd-tmpfiles completed" "true"
else
    check_result "systemd-tmpfiles completed" "false"
fi

# Set persistent storage in journald config
msg "Configuring Storage=persistent in $JOURNALD_CONF..."
run_cmd_no_subshell sed -i 's/^#Storage=.*/Storage=persistent/' "$JOURNALD_CONF"

# If the line doesn't exist, add it
if ! grep -q '^Storage=' "$JOURNALD_CONF"; then
    msg "Storage= line not found, adding it..."
    echo 'Storage=persistent' | tee -a "$JOURNALD_CONF" > /dev/null
fi

# Verify the change
if grep -q "^Storage=persistent" "$JOURNALD_CONF"; then
    check_result "Storage=persistent configured" "true" "$JOURNALD_CONF"
else
    check_result "Storage=persistent configured" "false" "Failed to update $JOURNALD_CONF"
fi

# Restart journald
msg "Restarting systemd-journald..."
if run_cmd_no_subshell systemctl restart systemd-journald; then
    check_result "systemd-journald restarted" "true"
else
    check_result "systemd-journald restarted" "false"
fi

# Verify journald is running
if systemctl is-active systemd-journald &> /dev/null; then
    check_result "systemd-journald is active" "true"
else
    check_result "systemd-journald is active" "false"
fi

# Step 3: Restart user session for changes to take effect
msg "Step 3: Restarting user systemd instance for $TARGET_USER..."

# Get user UID
user_uid=$(id -u "$TARGET_USER")
msg "User $TARGET_USER UID: $user_uid"

# Restart user systemd instance
msg "Executing daemon-reexec for user $TARGET_USER..."
if run_cmd_no_subshell sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$user_uid" systemctl --user daemon-reexec; then
    check_result "User systemd instance restarted" "true" "$TARGET_USER"
else
    check_result "User systemd instance restarted" "false" "daemon-reexec failed"
fi

# Step 4: Verify journals are working
msg "Step 4: Verifying journal configuration..."

# Check if journal directory exists
if [[ -d "/var/log/journal/$machine_id" ]]; then
    check_result "Journal directory exists" "true" "/var/log/journal/$machine_id"
else
    check_result "Journal directory exists" "false" "Directory not found"
fi

# Check if user journal files exist
user_journal_pattern="/var/log/journal/*/user-$user_uid.journal*"
if ls $user_journal_pattern &> /dev/null; then
    journal_count=$(ls $user_journal_pattern 2> /dev/null | wc -l)
    check_result "User journal files exist" "true" "$journal_count file(s) for UID $user_uid"
else
    msg "ℹ User journal files not yet created (will be created when services generate logs)"
    check_result "User journal files ready" "true" "Will be created on first log entry"
fi

# Summary
echo
if [[ $FAILED_CHECKS -eq 0 ]]; then
    msg "✅ All checks passed! Persistent journal logging is configured."
    msg ""
    msg "To view user service logs, run as $TARGET_USER:"
    msg "  journalctl --user -u <service-name>"
    msg "  journalctl --user -u <service-name> -f          # Follow logs"
    msg "  journalctl --user -u <service-name> -n 100      # Last 100 lines"
    msg ""
    msg "Example for immich-server service:"
    msg "  journalctl --user -u immich-server.service -f"
    msg ""
    msg "Alternative (if journals not yet generated):"
    msg "  systemctl --user status -l -n 500 immich-server.service --no-pager"
    exit 0
else
    warn "❌ $FAILED_CHECKS check(s) failed!"
    warn "Journal logging may not work properly."
    warn "Review the failed checks above and fix the issues."
    exit 1
fi
