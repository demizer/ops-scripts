#!/bin/bash

# Sanity check script for motorhead
# Verifies the system is ready to boot into GDM

# Load common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib.sh"

# Pre-populated configuration
MOUNT_ROOT="${1:-/mnt/root}"
DEVICE_ROOT="/dev/disk/by-id/nvme-KINGSTON_OM3PGP4128P-AH_0026B7382A48ED90"

show_help() {
    cat << EOF
Usage: $0 [CHROOT_PATH] [OPTIONS]

Perform sanity checks to verify the system is ready to boot

ARGUMENTS:
    CHROOT_PATH             Path to the chroot directory (default: /mnt/root)

OPTIONS:
    -h, --help              Show this help message

CHECKS PERFORMED:
    - EFI boot manager has GRUB entry
    - GDM service is enabled
    - GRUB configuration is generated and contains linux-zen kernel
    - /etc/fstab is correct with EFI partition
    - EFI partition contains initramfs files
    - Root filesystem structure is complete
    - Hostname configuration (FQDN, /etc/hostname, /etc/hosts)

EXAMPLES:
    $0
    $0 /mnt/root
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
        *)
            # First non-option argument is the chroot path
            if [[ -z "${CHROOT_PATH_SET:-}" ]]; then
                MOUNT_ROOT="$1"
                CHROOT_PATH_SET=1
            else
                err "Unknown option: $1"
            fi
            shift
            ;;
    esac
done

# Check if running as root
if [[ "$(id -u)" != "0" ]]; then
    err "This script must be run as root"
fi

# Check if mount root exists and is mounted
if [[ ! -d "$MOUNT_ROOT" ]]; then
    err "Mount root directory $MOUNT_ROOT does not exist"
fi

if ! mountpoint -q "$MOUNT_ROOT"; then
    err "$MOUNT_ROOT is not mounted"
fi

msg "Performing sanity checks for boot readiness..."

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

# Check 1: EFI boot manager has GRUB entry
msg "Checking EFI boot manager..."
if arch-chroot "$MOUNT_ROOT" efibootmgr | grep -q "GRUB"; then
    grub_entry=$(arch-chroot "$MOUNT_ROOT" efibootmgr | grep "GRUB" | head -1)
    check_result "EFI boot manager has GRUB entry" "true" "$grub_entry"
else
    check_result "EFI boot manager has GRUB entry" "false" "No GRUB entry found in efibootmgr"
fi

# Check 2: GDM service is enabled
msg "Checking GDM service status..."
if arch-chroot "$MOUNT_ROOT" systemctl is-enabled gdm > /dev/null 2>&1; then
    check_result "GDM service is enabled" "true" "systemctl is-enabled gdm: enabled"
else
    check_result "GDM service is enabled" "false" "GDM service is not enabled"
fi

# Check 3: GRUB configuration exists and contains linux-zen
msg "Checking GRUB configuration..."
grub_cfg="$MOUNT_ROOT/boot/grub/grub.cfg"
if [[ -f "$grub_cfg" ]]; then
    if grep -q "linux-zen" "$grub_cfg"; then
        # Check if linux-zen is the first (default) entry
        first_kernel=$(grep "^[[:space:]]*linux" "$grub_cfg" | head -1)
        if echo "$first_kernel" | grep -q "linux-zen"; then
            kernel_version=$(echo "$first_kernel" | grep -o "linux-zen[^ ]*" | head -1)
            check_result "GRUB config contains linux-zen as first entry" "true" "Default kernel: $kernel_version"
        else
            check_result "GRUB config contains linux-zen as first entry" "false" "linux-zen found but not as first entry"
        fi
    else
        check_result "GRUB config contains linux-zen kernel" "false" "No linux-zen kernel found in GRUB config"
    fi
else
    check_result "GRUB configuration file exists" "false" "$grub_cfg not found"
fi

# Check 4: /etc/fstab is correct
msg "Checking /etc/fstab..."
fstab_file="$MOUNT_ROOT/etc/fstab"
if [[ -f "$fstab_file" ]]; then
    # Check for EFI partition
    if grep -q "/boot.*vfat" "$fstab_file" || grep -q "/boot.*fat32" "$fstab_file"; then
        efi_entry=$(grep "/boot" "$fstab_file" | head -1)
        check_result "/etc/fstab has EFI partition entry" "true" "$efi_entry"
    else
        check_result "/etc/fstab has EFI partition entry" "false" "No EFI partition (/boot) found in fstab"
    fi

    # Check for root partition
    if grep -q "/ " "$fstab_file"; then
        root_entry=$(grep "/ " "$fstab_file" | head -1)
        check_result "/etc/fstab has root partition entry" "true" "$root_entry"
    else
        check_result "/etc/fstab has root partition entry" "false" "No root partition (/) found in fstab"
    fi

    # Check for NFS mounts
    if grep -q "arch_repo" "$fstab_file" && grep -q "arch_pkg_cache" "$fstab_file"; then
        check_result "/etc/fstab has NFS repository mounts" "true" "arch_repo and arch_pkg_cache configured"
    else
        check_result "/etc/fstab has NFS repository mounts" "false" "NFS repository mounts not found"
    fi
else
    check_result "/etc/fstab exists" "false" "fstab file not found"
fi

# Check 5: EFI partition is mounted and contains initramfs
msg "Checking EFI partition contents..."
boot_dir="$MOUNT_ROOT/boot"
if [[ -d "$boot_dir" ]]; then
    # Check for EFI directory structure
    if [[ -d "$boot_dir/EFI/GRUB" ]]; then
        check_result "EFI partition has GRUB directory" "true" "/boot/EFI/GRUB exists"
    else
        check_result "EFI partition has GRUB directory" "false" "/boot/EFI/GRUB not found"
    fi

    # Check for initramfs files
    if ls "$boot_dir"/initramfs-linux-zen*.img > /dev/null 2>&1; then
        initramfs_files=$(ls "$boot_dir"/initramfs-linux-zen*.img | wc -l)
        check_result "EFI partition contains initramfs files" "true" "$initramfs_files initramfs files found"
    else
        check_result "EFI partition contains initramfs files" "false" "No initramfs-linux-zen*.img files found"
    fi

    # Check for kernel files
    if ls "$boot_dir"/vmlinuz-linux-zen > /dev/null 2>&1; then
        kernel_file=$(ls -la "$boot_dir"/vmlinuz-linux-zen | awk '{print $5 " bytes"}')
        check_result "EFI partition contains kernel file" "true" "vmlinuz-linux-zen ($kernel_file)"
    else
        check_result "EFI partition contains kernel file" "false" "vmlinuz-linux-zen not found"
    fi
else
    check_result "EFI partition is mounted at /boot" "false" "$boot_dir directory not found"
fi

# Check 6: Essential services are enabled
msg "Checking essential services..."
services=("NetworkManager" "sshd")
for service in "${services[@]}"; do
    if arch-chroot "$MOUNT_ROOT" systemctl is-enabled "$service" > /dev/null 2>&1; then
        check_result "$service service is enabled" "true"
    else
        check_result "$service service is enabled" "false" "$service is not enabled"
    fi
done

# Check 7: Root filesystem structure
msg "Checking root filesystem structure..."
essential_dirs=("etc" "usr" "bin" "lib" "var" "home" "root")
missing_dirs=()
for dir in "${essential_dirs[@]}"; do
    if [[ ! -d "$MOUNT_ROOT/$dir" ]]; then
        missing_dirs+=("$dir")
    fi
done

if [[ ${#missing_dirs[@]} -eq 0 ]]; then
    check_result "Essential directories present" "true" "All essential directories found"
else
    check_result "Essential directories present" "false" "Missing directories: ${missing_dirs[*]}"
fi

# Check 8: User configuration
msg "Checking user configuration..."
if arch-chroot "$MOUNT_ROOT" id jesusa > /dev/null 2>&1; then
    user_info=$(arch-chroot "$MOUNT_ROOT" id jesusa)
    check_result "User 'jesusa' exists" "true" "$user_info"

    # Check if jesusa is in wheel group
    if arch-chroot "$MOUNT_ROOT" groups jesusa | grep -q wheel; then
        check_result "User 'jesusa' is in wheel group" "true" "Has sudo access"
    else
        check_result "User 'jesusa' is in wheel group" "false" "No sudo access"
    fi
else
    check_result "User 'jesusa' exists" "false" "User not found"
fi

# Check 9: Hostname configuration
msg "Checking hostname configuration..."
expected_fqdn="motorhead.alvaone.net"
if arch-chroot "$MOUNT_ROOT" hostname | grep -q "^$expected_fqdn$"; then
    check_result "Hostname FQDN is set correctly" "true" "$(arch-chroot "$MOUNT_ROOT" hostname)"
else
    actual_hostname=$(arch-chroot "$MOUNT_ROOT" hostname 2> /dev/null || echo "unknown")
    check_result "Hostname FQDN is set correctly" "false" "Expected: $expected_fqdn, Actual: $actual_hostname"
fi

# Check hostname file
if [[ -f "$MOUNT_ROOT/etc/hostname" ]]; then
    hostname_file_content=$(cat "$MOUNT_ROOT/etc/hostname" | tr -d '\n')
    if [[ "$hostname_file_content" == "motorhead" ]]; then
        check_result "/etc/hostname contains correct short hostname" "true" "$hostname_file_content"
    else
        check_result "/etc/hostname contains correct short hostname" "false" "Expected: motorhead, Actual: $hostname_file_content"
    fi
else
    check_result "/etc/hostname file exists" "false" "File not found"
fi

# Check /etc/hosts configuration
if [[ -f "$MOUNT_ROOT/etc/hosts" ]]; then
    if grep -q "127.0.1.1.*motorhead.alvaone.net.*motorhead" "$MOUNT_ROOT/etc/hosts"; then
        hosts_entry=$(grep "127.0.1.1" "$MOUNT_ROOT/etc/hosts")
        check_result "/etc/hosts has correct FQDN entry" "true" "$hosts_entry"
    else
        check_result "/etc/hosts has correct FQDN entry" "false" "FQDN entry not found or incorrect"
    fi
else
    check_result "/etc/hosts file exists" "false" "File not found"
fi

# Check 10: Validate fstab contains only expected target devices
msg "Checking fstab contains only expected target devices..."
if [[ -f "$fstab_file" ]]; then
    # Get target device name (e.g., nvme0n1 from /dev/disk/by-id/nvme-...)
    target_device_path=$(readlink -f "$DEVICE_ROOT" 2> /dev/null || echo "$DEVICE_ROOT")
    target_device_name=$(basename "$target_device_path")
    invalid_devices=()
    found_partitions=()

    # Parse fstab and validate each device
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Parse fstab entry
        device=$(echo "$line" | awk '{print $1}')
        mountpoint=$(echo "$line" | awk '{print $2}')
        fstype=$(echo "$line" | awk '{print $3}')

        # Skip special filesystems that don't need device validation
        case "$fstype" in
            proc | sysfs | devpts | tmpfs | devtmpfs) continue ;;
        esac

        # Check if this is an expected device
        device_valid=false
        target_partition=""

        if [[ "$device" =~ ^UUID= ]]; then
            uuid=${device#UUID=}
            # Check if this UUID belongs to our target device by looking up the device name
            uuid_device=$(readlink -f "/dev/disk/by-uuid/$uuid" 2> /dev/null)
            if [[ -n "$uuid_device" ]]; then
                uuid_device_name=$(basename "$uuid_device")
                # Check if it's one of our target device partitions (e.g., nvme0n1p1-5)
                if [[ "$uuid_device_name" =~ ^${target_device_name}p[1-5]$ ]]; then
                    device_valid=true
                    target_partition="$uuid_device_name"
                    found_partitions+=("$target_partition")
                    msg "✅ Validated target partition $target_partition ($device -> $mountpoint, $fstype)"
                fi
            fi
        elif [[ "$device" =~ : ]]; then
            # NFS mount - these are allowed
            device_valid=true
            msg "✅ Validated NFS mount ($device -> $mountpoint, $fstype)"
        elif [[ "$device" =~ ^/dev/ ]]; then
            # Check if this is one of our target device partitions
            device_name=$(basename "$device")
            if [[ "$device_name" =~ ^${target_device_name}p[1-5]$ ]]; then
                device_valid=true
                target_partition="$device_name"
                found_partitions+=("$target_partition")
                msg "✅ Validated target partition $target_partition ($device -> $mountpoint, $fstype)"
            fi
        fi

        # If device is not valid, it's likely an archiso or other external device
        if [[ "$device_valid" == "false" ]]; then
            invalid_devices+=("$device ($mountpoint, $fstype)")
            if [[ "$fstype" == "swap" ]] || [[ "$mountpoint" == "/swapfile" ]]; then
                warn "⚠️  CRITICAL: Invalid swap device $device - this is likely archiso swap that WILL cause boot failure!"
            else
                warn "⚠️  WARNING: Invalid device $device - not from target system partitions"
            fi
        fi
    done < "$fstab_file"

    # Check if all expected partitions are present in fstab
    expected_partitions=("${target_device_name}p1" "${target_device_name}p2" "${target_device_name}p3" "${target_device_name}p4" "${target_device_name}p5")
    missing_partitions=()
    for expected in "${expected_partitions[@]}"; do
        partition_found=false
        for found in "${found_partitions[@]}"; do
            if [[ "$found" == "$expected" ]]; then
                partition_found=true
                break
            fi
        done
        if [[ "$partition_found" == "false" ]]; then
            missing_partitions+=("$expected")
        fi
    done

    # Report results
    if [[ ${#invalid_devices[@]} -eq 0 ]] && [[ ${#missing_partitions[@]} -eq 0 ]]; then
        check_result "fstab contains only target system devices" "true" "All target partitions accounted for and no invalid devices"
    else
        error_details=""
        if [[ ${#invalid_devices[@]} -gt 0 ]]; then
            error_details+="Invalid devices: ${invalid_devices[*]} "
        fi
        if [[ ${#missing_partitions[@]} -gt 0 ]]; then
            error_details+="Missing partitions: ${missing_partitions[*]}"
        fi
        check_result "fstab contains only target system devices" "false" "$error_details"
    fi
else
    check_result "fstab file exists" "false" "No fstab file found"
fi

# Summary
echo
if [[ $FAILED_CHECKS -eq 0 ]]; then
    msg "🎉 All sanity checks passed! System is ready to boot."
    msg "You can safely:"
    msg "  1. Unmount the filesystem"
    msg "  2. Remove installation media"
    msg "  3. Reboot into the new system"
    msg "  4. Login as 'jesusa' with your configured password"
    msg "  5. The system should boot into GDM automatically"
    exit 0
else
    warn "❌ $FAILED_CHECKS sanity check(s) failed!"
    warn "The system may not boot properly."
    warn "Review the failed checks above and fix the issues before rebooting."
    exit 1
fi
