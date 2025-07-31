#!/bin/bash

set -o errexit
set -o pipefail

excludes=(
    "/proc/*"
    "/sys/*"
    "/mnt/*"
    "/media/*"
    "/dev/*"
    "/tmp/*"
    "/data/*"
    "/var/tmp/*"
    "/var/abs/*"
    "/var/spool/*"
    "/run/*"
    "*/lost+found"
    # "/home"
    "/home/*/.thumbnails"
    "/home/*/.gvfs"
    "/home/*/**/Trash/*"
    "/home/*/.npm"
    "/home/*/.[cC]*ache"
    "/home/*/**/*Cache*"
    "/home/*/.netflix*"
    "/home/*/.dbus"
    "/home/*/.cargo"
    # "/home/*/.steam"
    # "/home/*/.local/share/Steam"
)

args=(
    "--verbose"
    "--archive" # Archive. equiv to -rlptgoD
    "--acls" # Preserve acls. implies --perms
    "--xattrs" # Preserve extended attributes
    "--partial" # keep partially transfered files
    "--progress" # show progress
    "--hard-links" # preserve hard links
    "--human-readable" # Output numbers in human readable format
    "--delete-after"
)

flagged_excludes=()
for arg in "${excludes[@]}"; do
    flagged_excludes+=("--exclude=$arg")
done

if [[ "$#" -lt 2 ]]; then
    echo "Error: This script requires atleast 2 arguments."
    echo "Usage: $0 source-path dest-path <additional-rsync-options>"
    exit 1
fi

source_path=$1
dest_path=$2
shift 2
passed_args=${@}

echo
echo "COMMAND: rsync ${args[@]} ${flagged_excludes[@]} ${source_path} ${dest_path} ${passed_args[@]}"
echo
rsync ${args[@]} ${flagged_excludes[@]} ${source_path} ${dest_path} ${passed_args[@]}
