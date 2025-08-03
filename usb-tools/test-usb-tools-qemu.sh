#!/bin/bash

# QEMU Test Script for Custom Arch ISO
# Tests the USB tools system using QEMU virtual machine
# Automatically detects the most recent ISO in the output directory

# Color output functions (matching other scripts)
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

debug() {
    if [[ "$DEBUG_MODE" == true ]]; then
        local mesg=$1; shift
        printf "${YELLOW}==> DEBUG:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2;
    fi
}

# Configuration
OUTPUT_DIR="/tmp/usb-tools-output"
QEMU_MEMORY="4G"
QEMU_CPUS="2"
OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"

# Parse command line arguments
HEADLESS=false
UEFI_MODE=true
MEMORY="$QEMU_MEMORY"
CPUS="$QEMU_CPUS"
HOST_NETWORKING=true
CREATE_BRIDGE=false
REMOVE_BRIDGE=false
DEBUG_MODE=false
BOOT_DEVICE=""
CREATE_ISO_FROM_DEVICE=false
AUTO_YES=false

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Test custom Arch ISO using QEMU

OPTIONS:
    -h, --help          Show this help message
    -m, --memory SIZE   Set memory size (default: 4G)
    -c, --cpus NUM      Set number of CPUs (default: 2)
    -b, --bios          Boot in legacy BIOS mode (default is UEFI)
    --headless          Run without graphics (VNC on :1)
    --no-host-networking Disable host networking (use NAT instead)
    --create-bridge     Create QEMU network bridge with NetworkManager
    --remove-bridge     Remove QEMU network bridge configuration
    --debug             Enable debug output for bridge creation
    --iso PATH          Use specific ISO file instead of auto-detection
    --device PATH       Boot from device with PCIe passthrough (requires IOMMU)
    --create-iso        Create ISO from --device and boot from that (faster than USB passthrough)
    -y, --yes           Answer yes to all prompts

EXAMPLES:
    $0                          # Test with default settings
    $0 -m 8G -c 4              # Test with 8GB RAM and 4 CPUs
    $0 --bios                  # Test in legacy BIOS mode
    $0 --headless              # Test without graphics
    $0 --iso /path/to/test.iso # Test specific ISO file
    $0 --device /dev/sdb       # Boot from USB/SD card with PCIe passthrough
    $0 --device /dev/sdb --create-iso # Create ISO from device and boot (faster)

EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -m|--memory)
            MEMORY="$2"
            shift 2
            ;;
        -c|--cpus)
            CPUS="$2"
            shift 2
            ;;
        -b|--bios)
            UEFI_MODE=false
            shift
            ;;
        --headless)
            HEADLESS=true
            shift
            ;;
        --no-host-networking)
            HOST_NETWORKING=false
            shift
            ;;
        --create-bridge)
            CREATE_BRIDGE=true
            shift
            ;;
        --remove-bridge)
            REMOVE_BRIDGE=true
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --iso)
            CUSTOM_ISO="$2"
            shift 2
            ;;
        --device)
            BOOT_DEVICE="$2"
            shift 2
            ;;
        --create-iso)
            CREATE_ISO_FROM_DEVICE=true
            shift
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Handle bridge management commands first
if [[ "$CREATE_BRIDGE" == true ]]; then
    msg "Creating QEMU network bridge with NetworkManager";

    # Check if running as root
    if [[ "$(id -u)" != "0" ]]; then
        error "Bridge creation requires root privileges";
        exit 1;
    fi

    # Check if NetworkManager is running
    if ! systemctl is-active --quiet NetworkManager; then
        error "NetworkManager is not running. Start it with: systemctl start NetworkManager";
        exit 1;
    fi

    # Check if nmcli is available
    if ! command -v nmcli &>/dev/null; then
        error "nmcli not found. Install NetworkManager with: pacman -S networkmanager";
        exit 1;
    fi

    # Check if currently using WiFi connection
    ACTIVE_CONNECTION=$(nmcli -t -f NAME,TYPE connection show --active | grep ":wifi$" | cut -d: -f1)
    if [[ -n "$ACTIVE_CONNECTION" ]]; then
        error "Bridge networking requires a wired connection!";
        error "Currently active WiFi connection: $ACTIVE_CONNECTION";
        error "WiFi interfaces cannot be properly bridged.";
        msg2 "Please:";
        msg2 "  1. Connect to a wired network";
        msg2 "  2. Disconnect from WiFi";
        msg2 "  3. Run this command again";
        msg2 "Alternative: Use --no-host-networking for NAT mode";
        exit 1;
    fi

    # Detect the active wired network interface
    msg2 "Detecting active wired network interface...";
    ACTIVE_INTERFACE=$(nmcli -t -f DEVICE,TYPE connection show --active | grep ":ethernet$" | cut -d: -f1 | head -n1)
    if [[ -z "$ACTIVE_INTERFACE" ]]; then
        # Try to find any available ethernet interface
        ACTIVE_INTERFACE=$(ip link show | grep -E "^[0-9]+: (en|eth)" | head -n1 | cut -d: -f2 | tr -d ' ')
        if [[ -z "$ACTIVE_INTERFACE" ]]; then
            error "No wired network interface found";
            error "Please connect a wired network cable and ensure the interface is up";
            exit 1;
        fi
        warning "Found ethernet interface $ACTIVE_INTERFACE but no active connection";
        msg2 "Will attempt to use $ACTIVE_INTERFACE";
    fi

    msg2 "Found wired interface: $ACTIVE_INTERFACE";

    # Get current connection name for the interface
    CURRENT_CONNECTION=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$ACTIVE_INTERFACE$" | cut -d: -f1)
    if [[ -n "$CURRENT_CONNECTION" ]]; then
        msg2 "Current connection: $CURRENT_CONNECTION";
        warning "This will temporarily disconnect your network!";
        
        if [[ "$AUTO_YES" == true ]]; then
            msg2 "Continuing with bridge creation (--yes specified)";
        else
            read -p "Continue? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                msg2 "Bridge creation cancelled";
                exit 0;
            fi
        fi
    fi

    # Create bridge connection
    msg2 "Creating bridge connection br0...";
    nmcli connection add type bridge ifname br0 con-name br0

    # Configure bridge to use DHCP and DNS
    msg2 "Configuring bridge network...";
    nmcli connection modify br0 ipv4.method auto
    nmcli connection modify br0 ipv6.method auto
    nmcli connection modify br0 ipv4.dns "192.168.5.1,1.1.1.1,1.0.0.1"
    nmcli connection modify br0 ipv4.ignore-auto-dns no

    # Create bridge slave for the physical interface
    msg2 "Creating bridge slave for $ACTIVE_INTERFACE...";
    nmcli connection add type bridge-slave ifname "$ACTIVE_INTERFACE" master br0 con-name "br0-slave-$ACTIVE_INTERFACE"

    # Bring down the current connection and bring up the bridge
    msg2 "Switching to bridge networking...";
    if [[ -n "$CURRENT_CONNECTION" ]]; then
        nmcli connection down "$CURRENT_CONNECTION"
    fi
    nmcli connection up br0
    nmcli connection up "br0-slave-$ACTIVE_INTERFACE"

    # Wait for bridge to get IP and verify it's active
    msg2 "Waiting for bridge to become active...";
    BRIDGE_ACTIVE=false
    BRIDGE_TIMEOUT=60
    for i in $(seq 1 $BRIDGE_TIMEOUT); do
        # Check if bridge connection is activated
        BRIDGE_STATE=$(nmcli -t -f GENERAL.STATE connection show br0 2>/dev/null || echo "unknown")
        SLAVE_STATE=$(nmcli -t -f GENERAL.STATE connection show "br0-slave-$ACTIVE_INTERFACE" 2>/dev/null || echo "unknown")

        # Extract just the state value (remove GENERAL.STATE: prefix)
        BRIDGE_STATE_VALUE=$(echo "$BRIDGE_STATE" | cut -d: -f2)
        SLAVE_STATE_VALUE=$(echo "$SLAVE_STATE" | cut -d: -f2)

        # Check if bridge has an IP address
        BRIDGE_IP=$(ip addr show br0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)

        # Debug output every iteration to see what's happening
        if [[ $i -eq 1 ]] || [[ $((i % 5)) -eq 0 ]]; then
            debug "($i/$BRIDGE_TIMEOUT): Raw states: '$BRIDGE_STATE' | '$SLAVE_STATE'";
            debug "($i/$BRIDGE_TIMEOUT): Parsed: Bridge='$BRIDGE_STATE_VALUE' Slave='$SLAVE_STATE_VALUE'";
            debug "($i/$BRIDGE_TIMEOUT): Bridge IP: '$BRIDGE_IP'";
            debug "($i/$BRIDGE_TIMEOUT): IP check result: [[ -n '$BRIDGE_IP' ]] = $([[ -n "$BRIDGE_IP" ]] && echo true || echo false)";
            debug "($i/$BRIDGE_TIMEOUT): Slave check result: [[ '$SLAVE_STATE_VALUE' == 'activated' ]] = $([[ "$SLAVE_STATE_VALUE" == "activated" ]] && echo true || echo false)";
        fi

        if [[ -n "$BRIDGE_IP" ]] && [[ "$SLAVE_STATE_VALUE" == "activated" ]]; then
            # Bridge has IP and slave is ready - that's good enough
            msg "Bridge is ready with IP: $BRIDGE_IP (state: $BRIDGE_STATE_VALUE)";
            BRIDGE_ACTIVE=true
            break;
        elif [[ "$BRIDGE_STATE_VALUE" == "activated" ]] && [[ "$SLAVE_STATE_VALUE" == "activated" ]]; then
            msg2 "Bridge fully activated but waiting for IP... ($i/$BRIDGE_TIMEOUT)";
            # Give it a bit more time for DHCP to complete, check more frequently
            for j in {1..10}; do
                sleep 0.5
                BRIDGE_IP=$(ip addr show br0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
                if [[ -n "$BRIDGE_IP" ]]; then
                    msg "Bridge got IP: $BRIDGE_IP after DHCP completion";
                    BRIDGE_ACTIVE=true
                    break 2;  # Break out of both loops
                fi
            done
        else
            msg2 "Waiting for bridge activation... Bridge: $BRIDGE_STATE_VALUE, Slave: $SLAVE_STATE_VALUE ($i/$BRIDGE_TIMEOUT)";
        fi
        sleep 1
    done

    if [[ "$BRIDGE_ACTIVE" != true ]]; then
        warning "Bridge activation timed out after $BRIDGE_TIMEOUT seconds";
        msg2 "Current status:";
        FINAL_BRIDGE_STATE=$(nmcli -t -f GENERAL.STATE connection show br0 2>/dev/null || echo 'unknown')
        FINAL_SLAVE_STATE=$(nmcli -t -f GENERAL.STATE connection show "br0-slave-$ACTIVE_INTERFACE" 2>/dev/null || echo 'unknown')
        FINAL_BRIDGE_IP=$(ip addr show br0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 || echo 'none')

        # Extract just the state values
        FINAL_BRIDGE_STATE_VALUE=$(echo "$FINAL_BRIDGE_STATE" | cut -d: -f2)
        FINAL_SLAVE_STATE_VALUE=$(echo "$FINAL_SLAVE_STATE" | cut -d: -f2)

        msg2 "  Bridge state: $FINAL_BRIDGE_STATE_VALUE";
        msg2 "  Slave state: $FINAL_SLAVE_STATE_VALUE";
        msg2 "  Bridge IP: $FINAL_BRIDGE_IP";

        # Check if it's actually active now (race condition)
        if [[ "$FINAL_BRIDGE_STATE_VALUE" == "activated" ]] && [[ "$FINAL_SLAVE_STATE_VALUE" == "activated" ]] && [[ -n "$FINAL_BRIDGE_IP" ]]; then
            msg "Bridge is actually active now! (timing issue)";
            BRIDGE_ACTIVE=true
        else
            msg2 "You can check status manually with: nmcli connection show br0";
        fi
    fi

    # Create QEMU bridge configuration
    msg2 "Creating QEMU bridge configuration...";
    mkdir -p /etc/qemu
    echo "allow br0" > /etc/qemu/bridge.conf

    # Set permissions for qemu-bridge-helper
    if [[ -f /usr/lib/qemu/qemu-bridge-helper ]]; then
        chmod u+s /usr/lib/qemu/qemu-bridge-helper
    fi

    msg "Bridge br0 created successfully!";
    msg2 "NetworkManager bridge connection created: br0";
    msg2 "Physical interface enslaved: $ACTIVE_INTERFACE";
    msg2 "QEMU bridge configuration: /etc/qemu/bridge.conf";

    # Show final bridge status
    msg2 "Final bridge status:";
    BRIDGE_STATE=$(nmcli -t -f GENERAL.STATE connection show br0 2>/dev/null || echo "unknown")
    SLAVE_STATE=$(nmcli -t -f GENERAL.STATE connection show "br0-slave-$ACTIVE_INTERFACE" 2>/dev/null || echo "unknown")
    BRIDGE_IP=$(ip addr show br0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)

    # Extract just the state value (remove GENERAL.STATE: prefix)
    BRIDGE_STATE_VALUE=$(echo "$BRIDGE_STATE" | cut -d: -f2)
    SLAVE_STATE_VALUE=$(echo "$SLAVE_STATE" | cut -d: -f2)

    msg2 "  Bridge state: $BRIDGE_STATE_VALUE";
    msg2 "  Slave state: $SLAVE_STATE_VALUE";
    if [[ -n "$BRIDGE_IP" ]]; then
        msg2 "  IP Address: $BRIDGE_IP";
    else
        msg2 "  IP Address: Not assigned";
    fi

    # Show bridge link status
    if command -v bridge &>/dev/null; then
        BRIDGE_LINKS=$(bridge link show | grep "master br0" | wc -l)
        msg2 "  Bridge links: $BRIDGE_LINKS";
    fi

    # Test connectivity
    msg2 "Testing connectivity...";
    if [[ -n "$BRIDGE_IP" ]]; then
        if ping -c1 -W2 192.168.5.1 &>/dev/null; then
            msg2 "  ✓ Gateway reachable";
        else
            warning "  ✗ Gateway not reachable";
        fi

        if ping -c1 -W2 1.1.1.1 &>/dev/null; then
            msg2 "  ✓ Internet reachable";
        else
            warning "  ✗ Internet not reachable";
        fi
    else
        warning "  ✗ No IP address assigned - cannot test connectivity";
    fi

    exit 0;
fi

if [[ "$REMOVE_BRIDGE" == true ]]; then
    msg "Removing QEMU network bridge configuration";

    # Check if running as root
    if [[ "$(id -u)" != "0" ]]; then
        error "Bridge removal requires root privileges";
        exit 1;
    fi

    # Check if nmcli is available
    if command -v nmcli &>/dev/null; then
        # Remove NetworkManager bridge connection if it exists
        if nmcli connection show br0 &>/dev/null; then
            msg2 "Removing NetworkManager bridge connection...";
            nmcli connection delete br0
        else
            msg2 "NetworkManager bridge connection br0 not found";
        fi
        
        # Remove all bridge slave connections (delete by name removes all with same name)
        msg2 "Removing bridge slave connections...";
        SLAVE_NAMES=$(nmcli -t -f NAME connection show | grep "^br0-slave-" | sort -u)
        if [[ -n "$SLAVE_NAMES" ]]; then
            while IFS= read -r slave_name; do
                msg2 "  Removing all connections named: $slave_name";
                nmcli connection delete "$slave_name" 2>/dev/null || true
            done <<< "$SLAVE_NAMES"
        else
            msg2 "No bridge slave connections found";
        fi
        
        # Restore wired connection
        msg2 "Restoring wired network connection...";
        # Find available ethernet interfaces
        ETH_INTERFACE=$(ip link show | grep -E "^[0-9]+: (en|eth)" | head -n1 | cut -d: -f2 | tr -d ' ')
        if [[ -n "$ETH_INTERFACE" ]]; then
            msg2 "  Found ethernet interface: $ETH_INTERFACE";
            
            # First, try to find any active wired connections
            ACTIVE_WIRED=$(nmcli -t -f NAME,TYPE connection show --active | grep ":802-3-ethernet$" | head -n1 | cut -d: -f1)
            if [[ -n "$ACTIVE_WIRED" ]]; then
                msg2 "  Wired connection already active: $ACTIVE_WIRED";
            else
                # Look for any existing wired connections to activate
                EXISTING_WIRED=$(nmcli -t -f NAME,TYPE connection show | grep ":802-3-ethernet$" | head -n1 | cut -d: -f1)
                if [[ -n "$EXISTING_WIRED" ]]; then
                    msg2 "  Activating existing wired connection: $EXISTING_WIRED";
                    nmcli connection up "$EXISTING_WIRED"
                else
                    # Only create if no wired connections exist at all
                    msg2 "  No existing wired connections found, creating new one";
                    nmcli connection add type ethernet ifname "$ETH_INTERFACE" con-name "Wired-$ETH_INTERFACE"
                    nmcli connection up "Wired-$ETH_INTERFACE"
                fi
            fi
        else
            warning "No ethernet interface found to restore connection";
        fi
    fi

    # Remove QEMU bridge configuration
    msg2 "Removing QEMU bridge configuration...";
    rm -f /etc/qemu/bridge.conf

    msg "Bridge configuration removed successfully!";
    exit 0;
fi

msg "Testing Custom Arch ISO with QEMU";

# Check for leftover qemu*.iso files in current directory and prompt for deletion
QEMU_ISO_FILES=(./qemu*.iso)
if [[ -f "${QEMU_ISO_FILES[0]}" ]]; then
    msg2 "Found leftover QEMU ISO files in current directory:";
    for iso_file in "${QEMU_ISO_FILES[@]}"; do
        if [[ -f "$iso_file" ]]; then
            ISO_SIZE=$(du -h "$iso_file" | cut -f1)
            ISO_DATE=$(stat -c '%y' "$iso_file" | cut -d'.' -f1)
            msg2 "  $(basename "$iso_file") - $ISO_SIZE - $ISO_DATE";
        fi
    done
    echo
    
    if [[ "$AUTO_YES" == true ]]; then
        msg2 "Auto-deleting leftover ISO files (--yes specified)";
        DELETE_ISOS=true
    else
        read -p "Delete these leftover ISO files? (y/N): " -n 1 -r
        echo
        DELETE_ISOS=false
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            DELETE_ISOS=true
        fi
    fi
    
    if [[ "$DELETE_ISOS" == true ]]; then
        for iso_file in "${QEMU_ISO_FILES[@]}"; do
            if [[ -f "$iso_file" ]]; then
                rm -f "$iso_file"
                msg2 "Deleted: $(basename "$iso_file")";
            fi
        done
    else
        msg2 "Keeping existing ISO files";
    fi
    echo
fi

# Check if QEMU is installed
if ! command -v qemu-system-x86_64 &>/dev/null; then
    error "QEMU is not installed. Install with: pacman -S qemu-desktop";
    exit 1;
fi

# Determine boot source (device or ISO)
if [[ -n "$BOOT_DEVICE" ]]; then
    # Boot from device
    if [[ ! -b "$BOOT_DEVICE" ]]; then
        error "Boot device not found or not a block device: $BOOT_DEVICE";
        exit 1;
    fi
    
    # Check device info
    DEVICE_SIZE=$(lsblk -b -n -o SIZE "$BOOT_DEVICE" 2>/dev/null | head -1)
    if [[ -n "$DEVICE_SIZE" ]]; then
        DEVICE_SIZE_GB=$((DEVICE_SIZE / 1024 / 1024 / 1024))
        msg2 "Device size: ${DEVICE_SIZE_GB}GB";
    fi
    
    # Show partition info if available
    msg2 "Device partition info:";
    lsblk "$BOOT_DEVICE" 2>/dev/null | while IFS= read -r line; do
        msg2 "  $line";
    done
    
    # Create ISO from device if requested
    if [[ "$CREATE_ISO_FROM_DEVICE" == true ]]; then
        msg2 "Creating ISO from device for faster booting...";
        
        # Check if running as root for device access
        if [[ "$(id -u)" != "0" ]]; then
            error "Creating ISO from device requires root privileges";
            exit 1;
        fi
        
        # Create ISO file in current directory
        TEMP_ISO="./qemu-device-$(basename "$BOOT_DEVICE")-$(date +%Y%m%d-%H%M%S).iso"
        
        msg2 "Creating ISO: $TEMP_ISO";
        msg2 "This may take a few minutes depending on device size...";
        
        # Use dd to create ISO from device with progress
        if command -v pv &>/dev/null; then
            # Use pv for progress if available
            pv "$BOOT_DEVICE" > "$TEMP_ISO"
        else
            # Fallback to dd with periodic status
            dd if="$BOOT_DEVICE" of="$TEMP_ISO" bs=1M status=progress
        fi
        
        if [[ $? -ne 0 ]]; then
            error "Failed to create ISO from device";
            rm -f "$TEMP_ISO"
            exit 1;
        fi
        
        BOOT_SOURCE="$TEMP_ISO"
        msg2 "ISO created successfully: $BOOT_SOURCE";
        
        # Cleanup function for ISO (still in current directory)
        cleanup_temp_iso() {
            if [[ -f "$TEMP_ISO" ]]; then
                msg2 "Cleaning up ISO: $TEMP_ISO";
                rm -f "$TEMP_ISO"
            fi
        }
        trap cleanup_temp_iso EXIT
        
        # Set flag to boot from ISO instead of device
        USE_DEVICE_PASSTHROUGH=false
    else
        BOOT_SOURCE="$BOOT_DEVICE"
        msg2 "Using boot device: $BOOT_SOURCE";
        USE_DEVICE_PASSTHROUGH=true
    fi
    
else
    # Boot from ISO file
    if [[ -n "$CUSTOM_ISO" ]]; then
        if [[ ! -f "$CUSTOM_ISO" ]]; then
            error "Custom ISO file not found: $CUSTOM_ISO";
            exit 1;
        fi
        ISO_FILE="$CUSTOM_ISO"
        msg2 "Using custom ISO: $ISO_FILE";
    else
        # Auto-detect most recent ISO
        if [[ ! -d "$OUTPUT_DIR" ]]; then
            error "Output directory not found: $OUTPUT_DIR";
            error "Run create-usb-tools.sh first to build the USB system";
            exit 1;
        fi

        ISO_FILE=$(find "$OUTPUT_DIR" -name "*.iso" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

        if [[ -z "$ISO_FILE" ]]; then
            error "No ISO file found in $OUTPUT_DIR";
            error "Run create-usb-tools.sh first to build the USB system";
            exit 1;
        fi

        msg2 "Auto-detected ISO: $ISO_FILE";
    fi
    
    BOOT_SOURCE="$ISO_FILE"
    USE_DEVICE_PASSTHROUGH=false
    
    # Check ISO file size and modification time
    ISO_SIZE=$(du -h "$ISO_FILE" | cut -f1)
    ISO_DATE=$(stat -c '%y' "$ISO_FILE" | cut -d'.' -f1)
    msg2 "ISO size: $ISO_SIZE";
    msg2 "ISO created: $ISO_DATE";
fi

# UEFI mode checks
if [[ "$UEFI_MODE" == true ]]; then
    if [[ ! -f "$OVMF_CODE" ]]; then
        msg2 "OVMF firmware not found, installing edk2-ovmf package...";
        if ! sudo pacman -S --noconfirm edk2-ovmf; then
            error "Failed to install edk2-ovmf package";
            exit 1;
        fi

        if [[ ! -f "$OVMF_CODE" ]]; then
            error "OVMF firmware still not found at $OVMF_CODE after installation";
            exit 1;
        fi
    fi
    msg2 "UEFI mode enabled";
fi

# Build QEMU command
QEMU_CMD=(
    "qemu-system-x86_64"
    "-enable-kvm"
    "-m" "$MEMORY"
    "-smp" "$CPUS"
)

# Add boot source using virtio drive
QEMU_CMD+=("-drive" "file=$BOOT_SOURCE,format=raw,if=virtio,media=disk")
QEMU_CMD+=("-boot" "menu=on")

msg2 "Using virtio drive for boot";

# Check for bridge networking requirements
if [[ "$HOST_NETWORKING" == true ]]; then
    # Check if currently using WiFi connection
    ACTIVE_WIFI=$(nmcli -t -f NAME,TYPE connection show --active | grep ":wifi$" | cut -d: -f1)
    if [[ -n "$ACTIVE_WIFI" ]]; then
        error "Bridge networking requires a wired connection!";
        error "Currently active WiFi connection: $ACTIVE_WIFI";
        error "WiFi interfaces cannot be properly bridged.";
        msg2 "Please:";
        msg2 "  1. Connect to a wired network";
        msg2 "  2. Disconnect from WiFi";
        msg2 "  3. Run this command again";
        msg2 "Alternative: Use --no-host-networking for NAT mode";
        exit 1;
    fi

    if [[ ! -f "/etc/qemu/bridge.conf" ]] || ! grep -q "allow br0" /etc/qemu/bridge.conf 2>/dev/null; then
        error "QEMU network bridge not configured!";
        error "A network bridge is required for host networking.";
        msg2 "To create a bridge: sudo $0 --create-bridge";
        msg2 "To remove a bridge: sudo $0 --remove-bridge";
        exit 1;
    fi

    # Check if bridge exists
    if ! ip link show br0 &>/dev/null; then
        error "Bridge br0 does not exist!";
        error "Create the bridge first: sudo $0 --create-bridge";
        exit 1;
    fi

    QEMU_CMD+=("-netdev" "bridge,br=br0,id=net0" "-device" "e1000,netdev=net0")
else
    QEMU_CMD+=("-netdev" "user,id=net0,hostfwd=tcp::2222-:22" "-device" "e1000,netdev=net0")
fi

# Add graphics options
if [[ "$HEADLESS" == true ]]; then
    QEMU_CMD+=("-nographic" "-vnc" ":1")
    msg2 "Running in headless mode (VNC on :1)";
else
    QEMU_CMD+=("-vga" "virtio")
    msg2 "Running with graphics";
fi

# Add UEFI firmware if requested
if [[ "$UEFI_MODE" == true ]]; then
    # Create temporary VARS file for this session
    TEMP_VARS="/tmp/qemu-ovmf-vars-$$.fd"
    cp "$OVMF_VARS" "$TEMP_VARS"

    QEMU_CMD+=("-drive" "if=pflash,format=raw,readonly=on,file=$OVMF_CODE")
    QEMU_CMD+=("-drive" "if=pflash,format=raw,file=$TEMP_VARS")

    # Cleanup function for UEFI vars file
    cleanup_uefi() {
        if [[ -f "$TEMP_VARS" ]]; then
            rm -f "$TEMP_VARS"
        fi
    }
    trap cleanup_uefi EXIT
fi

msg2 "QEMU configuration:";
msg2 "  Memory: $MEMORY";
msg2 "  CPUs: $CPUS";
msg2 "  Boot mode: $([ "$UEFI_MODE" == true ] && echo "UEFI" || echo "BIOS")";
msg2 "  Boot source: $([ "$USE_DEVICE_PASSTHROUGH" == true ] && echo "Device passthrough ($BOOT_DEVICE)" || echo "ISO ($BOOT_SOURCE)")";
msg2 "  Graphics: $([ "$HEADLESS" == true ] && echo "Headless (VNC)" || echo "GUI")";
msg2 "  Networking: $([ "$HOST_NETWORKING" == true ] && echo "Host bridge" || echo "NAT/User")";

msg2 "Starting QEMU...";
msg2 "QEMU command: ${QEMU_CMD[*]}";

if [[ "$HEADLESS" == true ]]; then
    msg2 "Connect to VNC at localhost:5901 to access the VM";
    msg2 "Or use: vncviewer localhost:5901";
fi

msg2 "Press Ctrl+Alt+G to release mouse/keyboard from QEMU";
msg2 "Press Ctrl+Alt+2 to access QEMU monitor console";
msg2 "Press Ctrl+Alt+1 to return to main console";
msg2 "To quit QEMU: Press Ctrl+Alt+2, then type 'quit' and press Enter";

echo
msg "Starting virtual machine test...";

# Execute QEMU
exec "${QEMU_CMD[@]}"
