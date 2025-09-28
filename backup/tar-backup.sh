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
    REFRESH=10
fi

# Default exclusion patterns
EXCLUDE_PATTERNS=(
    # "/opt"
    # "/usr/*"
    "/proc/*"
    "/sys/*"
    "/mnt/*"
    "/media/*"
    "/dev/*"
    "/tmp/*"
    "/data/*"
    "/var/tmp/*"
    "/var/abs/*"
    "/run/*"
    "*/lost+found"
    "/home/*/.thumbnails"
    "/home/*/.gvfs"
    "/home/*/**/Trash/*"
    "/home/*/.npm"
    "/home/*/.[cC]*ache"
    "/home/*/**/*Cache*"
    "/home/*/.netflix*"
    "/home/*/.dbus"
    "/home/*/.cargo"
)

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
        # Use mail with attachment flag if available, otherwise fall back to inline base64
        if command -v mail >/dev/null 2>&1 && mail --help 2>&1 | grep -q "\-a"; then
            echo -e "${1}" | mail -s "${2}" -a "${3}" "${EMAIL}" &> /dev/null
        else
            {
                echo -e "${1}"
                echo ""
                echo "=== Attachment: $(basename "${3}") ==="
                base64 "${3}"
            } | mail -s "${2}" "${EMAIL}" &> /dev/null
        fi
    fi
}

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [SOURCE_PATH] [DEST_DIR_OR_FILE]

Create compressed tar backup with progress display

ARGUMENTS:
    SOURCE_PATH         Path to backup (default: /)
    DEST_DIR_OR_FILE    Directory where backup will be created (default: /mnt/backups)
                        OR full path to .tpxz file

OPTIONS:
    -h              Show this help message
    --help          Show this help message with exclusions list
    -e, --email     Email address for notifications (default: nas@alva.rez.codes)
    -k, --keep      Number of old backups to keep (default: 10)
    --no-email      Disable email notifications
    --no-cleanup    Don't remove old backups
    --excludes      Show default exclusion patterns

EXAMPLES:
    $0                                     # Backup / to /mnt/backups (Backup will be saved to /mnt/backups/hostname)
    $0 /home /backup/home                  # Backup /home to /backup/home (Backup will be saved to /backup/home/hostname)
    $0 /source /mnt/backups/destfile.tpxz  # Backup /source to exact file
    $0 --no-email /data /backup            # Backup /data to /backup without email
    $0 -k 10 /opt /mnt/backups             # Keep 10 old backups

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
        -h)
            show_help
            exit 0
            ;;
        --help)
            show_help
            echo "DEFAULT EXCLUSION PATTERNS:"
            printf "  * %s\n" "${EXCLUDE_PATTERNS[@]}"
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
        --excludes)
            echo "Default exclusion patterns:"
            printf "  * %s\n" "${EXCLUDE_PATTERNS[@]}"
            exit 0
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

# Check if pixz is available
if ! command -v pixz &> /dev/null; then
    error "pixz is not installed or not in PATH"
    msg2 "Please install pixz package for parallel XZ compression"
    exit 1
fi

# Make sure the raid pool is mounted if on lithium
if [[ $HOSTNAME == "lithium" ]]; then
    MOUNT=$(mount | grep /mnt/data)
    if [[ ${MOUNT} == "" ]]; then
        error "bigdata zpool is not mounted!"
        msg2 "Sending email to \"$EMAIL\"..."
        send_email "backup-tar could not find the bigdata zpool!" \
            "bigdata zpool not mounted on lithium!"
        msg2 "Done"
        exit 1
    else
        msg "bigdata zpool detected"
    fi
fi

# Check if BACKUP_DIR is actually a .tpxz file path
if [[ "$BACKUP_DIR" == *.tpxz ]]; then
    # Extract directory and filename
    DEST_FILE="$BACKUP_DIR"
    BACKUP_DIR="$(dirname "$BACKUP_DIR")"
    USE_CUSTOM_FILENAME=true
else
    # Create backup directory with hostname subdirectory (original behavior)
    BACKUP_DIR="${BACKUP_DIR%/}/$HOSTNAME"
    USE_CUSTOM_FILENAME=false
fi

# Check for backup directory
if [[ ! -e ${BACKUP_DIR} ]]; then
    mkdir -p ${BACKUP_DIR}
    msg "Created "${BACKUP_DIR}
    msg2 "Backing up to: "${BACKUP_DIR}
else
    msg "Backing up to: "${BACKUP_DIR}
fi

# Build exclusion flags from array
EXCLUDES=""
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    EXCLUDES="$EXCLUDES --exclude='$pattern'"
done
msg "Using built-in exclusion patterns"

if [[ "$USE_CUSTOM_FILENAME" == true ]]; then
    FILENAME="$(basename "$DEST_FILE")"
else
    FILENAME=$(echo $HOSTNAME)_backup_$(uname -r)_$(date +%m%d%Y).tpxz
fi

# Remove old backups if cleanup is enabled and not using custom filename
if [[ "$CLEANUP_BACKUPS" == true && "$USE_CUSTOM_FILENAME" != true ]]; then
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

TEMP_DIR=$(mktemp -d ./tmp.XXXX)
BACKUP_LOG="${TEMP_DIR}/backuplog.txt"
BACKUP_ERROR_LOG="${TEMP_DIR}/backuplog-error.txt"
cat /dev/null > "$BACKUP_LOG"
cat /dev/null > "$BACKUP_ERROR_LOG"

CALC="Calculating backup file list size... "
msgr "${CALC}"
(tar ${EXCLUDES} -cvpPf /dev/null "$SOURCE_PATH" > ${PWD}/logsize 2> /dev/null) &
PID1=$!

while [[ $(ps -p $PID1 -o pid=) ]]; do
    sleep 0.25
    PFILE_COUNT=$(wc -l < "${PWD}/logsize" 2> /dev/null || echo 0)
    # SIZE=$(wc -l ${PWD}/logsize | cut -f 1)
    # FSIZE=$(printf "%'d" "${SIZE}")
    msgr "\033[K${CALC}${PFILE_COUNT} files"
done
echo

FILE_COUNT_TOTAL=$(cat ${PWD}/logsize | wc -l)

BACKM="Performing backup... "
msgr "${BACKM}"
BACKUP_START_TIME=$(date +%s)

tar ${EXCLUDES} -Ipixz -cvpPf ${BACKUP_DIR}/${FILENAME} "$SOURCE_PATH" 2>"$BACKUP_ERROR_LOG" 1>"$BACKUP_LOG" &

PID2=$!

PREV_SIZE=0
PREV_TIME=$BACKUP_START_TIME
SPINNER_CHARS='/-\|'
SPINNER_INDEX=0

while [[ $(ps -p $PID2 -o pid=) ]]; do
    sleep 0.5
    MAX_COLUMNS=$(tput cols)
    CURRENT_TIME=$(date +%s)
    PROGRESS_BAR_COLS=4 # for for the arrow and space

    # Get spinner character
    SPINNER_CHAR=${SPINNER_CHARS:$SPINNER_INDEX:1}
    SPINNER_INDEX=$(((SPINNER_INDEX + 1) % 4))
    PROGRESS_BAR_COLS=$((PROGRESS_BAR_COLS + 1 + 1)) # 1=spinner 1=space

    # Count files processed (lines in log)
    if [[ -f "$BACKUP_LOG" ]]; then
	# ughhhh....
        FILE_COUNT=$(wc -l < "$BACKUP_LOG" 2> /dev/null || echo 0)
    else
        FILE_COUNT=0
    fi
    PROGRESS_BAR_COLS=$((PROGRESS_BAR_COLS + ${#FILE_COUNT} + ${#FILE_COUNT_TOTAL} + 2 + 2 + 1 + 5)) # 2=[] 2=space 1=/ 5=files

    if [[ -f "${BACKUP_DIR}/${FILENAME}" ]]; then
        BACKUP_SIZE_KB=$(du "${BACKUP_DIR}/${FILENAME}" | cut -f 1)
        BACKUP_SIZE_MB=$(du -m "${BACKUP_DIR}/${FILENAME}" | cut -f 1)
        BACKUP_SIZE_HR=$(du -h "${BACKUP_DIR}/${FILENAME}" | cut -f 1)
        PROGRESS_BAR_COLS=$((PROGRESS_BAR_COLS + ${#BACKUP_SIZE_HR} + 1)) # +1 for space

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
	# PROGRESS_BAR_COLS=$((PROGRESS_BAR_COLS + ${#SPEED_MBS} + 1 + 4 )) # 1=space, 4=mb/s
	PROGRESS_BAR_COLS=$((PROGRESS_BAR_COLS + 1 + 4 + 5 )) # 1=space, 4=text 4=mb/s

        # bash math sux
        PERC=$(python3 -c "print(round((${FILE_COUNT} / ${FILE_COUNT_TOTAL}) * 100))")
	if [[ ${PERC} -gt 100 ]]; then
	    # rounding error
	    PERC="100"
	fi
	PROGRESS_BAR_COLS=$((PROGRESS_BAR_COLS + ${#PERC} + 1 + 1)) # 1=space 1=%

	PROGRESS_WIDTH=$((MAX_COLUMNS - PROGRESS_BAR_COLS - 2 - 2)) # 2=space 2=[] 3=adjustment
	FILLED_WIDTH=$(python3 -c "print(round((${PERC} / ${PROGRESS_WIDTH}) * 100))")
	if [[ ${FILLED_WIDTH} -gt 100 ]]; then
	    FILLED_WIDTH=100
	fi
        PROGRESS_BAR=""
        for ((i = 0; i < FILLED_WIDTH; i++)); do
            PROGRESS_BAR+="="
        done
        for ((i = FILLED_WIDTH; i < PROGRESS_WIDTH; i++)); do
            PROGRESS_BAR+=" "
        done

        printf "\r\033[K${GREEN}==>${ALL_OFF}${BOLD} [${PROGRESS_BAR}] %3s%% [${FILE_COUNT}/${FILE_COUNT_TOTAL} files] ${BACKUP_SIZE_HR} %4sMB/s ${SPINNER_CHAR}${ALL_OFF}" "${PERC}" "${SPEED_MBS}"  >&2

	# echo
	# echo "pb_width: $PROGRESS_WIDTH"
	# echo "pb_fill: $FILLED_WIDTH"
	# echo "used_cols: $PROGRESS_BAR_COLS"
	# echo "max_cols: $MAX_COLUMNS"


    else



        LOG_SIZE=$(du "$BACKUP_LOG" | cut -f 1)
        if [[ ${LOG_FIN_SIZE} -gt 0 ]]; then
            PERC=$((${LOG_SIZE} * 100 / ${LOG_FIN_SIZE}))
        else
            PERC=0
        fi
        FPERC=$(printf "%2d" ${PERC})

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

        printf "\r\033[K${GREEN}==>${ALL_OFF}${BOLD} [${PROGRESS_BAR}] ${FPERC}%% ${FILE_COUNT} files ${SPINNER_CHAR}${ALL_OFF}" >&2
    fi
done
echo

wait $PID2
TAR_EXIT_CODE=$?
TAR_FILE_SIZE=$(du -h "${BACKUP_DIR}/${FILENAME}" | cut -f 1)

exit $TAR_EXIT_CODE

# cd "$TEMP_DIR"
#
# msg2 "Compressing backuplog.txt..."
# if [[ -f backuplog.zip ]]; then
#     rm -f backuplog.zip
# fi
# zip backuplog.zip backuplog.txt backuplog-error.txt &> /dev/null
#
# if [[ $TAR_EXIT_CODE > 1 ]]; then
#     error "The backup was not successful!"
#     if [[ "$SEND_EMAIL" == true ]]; then
#         msg2 "Sending log to ${EMAIL}..."
#         send_email "A problem occurred during backup.\n\nSource: $SOURCE_PATH\nDestination: $BACKUP_DIR\nExit code: \
# ${TAR_EXIT_CODE}\nBackup file size: ${TAR_FILE_SIZE}" \
#             "$HOSTNAME Backup FAILED" "${TEMP_DIR}/backuplog.zip"
#         msg2 "Done"
#     fi
# else
#     msg2 "Backup completed successfully."
#     if [[ "$SEND_EMAIL" == true ]]; then
#         msg2 "Sending log to ${EMAIL}..."
#         send_email "Backup completed successfully.\n\nSource: $SOURCE_PATH\nDestination: $BACKUP_DIR\nExit code: \
# ${TAR_EXIT_CODE}\nBackup file size: ${TAR_FILE_SIZE}" \
#             "$HOSTNAME Backup SUCCESSFUL" "${TEMP_DIR}/backuplog.zip"
#         msg2 "Done"
#     fi
# fi
