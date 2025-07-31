#!/usr/bin/env python3
"""
SD Card Flashing and Filesystem Repair Script (Python version)
Safely flashes an image to SD card and fixes common filesystem issues
"""

import os
import sys
import time
import shutil
import subprocess
import argparse
import signal
from pathlib import Path

class Colors:
    """Terminal color codes"""
    def __init__(self):
        if self._supports_color():
            self.ALL_OFF = '\033[0m'
            self.BOLD = '\033[1m'
            self.BLUE = '\033[1;34m'
            self.GREEN = '\033[1;32m'
            self.RED = '\033[1;31m'
            self.YELLOW = '\033[1;33m'
            self.CYAN = '\033[1;36m'
        else:
            self.ALL_OFF = ''
            self.BOLD = ''
            self.BLUE = ''
            self.GREEN = ''
            self.RED = ''
            self.YELLOW = ''
            self.CYAN = ''

    def _supports_color(self):
        """Check if terminal supports color"""
        return hasattr(sys.stderr, 'isatty') and sys.stderr.isatty()

colors = Colors()

def msg(text, *args):
    """Print main message"""
    print(f"{colors.GREEN}==>{colors.ALL_OFF}{colors.BOLD} {text % args}{colors.ALL_OFF}", file=sys.stderr)

def msg2(text, *args):
    """Print sub-message"""
    print(f"{colors.BLUE}  ->{colors.ALL_OFF}{colors.BOLD} {text % args}{colors.ALL_OFF}", file=sys.stderr)

def warning(text, *args):
    """Print warning message"""
    print(f"{colors.YELLOW}==> WARNING:{colors.ALL_OFF}{colors.BOLD} {text % args}{colors.ALL_OFF}", file=sys.stderr)

def error(text, *args):
    """Print error message"""
    print(f"{colors.RED}==> ERROR:{colors.ALL_OFF}{colors.BOLD} {text % args}{colors.ALL_OFF}", file=sys.stderr)

def get_terminal_width():
    """Get terminal width"""
    try:
        return shutil.get_terminal_size().columns
    except:
        return 120

def format_size(bytes_val):
    """Format bytes as human readable"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if bytes_val < 1024:
            return f"{bytes_val:.1f}{unit}"
        bytes_val /= 1024
    return f"{bytes_val:.1f}TB"

def flash_image_with_progress(image_path, device_path, verify=False):
    """Flash image to device with real-time progress bar"""
    msg("Flashing %s to %s", image_path, device_path)

    # Get image size
    image_size = os.path.getsize(image_path)
    image_size_mb = image_size // (1024 * 1024)

    # Unmount any mounted partitions
    msg2("Unmounting any mounted partitions...")
    if 'mmcblk' in device_path or 'nvme' in device_path:
        subprocess.run(['umount', f"{device_path}p*"],
                      stderr=subprocess.DEVNULL, check=False)
    else:
        subprocess.run(['umount', f"{device_path}*"],
                      stderr=subprocess.DEVNULL, check=False)

    msg2("Flashing image with progress...")

    # Progress tracking variables
    spinner_chars = '/-\\|'
    spinner_index = 0
    start_time = time.time()
    bytes_written = 0
    last_update = start_time
    last_bytes = 0

    # Set up signal handler for immediate Ctrl+C
    def signal_handler(signum, frame):
        print(f"\n{colors.YELLOW}==> Operation cancelled by user{colors.ALL_OFF}", file=sys.stderr)
        sys.exit(1)

    signal.signal(signal.SIGINT, signal_handler)

    try:
        with open(image_path, 'rb') as src, open(device_path, 'wb', buffering=0) as dst:
            block_size = 8 * 1024  # 8KB blocks for very responsive Ctrl+C
            blocks_processed = 0

            while bytes_written < image_size:
                # Read block
                remaining = image_size - bytes_written
                read_size = min(block_size, remaining)
                block = src.read(read_size)
                if not block:
                    break

                # Write block
                dst.write(block)
                bytes_written += len(block)
                blocks_processed += 1

                # Only sync every 1MB (128 blocks) for better performance
                if blocks_processed % 128 == 0:
                    dst.flush()  # Force kernel buffers to flush
                    os.fsync(dst.fileno())  # Force data to physical device

                # Update progress every few blocks or when significant progress made
                current_time = time.time()
                if current_time - last_update >= 0.2:  # Every 0.5 seconds
                    # Calculate progress
                    current_mb = bytes_written // (1024 * 1024)
                    percent = (bytes_written * 100) // image_size
                    if percent > 100:
                        percent = 100

                    # Calculate speed
                    time_diff = current_time - last_update
                    if time_diff > 0 and last_bytes > 0:
                        bytes_diff = bytes_written - last_bytes
                        speed_mbs = int((bytes_diff / time_diff) / (1024 * 1024))
                    else:
                        speed_mbs = 0

                    # Get spinner character
                    spinner_char = spinner_chars[spinner_index]
                    spinner_index = (spinner_index + 1) % 4

                    # Create progress bar (1/3 of terminal width)
                    terminal_width = get_terminal_width()
                    progress_width = terminal_width // 3
                    if progress_width < 30:
                        progress_width = 30

                    filled_width = (percent * progress_width) // 100
                    progress_bar = '=' * filled_width

                    # Add spinner at progress position if not complete
                    if filled_width < progress_width and percent < 100:
                        progress_bar += spinner_char
                        filled_width += 1

                    progress_bar += ' ' * (progress_width - filled_width)

                    # Clear line and print progress with \r
                    sys.stderr.write(f"\r\033[K{colors.GREEN}==>{colors.ALL_OFF}{colors.BOLD} [{progress_bar}] {percent:3d}% ({current_mb}MB/{image_size_mb}MB) @ {speed_mbs}MB/s{colors.ALL_OFF}")
                    sys.stderr.flush()

                    last_update = current_time
                    last_bytes = bytes_written

            # Sync data to disk
            dst.flush()
            os.fsync(dst.fileno())

    except Exception as e:
        error("Failed to flash image: %s", str(e))
        return False

    # Final progress update
    progress_bar_full = '=' * progress_width
    sys.stderr.write(f"\r{colors.GREEN}==>{colors.ALL_OFF}{colors.BOLD} [{progress_bar_full}] 100% ({image_size_mb}MB/{image_size_mb}MB) @ {speed_mbs}MB/s{colors.ALL_OFF}\n")
    sys.stderr.flush()

    msg("Image flashed successfully")
    msg2("Syncing filesystem...")
    subprocess.run(['sync'], check=False)

    # Verify if requested
    if verify:
        msg2("Verifying write...")
        try:
            with open(image_path, 'rb') as src, open(device_path, 'rb') as dst:
                chunk_size = 1024 * 1024
                bytes_compared = 0
                while bytes_compared < image_size:
                    src_chunk = src.read(chunk_size)
                    dst_chunk = dst.read(len(src_chunk))
                    if src_chunk != dst_chunk:
                        warning("Verification failed - data may be corrupted")
                        return False
                    bytes_compared += len(src_chunk)
            msg2("Verification successful")
        except Exception as e:
            warning("Verification failed: %s", str(e))
            return False

    return True

def repair_filesystem(device_path, force=False):
    """Repair filesystem on device"""
    msg("Repairing filesystem on %s", device_path)

    # Check required tools
    required_tools = ['parted', 'fsck', 'e2fsck', 'dosfsck', 'partprobe']
    for tool in required_tools:
        if not shutil.which(tool):
            error("Required tool not found: %s", tool)
            error("Install with: pacman -S parted e2fsprogs dosfstools")
            return False

    # Force kernel to re-read partition table
    msg2("Refreshing partition table...")
    subprocess.run(['partprobe', device_path],
                  stderr=subprocess.DEVNULL, check=False)
    time.sleep(2)

    # Extract base device if partition number is included
    base_device = device_path
    if device_path[-1].isdigit():
        base_device = device_path.rstrip('0123456789')

    # Check partition table
    msg2("Checking partition table...")
    try:
        subprocess.run(['parted', '-s', base_device, 'print'],
                      check=True, capture_output=True)
    except subprocess.CalledProcessError:
        warning("Partition table appears corrupted")
        if force:
            msg2("Creating new GPT partition table...")
            try:
                subprocess.run(['parted', '-s', base_device, 'mklabel', 'gpt'],
                              check=True, stderr=subprocess.DEVNULL)
            except subprocess.CalledProcessError:
                msg2("GPT failed, trying MBR...")
                try:
                    subprocess.run(['parted', '-s', base_device, 'mklabel', 'msdos'],
                                  check=True, stderr=subprocess.DEVNULL)
                except subprocess.CalledProcessError:
                    error("Failed to create partition table")
                    return False
        else:
            warning("Partition table is corrupted. Use --force to recreate it.")
            return False

    # Scan for partitions
    msg2("Scanning for partitions...")
    subprocess.run(['partprobe', base_device],
                  stderr=subprocess.DEVNULL, check=False)
    time.sleep(1)

    # Find partitions
    partitions = []
    if 'mmcblk' in base_device or 'nvme' in base_device:
        # For devices like /dev/mmcblk0, partitions are /dev/mmcblk0p1, etc.
        base_name = Path(base_device).name
        for dev in Path('/dev').glob(f"{base_name}p[0-9]*"):
            if dev.is_block_device():
                partitions.append(str(dev))
    else:
        # For devices like /dev/sdb, partitions are /dev/sdb1, etc.
        base_name = Path(base_device).name
        for dev in Path('/dev').glob(f"{base_name}[0-9]*"):
            if dev.is_block_device():
                partitions.append(str(dev))

    partitions.sort()

    if not partitions:
        warning("No partitions found on %s", base_device)
        return True

    msg2("Found %d partition(s): %s", len(partitions), ' '.join(partitions))

    # Check and repair each partition
    for partition in partitions:
        msg2("Checking partition: %s", partition)

        # Detect filesystem type
        try:
            result = subprocess.run(['blkid', '-o', 'value', '-s', 'TYPE', partition],
                                  capture_output=True, text=True, check=True)
            fstype = result.stdout.strip()
        except subprocess.CalledProcessError:
            fstype = 'unknown'

        if fstype in ['ext2', 'ext3', 'ext4']:
            msg2("  Filesystem: %s - running e2fsck", fstype)
            subprocess.run(['e2fsck', '-f', '-y', partition],
                          stderr=subprocess.DEVNULL, check=False)
        elif fstype in ['vfat', 'fat32', 'fat16']:
            msg2("  Filesystem: %s - running dosfsck", fstype)
            subprocess.run(['dosfsck', '-a', '-v', partition],
                          stderr=subprocess.DEVNULL, check=False)
        elif fstype == 'ntfs':
            if shutil.which('ntfsfix'):
                msg2("  Filesystem: %s - running ntfsfix", fstype)
                subprocess.run(['ntfsfix', partition],
                              stderr=subprocess.DEVNULL, check=False)
            else:
                warning("  Filesystem: %s - ntfsfix not available", fstype)
        else:
            msg2("  Filesystem: %s - no specific repair tool", fstype)

    # Final partition table refresh
    subprocess.run(['partprobe', base_device],
                  stderr=subprocess.DEVNULL, check=False)
    msg("Filesystem repair completed for %s", base_device)
    return True

def main():
    parser = argparse.ArgumentParser(
        description='Flash an image file to SD card and repair filesystem issues',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  %(prog)s archlinux.img /dev/sdb
  %(prog)s --force --verify raspios.img /dev/mmcblk0
  %(prog)s --fix-only /dev/sdb1
        '''
    )

    parser.add_argument('image_file', nargs='?', help='Path to the image file to flash')
    parser.add_argument('device', nargs='?', help='Target device (e.g., /dev/sdb, /dev/mmcblk0)')
    parser.add_argument('-f', '--force', action='store_true',
                       help='Skip confirmation prompts')
    parser.add_argument('-n', '--no-repair', action='store_true',
                       help='Skip filesystem repair after flashing')
    parser.add_argument('-v', '--verify', action='store_true',
                       help='Verify write after flashing')
    parser.add_argument('--fix-only', action='store_true',
                       help='Only repair filesystem, don\'t flash')

    args = parser.parse_args()

    # Check if running as root
    if os.geteuid() != 0:
        error("This script must be run as root")
        sys.exit(1)

    if args.fix_only:
        # Fix only mode
        device = args.device or args.image_file
        if not device:
            error("Device not specified for --fix-only mode")
            parser.print_help()
            sys.exit(1)

        if not os.path.exists(device) or not os.stat(device).st_mode & 0o060000:
            error("Device not found: %s", device)
            sys.exit(1)

        if not repair_filesystem(device, args.force):
            sys.exit(1)
    else:
        # Normal flash mode
        if not args.image_file or not args.device:
            error("Both image file and device must be specified")
            parser.print_help()
            sys.exit(1)

        if not os.path.isfile(args.image_file):
            error("Image file not found: %s", args.image_file)
            sys.exit(1)

        if not os.path.exists(args.device) or not os.stat(args.device).st_mode & 0o060000:
            error("Device not found: %s", args.device)
            sys.exit(1)

        # Show device info before confirmation
        image_size = os.path.getsize(args.image_file)
        image_size_mb = image_size // (1024 * 1024)
        msg2("Image size: %dMB (%s)", image_size_mb, format_size(image_size))

        msg2("Target device info:")
        try:
            result = subprocess.run(['lsblk', args.device],
                                  capture_output=True, text=True, check=True)
            for line in result.stdout.strip().split('\n'):
                print(f"    {line}", file=sys.stderr)
        except:
            pass

        msg2("Current partition table:")
        try:
            result = subprocess.run(['parted', '-s', args.device, 'print'],
                                  capture_output=True, text=True, check=False)
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n'):
                    print(f"    {line}", file=sys.stderr)
            else:
                print("    No valid partition table found", file=sys.stderr)
        except:
            print("    Unable to read partition table", file=sys.stderr)

        # Confirmation
        if not args.force:
            warning("This will completely overwrite %s!", args.device)
            response = input("Are you sure you want to continue? (y/N): ")
            if response.lower() not in ('y', 'yes'):
                msg2("Operation cancelled")
                sys.exit(0)

        # Flash the image
        if not flash_image_with_progress(args.image_file, args.device, args.verify):
            sys.exit(1)

        # Repair filesystem unless disabled
        if not args.no_repair:
            time.sleep(2)  # Give system time to recognize new partitions
            if not repair_filesystem(args.device, args.force):
                sys.exit(1)

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{colors.YELLOW}==> Operation cancelled by user{colors.ALL_OFF}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        error("Unexpected error: %s", str(e))
        sys.exit(1)
