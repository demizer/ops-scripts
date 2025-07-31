#!/bin/bash

# Arch Linux Sendmail Setup Script for Proton Mail Bridge
# Configures sendmail to send mail via local Proton Mail Bridge
# Based on configuration from /home/jesusa/bigbrain/bigbrain/Sys Admin/Proton Mail.md

# Update package database for Arch Linux live ISO
msg "Updating package database..."
pacman -Syy

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

# Test mode - only send test email
if [[ "$TEST_MODE" == true ]]; then
    msg "Sending test email via sendmail...";
    TEST_MESSAGE="Test email from archiso at $(date)"
    TEST_SUBJECT="Sendmail Test from archiso"
    
    if echo "$TEST_MESSAGE" | mail -s "$TEST_SUBJECT" "$BRIDGE_USER" &>/dev/null; then
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

msg "Setting up sendmail for Proton Mail Bridge on Arch Linux";

# Check if sendmail is already installed
if ! pacman -Q sendmail &>/dev/null; then
    msg2 "Installing sendmail...";
    pacman -S --noconfirm sendmail
else
    msg2 "Sendmail already installed";
fi

# Check if sendmail is already configured for bridge
if [[ -f /etc/mail/sendmail.cf ]] && grep -q "ops.alvaone.net.*1025" /etc/mail/sendmail.cf; then
    msg "Sendmail is already configured for Proton Mail Bridge";
    exit 0;
fi

# Backup existing sendmail configuration if it exists
if [[ -f /etc/mail/sendmail.cf ]]; then
    msg2 "Backing up existing sendmail configuration...";
    cp /etc/mail/sendmail.cf /etc/mail/sendmail.cf.backup.$(date +%Y%m%d_%H%M%S)
fi

# Create sendmail configuration directory if it doesn't exist
mkdir -p /etc/mail

# Test bridge connectivity
msg2 "Testing Proton Mail Bridge connectivity...";
if ! nc -z ${BRIDGE_HOST} ${BRIDGE_PORT} 2>/dev/null; then
    warning "Cannot connect to Proton Mail Bridge at ${BRIDGE_HOST}:${BRIDGE_PORT}";
    warning "Make sure the Proton Mail Bridge is running on your network";
fi

# Create sendmail.mc configuration
msg2 "Creating sendmail configuration...";
cat > /etc/mail/sendmail.mc << 'EOF'
divert(-1)dnl
include(`/usr/share/sendmail-cf/m4/cf.m4')dnl
VERSIONID(`sendmail.mc')dnl
OSTYPE(`linux')dnl

dnl # Basic sendmail configuration for send-only via SMTP relay
define(`confDONT_PROBE_INTERFACES', `True')dnl
define(`PROCMAIL_MAILER_PATH', `/usr/bin/procmail')dnl
define(`ALIAS_FILE', `/etc/aliases')dnl
define(`STATUS_FILE', `/var/log/mail/statistics')dnl
define(`UUCP_MAILER_MAX', `2000000')dnl
define(`confUSERDB_SPEC', `/etc/mail/userdb.db')dnl
define(`confPRIVACY_FLAGS', `authwarnings,novrfy,noexpn,restrictqrun')dnl
define(`confTO_CONNECT', `1m')dnl
define(`confTRY_NULL_MX_LIST', `True')dnl
define(`confDONT_PROBE_INTERFACES', `True')dnl
define(`PROCMAIL_MAILER_PATH', `/usr/bin/procmail')dnl

dnl # Smart host configuration for Proton Mail Bridge
define(`SMART_HOST', `[ops.alvaone.net]')dnl
define(`RELAY_MAILER_ARGS', `TCP $h 1025')dnl
define(`ESMTP_MAILER_ARGS', `TCP $h 1025')dnl

dnl # SMTP Authentication
define(`confAUTH_OPTIONS', `A p y')dnl
TRUST_AUTH_MECH(`EXTERNAL DIGEST-MD5 CRAM-MD5 LOGIN PLAIN')dnl
define(`confAUTH_MECHANISMS', `EXTERNAL GSSAPI DIGEST-MD5 CRAM-MD5 LOGIN PLAIN')dnl

dnl # Masquerading - rewrite sender addresses
MASQUERADE_AS(`alva.rez.codes')dnl
FEATURE(`masquerade_envelope')dnl
FEATURE(`masquerade_entire_domain')dnl

dnl # Enable local delivery for compatibility
FEATURE(`msp', `[ops.alvaone.net]', `1025')dnl

dnl # Standard features
FEATURE(`access_db')dnl
FEATURE(`blacklist_recipients')dnl
FEATURE(`accept_unresolvable_domains')dnl
FEATURE(`accept_unqualified_senders')dnl
FEATURE(`relay_based_on_MX')dnl

dnl # Mailer definitions
MAILER(`local')dnl
MAILER(`smtp')dnl
EOF

# Generate sendmail.cf from sendmail.mc
msg2 "Generating sendmail.cf configuration...";
cd /etc/mail
m4 sendmail.mc > sendmail.cf

# Create submit.mc for client submission
msg2 "Creating submit.mc configuration...";
cat > /etc/mail/submit.mc << 'EOF'
divert(-1)dnl
include(`/usr/share/sendmail-cf/m4/cf.m4')dnl
VERSIONID(`submit.mc')dnl
OSTYPE(`linux')dnl

define(`confCF_VERSION', `Submit')dnl
define(`__OSTYPE__',`')dnl
define(`_USE_DECNET_SYNTAX_', `1')dnl
define(`confTIME_ZONE', `USE_TZ')dnl
define(`confDONT_PROBE_INTERFACES', `True')dnl

FEATURE(`msp', `[ops.alvaone.net]', `1025')dnl
EOF

# Generate submit.cf
m4 submit.mc > submit.cf

# Create aliases file
msg2 "Creating aliases file...";
cat > /etc/aliases << EOF
# Basic aliases
postmaster: root
abuse: root
spam: root
mailer-daemon: root

# Forward root mail to bridge user
root: ${BRIDGE_USER}
EOF

# Create local-host-names file
msg2 "Creating local-host-names...";
cat > /etc/mail/local-host-names << EOF
localhost
archiso
archiso.local
EOF

# Create access database (empty but required)
touch /etc/mail/access
makemap hash /etc/mail/access < /etc/mail/access

# Create auth-info file for SMTP authentication
msg2 "Creating SMTP authentication file...";
cat > /etc/mail/auth-info << EOF
AuthInfo:ops.alvaone.net "U:${BRIDGE_USER}" "P:${BRIDGE_PASSWORD}" "M:LOGIN PLAIN"
EOF

# Secure the auth-info file
chmod 600 /etc/mail/auth-info
makemap hash /etc/mail/auth-info < /etc/mail/auth-info

# Build aliases database
newaliases

# Create mail directories
mkdir -p /var/spool/mqueue
mkdir -p /var/log/mail
chown root:mail /var/spool/mqueue
chmod 755 /var/spool/mqueue

# Enable and start sendmail
msg2 "Enabling and starting sendmail service...";
systemctl enable sendmail
systemctl restart sendmail

# Test sendmail configuration
msg2 "Testing sendmail configuration...";
if sendmail -bt < /dev/null &>/dev/null; then
    msg "Sendmail configuration test passed";
else
    warning "Sendmail configuration test had warnings (this may be normal)";
fi

msg "Sendmail setup completed successfully!";
msg2 "Configuration files created/modified:";
msg2 "  - /etc/mail/sendmail.cf";
msg2 "  - /etc/mail/submit.cf";
msg2 "  - /etc/aliases";
msg2 "  - /etc/mail/local-host-names";
msg2 "  - /etc/mail/auth-info (secured with 600 permissions)";

warning "IMPORTANT: Make sure Proton Mail Bridge is running at ${BRIDGE_HOST}:${BRIDGE_PORT}";
msg2 "To test email functionality, run:";
msg2 "$0 --test";

msg2 "To view sendmail logs, run:";
msg2 "journalctl -u sendmail -f";