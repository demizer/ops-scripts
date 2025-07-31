#!/bin/bash

# Easy tar backup script
# Meant to be run as root
# Displays progress indicator when ran in the terminal

# This script uses the mail command to send emails.
# File and Error logs are sent to the following address:
EMAIL="nas@alva.rez.codes"

# The directory backups will be saved to
BACKUP_DIR="/mnt/backups"

# The FULL path of the exclude file
# TODO: NEED TO ALLOW SETTING THIS!
EXCLUDE_FILE_NAME="/home/demizer/bin/backup-excludes.txt"

# Script variables
# Keep only the last N backups
if [[ $HOSTNAME == "lithium" ]]; then
    REFRESH=6;
else
    REFRESH=4;
fi

# check if messages are to be printed using color
unset ALL_OFF BOLD BLUE GREEN RED YELLOW

# prefer terminal safe colored and bold text when tput is supported
if tput setaf 0 &>/dev/null; then
    ALL_OFF="$(tput sgr0)";
    BOLD="$(tput bold)";
    BLUE="${BOLD}$(tput setaf 4)";
    GREEN="${BOLD}$(tput setaf 2)";
    RED="${BOLD}$(tput setaf 1)";
    YELLOW="${BOLD}$(tput setaf 3)";
else
    ALL_OFF="\e[1;0m";
    BOLD="\e[1;1m";
    BLUE="${BOLD}\e[1;34m";
    GREEN="${BOLD}\e[1;32m";
    RED="${BOLD}\e[1;31m";
    YELLOW="${BOLD}\e[1;33m";
fi

readonly ALL_OFF BOLD BLUE GREEN RED YELLOW;

plain() {
	local mesg=$1; shift
	printf "${BOLD}    ${mesg}${ALL_OFF}\n" "$@" >&2;
}

msg() {
	local mesg=$1; shift
	printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2;
}

msgr() {
	local mesg=$1; shift
	printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\r" "$@" >&2;
}

msg2() {
	local mesg=$1; shift
	printf "${BLUE}  ->${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2;
}

warning() {
	local mesg=$1; shift
	printf "${YELLOW}==> "WARNING:"${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2;
}

error() {
	local mesg=$1; shift
	printf "${RED}==> "ERROR:"${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2;
}

# $1 = Message
# $2 = Subject
# $3 = attachment
send_email() {
    if [[ $3 == "" ]]; then
        echo -e "${1}" | mail -s "${2}" "${EMAIL}" &> /dev/null;
    else
        echo -e "${1}" | uuencode "${3}" "$(basename "${3}")" | mail -s "${2}" "${EMAIL}" &> /dev/null;
    fi
}

# Make sure only root can run this script
if [[ "$(id -u)" != "0" ]]; then
   error "This script must be run as root";
   exit 1;
fi

# Make sure the raid pool is mounted if on lithium
if [[ $HOSTNAME == "lithium" ]]; then
    MOUNT=`mount | grep /mnt/data`;
    if [[ ${MOUNT} == "" ]]; then
        error "bigdata zpool is not mounted!";
        msg2 "Sending email to \"$EMAIL\"...";
        send_email "backup-tar could not find the bigdata zpool!" \
            "bigdata zpool not mounted on lithium!";
        msg2 "Done";
        exit 1;
    else
        msg "bigdata zpool detected";
    fi
fi

BACKUP_DIR="${BACKUP_DIR%/}/$HOSTNAME";

# Check for backup directory
if [[ ! -e ${BACKUP_DIR} ]]; then
    mkdir -p ${BACKUP_DIR};
    msg "Created "${BACKUP_DIR};
    msg2 "Backing up to: "${BACKUP_DIR};
else
    msg "Backing up to: "${BACKUP_DIR};
fi

# Check for excludes file
EXCLUDES=""
echo $EXCLUDE_FILE_NAME
if [[ ! -f $EXCLUDE_FILE_NAME ]]; then
    msg "Not using excludes file"
else
    msg "Using excludes file: $EXCLUDE_FILE_NAME"
    EXCLUDES="--exclude-from=${EXCLUDE_FILE_NAME}"
fi

FILENAME=$(echo $HOSTNAME)_backup_`uname -r`_$(date +%m%d%Y).tar.xz;

# Remove the last backup if the backups number $REFRESH
cd "${BACKUP_DIR}";
count=`\ls -tr | wc -l`;
if [[ $count -gt $REFRESH ]]; then
    for ((a=1; a <= $count-$REFRESH; a++)); do
        FILE=`\ls -tr | head -n 1`;
        rm ${FILE} 2>&1;
        msg "Deleted "${FILE};
    done
fi

cat /dev/null > /root/backuplog.txt;
cat /dev/null > /root/backuplog-error.txt;

CALC="Calculating backup file list size... ";
msgr "${CALC}";
(tar "${EXCLUDES}" -cvpPf /dev/null / > /tmp/logsize) &
PID1=$!

while [[ `ps -p $PID1 -o pid=` ]]; do
    sleep 0.25;
    SIZE=`du /tmp/logsize | cut -f 1`;
    FSIZE=`printf "%'d" "${SIZE}"`;
    msgr "${CALC}${FSIZE}K";
done
echo;

FIN_SIZE=`du /tmp/logsize | cut -f 1`;

BACKM="Performing backup... ";
msgr "${BACKM}";
(tar --xz ${EXCLUDES} -cvpPf ${BACKUP_DIR}/${FILENAME} / \
    2> /root/backuplog-error.txt > /root/backuplog.txt;) &
PID2=$!

while [[ `ps -p $PID2 -o pid=` ]]; do
    sleep 0.25;
    SIZE=`du /root/backuplog.txt | cut -f 1`;
    PERC=$(( ${SIZE} * 100 / ${FIN_SIZE} ));
    FPERC=`printf "%2d" ${PERC}`;
    msgr "${BACKM}${FPERC}%%";
done
echo;

wait $PID2
TAR_EXIT_CODE=$?
TAR_FILE_SIZE=`du -h "${BACKUP_DIR}/${FILENAME}" | cut -f 1`

cd /root;

msg2 "Compressing backuplog.txt...";
if [[ -f backuplog.zip ]]; then
    rm -f backuplog.zip;
fi;
zip backuplog.zip backuplog.txt backuplog-error.txt &> /dev/null;

if [[ $TAR_EXIT_CODE > 1 ]]; then
    error "The backup was not successful!";
    msg2 "Sending log to ${EMAIL}...";
    send_email "A problem occurred during backup.\n\nExit code: \
${TAR_EXIT_CODE}\nBackup file size: ${TAR_FILE_SIZE}" \
    "$HOSTNAME Backup FAILED" backuplog.zip;
    msg2 "Done";
else
    msg2 "Backup completed successfully.";
    msg2 "Sending log to ${EMAIL}...";
    send_email "Backup completed successfully.\n\nExit code: \
${TAR_EXIT_CODE}\nBackup file size: ${TAR_FILE_SIZE}" \
    "$HOSTNAME Backup SUCCESSFUL" backuplog.zip;
    msg2 "Done";
fi
