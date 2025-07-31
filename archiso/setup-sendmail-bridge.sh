#!/bin/bash

# Arch Linux msmtp Setup Script for Proton Mail Bridge
# Configures msmtp to send mail via local Proton Mail Bridge
# Based on configuration from /home/jesusa/bigbrain/bigbrain/Sys Admin/Proton Mail.md

# Color output functions (matching tar-backup.sh style)
unset ALL_OFF BOLD BLUE GREEN RED YELLOW

if tput setaf 0 &>/dev/null; then
    ALL_OFF="$(tput sgr0)";
    BOLD="$(tput bold)";
    BLUE="${BOLD}$(tput setaf 4)";
    GREEN="${BOLD}$(tput setaf 2)";
    RED="${BOLD}$(tput setaf 1)";
    YELLOW="${BOLD}$(tput setaf 3)";
else
    ALL_OFF="\\e[1;0m";
    BOLD="\\e[1;1m";
    BLUE="${BOLD}\\e[1;34m";
    GREEN="${BOLD}\\e[1;32m";
    RED="${BOLD}\\e[1;31m";
    YELLOW="${BOLD}\\e[1;33m";
fi

readonly ALL_OFF BOLD BLUE GREEN RED YELLOW;

msg() {
    local mesg=$1; shift
    printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2;
}

msg2() {
    local mesg=$1; shift
    printf "${BLUE}  ->${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2;
}

warning() {
    local mesg=$1; shift
    printf "${YELLOW}==> WARNING:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2;
}

error() {
    local mesg=$1; shift
    printf "${RED}==> ERROR:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2;
}

# Proton Mail Bridge Configuration (network bridge)
BRIDGE_HOST="ops.alvaone.net"
BRIDGE_PORT="1025"
BRIDGE_USER="ops@alva.rez.codes"

# Prompt for bridge password if not set in environment
if [[ -z "$BRIDGE_PASSWORD" ]]; then
    msg2 "Proton Mail Bridge password required for authentication";
    echo -n "Enter bridge password: "
    read -s BRIDGE_PASSWORD
    echo
    if [[ -z "$BRIDGE_PASSWORD" ]]; then
        error "Bridge password is required";
        exit 1;
    fi
fi

# Check for test flag
TEST_MODE=false
if [[ "$1" == "--test" ]]; then
    TEST_MODE=true
fi

# Test mode - only send test email
if [[ "$TEST_MODE" == true ]]; then
    msg "Sending test email via msmtp...";
    TEST_MESSAGE="Test email from archiso at $(date)"
    TEST_SUBJECT="msmtp Test from archiso"
    
    if echo -e "Subject: $TEST_SUBJECT\n\n$TEST_MESSAGE" | msmtp "$BRIDGE_USER" &>/dev/null; then
        msg "Test email sent successfully to $BRIDGE_USER";
    else
        error "Failed to send test email";
        exit 1;
    fi
    exit 0;
fi

# Check if running as root
if [[ "$(id -u)" != "0" ]]; then
    error "This script must be run as root";
    exit 1;
fi

msg "Setting up msmtp for Proton Mail Bridge on Arch Linux";

# Verify msmtp is installed (should be pre-installed in the ISO)
if ! command -v msmtp &>/dev/null; then
    error "msmtp is not installed. This script expects msmtp to be pre-installed in the ISO.";
    exit 1;
fi

msg2 "msmtp found - proceeding with configuration";

# Check if msmtp is already configured for bridge
if [[ -f /etc/msmtprc ]] && grep -q "ops.alvaone.net" /etc/msmtprc; then
    msg "msmtp is already configured for Proton Mail Bridge";
    exit 0;
fi

# Backup existing msmtp configuration if it exists
if [[ -f /etc/msmtprc ]]; then
    msg2 "Backing up existing msmtp configuration...";
    cp /etc/msmtprc /etc/msmtprc.backup.$(date +%Y%m%d_%H%M%S)
fi

# Test bridge connectivity
msg2 "Testing Proton Mail Bridge connectivity...";
if ! nc -z ${BRIDGE_HOST} ${BRIDGE_PORT} 2>/dev/null; then
    warning "Cannot connect to Proton Mail Bridge at ${BRIDGE_HOST}:${BRIDGE_PORT}";
    warning "Make sure the Proton Mail Bridge is running on your network";
fi

# Create msmtp configuration
msg2 "Creating msmtp configuration...";
cat > /etc/msmtprc << EOF
# Default settings for all accounts
defaults
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
syslog on

# Proton Mail Bridge account
account proton
host ${BRIDGE_HOST}
port ${BRIDGE_PORT}
from ${BRIDGE_USER}
auth login
user ${BRIDGE_USER}
password ${BRIDGE_PASSWORD}
tls off

# Set default account
account default : proton
EOF

# Secure the msmtp config file
chmod 600 /etc/msmtprc

# Create aliases file for mail command compatibility
msg2 "Creating aliases file...";
cat > /etc/aliases << EOF
# Basic aliases for msmtp
default: ${BRIDGE_USER}
postmaster: ${BRIDGE_USER}
abuse: ${BRIDGE_USER}
spam: ${BRIDGE_USER}
mailer-daemon: ${BRIDGE_USER}
root: ${BRIDGE_USER}
EOF

# Create symbolic link for sendmail compatibility
msg2 "Creating sendmail compatibility link...";
ln -sf /usr/bin/msmtp /usr/sbin/sendmail
ln -sf /usr/bin/msmtp /usr/bin/sendmail

# Test msmtp configuration
msg2 "Testing msmtp configuration...";
if msmtp --serverinfo --account=proton &>/dev/null; then
    msg "msmtp configuration test passed";
else
    warning "msmtp configuration test had warnings (check bridge connectivity)";
fi

msg "msmtp setup completed successfully!";
msg2 "Configuration files created/modified:";
msg2 "  - /etc/msmtprc (secured with 600 permissions)";
msg2 "  - /etc/aliases";
msg2 "  - /usr/sbin/sendmail -> /usr/bin/msmtp (compatibility link)";

warning "IMPORTANT: Make sure Proton Mail Bridge is running at ${BRIDGE_HOST}:${BRIDGE_PORT}";
msg2 "To test email functionality, run:";
msg2 "$0 --test";

msg2 "To view msmtp logs, run:";
msg2 "journalctl -t msmtp -f";