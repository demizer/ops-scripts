#!/bin/bash

# Easy tar backup script with command line options
# Meant to be run as root
# Displays progress indicator when ran in the terminal

# This script uses the mail command to send emails.
# File and Error logs are sent to the following address:
EMAIL="nas@alva.rez.codes"

# Default values
DEFAULT_BACKUP_DIR="/mnt/backups"
DEFAULT_SOURCE_PATH="/"

# Script variables
# Keep only the last N backups
if [[ -n "$CUSTOM_KEEP" ]]; then
    REFRESH="$CUSTOM_KEEP"
else
    REFRESH=4
fi

# check if messages are to be printed using color
unset ALL_OFF BOLD BLUE GREEN RED YELLOW

# prefer terminal safe colored and bold text when tput is supported
if tput setaf 0 &> /dev/null; then
    ALL_OFF="$(tput sgr0)"
    BOLD="$(tput bold)"
    BLUE="${BOLD}$(tput setaf 4)"
    GREEN="${BOLD}$(tput setaf 2)"
    RED="${BOLD}$(tput setaf 1)"
    YELLOW="${BOLD}$(tput setaf 3)"
else
    ALL_OFF="\e[1;0m"
    BOLD="\e[1;1m"
    BLUE="${BOLD}\e[1;34m"
    GREEN="${BOLD}\e[1;32m"
    RED="${BOLD}\e[1;31m"
    YELLOW="${BOLD}\e[1;33m"
fi

readonly ALL_OFF BOLD BLUE GREEN RED YELLOW

plain() {
    local mesg=$1
    shift
    printf "${BOLD}    ${mesg}${ALL_OFF}\n" "$@" >&2
}

msg() {
    local mesg=$1
    shift
    printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

msgr() {
    local mesg=$1
    shift
    printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\r" "$@" >&2
}

msg2() {
    local mesg=$1
    shift
    printf "${BLUE}  ->${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

warning() {
    local mesg=$1
    shift
    printf "${YELLOW}==> "WARNING:"${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

error() {
    local mesg=$1
    shift
    printf "${RED}==> "ERROR:"${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

# $1 = Message
# $2 = Subject
# $3 = attachment
send_email() {
    if [[ "$SEND_EMAIL" != true ]]; then
        return 0
    fi

    if [[ $3 == "" ]]; then
        echo -e "${1}" | mail -s "${2}" "${EMAIL}" &> /dev/null
    else
        echo -e "${1}" | uuencode "${3}" "$(basename "${3}")" | mail -s "${2}" "${EMAIL}" &> /dev/null
    fi
}

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [SOURCE_PATH] [DEST_DIR]

Create compressed tar backup with progress display

ARGUMENTS:
    SOURCE_PATH     Path to backup (default: /)
    DEST_DIR        Directory where backup will be created (default: /mnt/backups)

OPTIONS:
    -h, --help      Show this help message
    -e, --email     Email address for notifications (default: nas@alva.rez.codes)
    -k, --keep      Number of old backups to keep (default: 4)
    --no-email      Disable email notifications
    --no-cleanup    Don't remove old backups

EXAMPLES:
    $0                              # Backup / to /mnt/backups
    $0 /home /backup/home           # Backup /home to /backup/home
    $0 --no-email /data /backup    # Backup /data to /backup without email
    $0 -k 10 /opt /mnt/backups     # Keep 10 old backups

EOF
}

# Parse command line arguments
SOURCE_PATH="$DEFAULT_SOURCE_PATH"
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
SEND_EMAIL=true
CLEANUP_BACKUPS=true
CUSTOM_KEEP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h | --help)
            show_help
            exit 0
            ;;
        -e | --email)
            EMAIL="$2"
            shift 2
            ;;
        -k | --keep)
            CUSTOM_KEEP="$2"
            shift 2
            ;;
        --no-email)
            SEND_EMAIL=false
            shift
            ;;
        --no-cleanup)
            CLEANUP_BACKUPS=false
            shift
            ;;
        -*)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [[ "$SOURCE_PATH" == "$DEFAULT_SOURCE_PATH" ]]; then
                SOURCE_PATH="$1"
            elif [[ "$BACKUP_DIR" == "$DEFAULT_BACKUP_DIR" ]]; then
                BACKUP_DIR="$1"
            else
                error "Too many arguments: $1"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate source path
if [[ ! -d "$SOURCE_PATH" ]]; then
    error "Source path does not exist: $SOURCE_PATH"
    exit 1
fi

# Make sure only root can run this script
if [[ "$(id -u)" != "0" ]]; then
    error "This script must be run as root"
    exit 1
fi

# Create backup directory with hostname subdirectory
BACKUP_DIR="${BACKUP_DIR%/}/$HOSTNAME"

# Check for backup directory
if [[ ! -e ${BACKUP_DIR} ]]; then
    mkdir -p ${BACKUP_DIR}
    msg "Created "${BACKUP_DIR}
    msg2 "Backing up to: "${BACKUP_DIR}
else
    msg "Backing up to: "${BACKUP_DIR}
fi

# Built-in exclusion patterns
# EXCLUDES="--exclude=/opt --exclude=/proc/* --exclude=/sys/* --exclude=/mnt/* --exclude=/media/* --exclude=/dev/* --exclude=/tmp/* --exclude=/data/* --exclude=/var/tmp/* --exclude=/var/abs/* --exclude=/run/* --exclude=/usr/* --exclude=*/lost+found --exclude=/home/*/.thumbnails --exclude=/home/*/.gvfs --exclude=/home/*/**/Trash/* --exclude=/home/*/.npm --exclude=/home/*/.[cC]*ache --exclude=/home/*/**/*Cache* --exclude=/home/*/.netflix* --exclude=/home/*/.dbus --exclude=/home/*/.cargo"
EXCLUDES="--exclude=${SOURCE_PATH}/opt --exclude=${SOURCE_PATH}/proc/* --exclude=${SOURCE_PATH}/sys/* --exclude=${SOURCE_PATH}/mnt/* --exclude=${SOURCE_PATH}/media/* --exclude=${SOURCE_PATH}/dev/* --exclude=${SOURCE_PATH}/tmp/* --exclude=${SOURCE_PATH}/data/* --exclude=${SOURCE_PATH}/var/tmp/* --exclude=${SOURCE_PATH}/var/abs/* --exclude=${SOURCE_PATH}/run/* --exclude=${SOURCE_PATH}/usr/* --exclude=${SOURCE_PATH}*/lost+found --exclude=${SOURCE_PATH}/home/*/.thumbnails --exclude=${SOURCE_PATH}/home/*/.gvfs --exclude=${SOURCE_PATH}/home/*/**/Trash/* --exclude=${SOURCE_PATH}/home/*/.npm --exclude=${SOURCE_PATH}/home/*/.[cC]*ache --exclude=${SOURCE_PATH}/home/*/**/*Cache* --exclude=${SOURCE_PATH}/home/*/.netflix* --exclude=${SOURCE_PATH}/home/*/.dbus --exclude=${SOURCE_PATH}/home/*/.cargo"

msg "Using built-in exclusion patterns"
msg "EXCLUDES=${EXCLUDES}"

FILENAME=$(echo $HOSTNAME)_backup_$(uname -r)_$(date +%m%d%Y).tar.xz

# Remove old backups if cleanup is enabled
if [[ "$CLEANUP_BACKUPS" == true ]]; then
    cd "${BACKUP_DIR}"
    count=$(\ls -tr | wc -l)
    if [[ $count -gt $REFRESH ]]; then
        msg2 "Cleaning up old backups (keeping last $REFRESH)"
        for ((a = 1; a <= $count - $REFRESH; a++)); do
            FILE=$(\ls -tr | head -n 1)
            rm ${FILE} 2>&1
            msg "Deleted "${FILE}
        done
    fi
fi

cat /dev/null > backuplog.txt;
cat /dev/null > backuplog-error.txt;

CALC="Calculating backup file list size... ";
(tar ${EXCLUDES} -cvpPf /dev/null "$SOURCE_PATH" > /tmp/logsize) &
PID1=$!
# msg "PID1=${PID1}"
msgr "${CALC}";
while [[ $(ps -p $PID1 -o pid=) ]]; do
    sleep 0.25;
    SIZE=`du /tmp/logsize | cut -f 1`;
    FSIZE=`printf "%'d" "${SIZE}"`;
    msgr "${CALC}${FSIZE}K";
done
echo

FIN_SIZE=`du /tmp/logsize | cut -f 1`;
if [[ -z ${FIN_SIZE} ]]; then
    error "Don't have a size to calculate!"
    exit 1;
fi

BACKM="Performing backup... "
msgr "${BACKM}"
BACKUP_START_TIME=$(date +%s)
(tar --xz ${EXCLUDES} -cvpPf ${BACKUP_DIR}/${FILENAME} "$SOURCE_PATH" \
    2> backuplog-error.txt > backuplog.txt;) &
PID2=$!

PREV_SIZE=0
PREV_TIME=$BACKUP_START_TIME
SPINNER_CHARS='/-\|'
SPINNER_INDEX=0

while [[ $(ps -p $PID2 -o pid=) ]]; do
    sleep 0.5
    CURRENT_TIME=$(date +%s)

    # Get spinner character
    SPINNER_CHAR=${SPINNER_CHARS:$SPINNER_INDEX:1}
    SPINNER_INDEX=$(( (SPINNER_INDEX + 1) % 4 ))

    # Count files processed (lines in log)
    if [[ -f "backuplog.txt" ]]; then
        FILE_COUNT=$(wc -l < "backuplog.txt" 2>/dev/null || echo 0)
    else
        FILE_COUNT=0
    fi

    if [[ -f "${BACKUP_DIR}/${FILENAME}" ]]; then
        BACKUP_SIZE_KB=$(du "${BACKUP_DIR}/${FILENAME}" | cut -f 1)
        BACKUP_SIZE_MB=$((BACKUP_SIZE_KB / 1024))

        # Calculate speed in MB/s
        TIME_DIFF=$((CURRENT_TIME - PREV_TIME))
        if [[ $TIME_DIFF -gt 0 ]]; then
            SIZE_DIFF_KB=$((BACKUP_SIZE_KB - PREV_SIZE))
            SIZE_DIFF_MB=$((SIZE_DIFF_KB / 1024))
            SPEED_MBS=$((SIZE_DIFF_MB / TIME_DIFF))
            PREV_SIZE=$BACKUP_SIZE_KB
            PREV_TIME=$CURRENT_TIME
        else
            SPEED_MBS=0
        fi

        # Calculate percentage based on log file size
        LOG_SIZE=`du backuplog.txt | cut -f 1`;
        PERC=$(( ${LOG_SIZE} * 100 / ${FIN_SIZE} ));
        FPERC=`printf "%2d" ${PERC}`;

        # Create progress bar (20 chars wide)
        PROGRESS_WIDTH=20
        FILLED_WIDTH=$((PERC * PROGRESS_WIDTH / 100))
        PROGRESS_BAR=""
        for ((i = 0; i < FILLED_WIDTH; i++)); do
            PROGRESS_BAR+="="
        done
        for ((i = FILLED_WIDTH; i < PROGRESS_WIDTH; i++)); do
            PROGRESS_BAR+=" "
        done

        printf "\r${GREEN}==>${ALL_OFF}${BOLD} [${PROGRESS_BAR}] ${FPERC}%% ${FILE_COUNT} files ${BACKUP_SIZE_MB}MB ${SPEED_MBS}MB/s ${SPINNER_CHAR}${ALL_OFF}" >&2;
    else
        LOG_SIZE=`du backuplog.txt | cut -f 1`;
        PERC=$(( ${LOG_SIZE} * 100 / ${FIN_SIZE} ));
        FPERC=`printf "%2d" ${PERC}`;

        # Create progress bar (20 chars wide)
        PROGRESS_WIDTH=20
        FILLED_WIDTH=$((PERC * PROGRESS_WIDTH / 100))
        PROGRESS_BAR=""
        for ((i = 0; i < FILLED_WIDTH; i++)); do
            PROGRESS_BAR+="="
        done
        for ((i = FILLED_WIDTH; i < PROGRESS_WIDTH; i++)); do
            PROGRESS_BAR+=" "
        done

        printf "\r${GREEN}==>${ALL_OFF}${BOLD} [${PROGRESS_BAR}] ${FPERC}%% ${FILE_COUNT} files ${SPINNER_CHAR}${ALL_OFF}" >&2;
    fi
done
echo

wait $PID2
TAR_EXIT_CODE=$?
TAR_FILE_SIZE=$(du -h "${BACKUP_DIR}/${FILENAME}" | cut -f 1)

msg2 "Compressing backuplog.txt...";
if [[ -f backuplog.zip ]]; then
    rm -f backuplog.zip
fi
zip backuplog.zip backuplog.txt backuplog-error.txt &> /dev/null

if [[ $TAR_EXIT_CODE > 1 ]]; then
    error "The backup was not successful!"
    if [[ "$SEND_EMAIL" == true ]]; then
        msg2 "Sending log to ${EMAIL}..."
        send_email "A problem occurred during backup.\n\nSource: $SOURCE_PATH\nDestination: $BACKUP_DIR\nExit code: \
${TAR_EXIT_CODE}\nBackup file size: ${TAR_FILE_SIZE}" \
            "$HOSTNAME Backup FAILED" backuplog.zip
        msg2 "Done"
    fi
else
    msg2 "Backup completed successfully."
    if [[ "$SEND_EMAIL" == true ]]; then
        msg2 "Sending log to ${EMAIL}..."
        send_email "Backup completed successfully.\n\nSource: $SOURCE_PATH\nDestination: $BACKUP_DIR\nExit code: \
${TAR_EXIT_CODE}\nBackup file size: ${TAR_FILE_SIZE}" \
            "$HOSTNAME Backup SUCCESSFUL" backuplog.zip
        msg2 "Done"
    fi
fi
