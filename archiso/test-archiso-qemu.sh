#!/bin/bash

# QEMU Test Script for Custom Arch ISO
# Tests the custom archiso build using QEMU virtual machine
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

# Configuration
OUTPUT_DIR="/tmp/archiso-output"
QEMU_MEMORY="4G"
QEMU_CPUS="2"
OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"

# Parse command line arguments
HEADLESS=false
UEFI_MODE=true
MEMORY="$QEMU_MEMORY"
CPUS="$QEMU_CPUS"

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
    --iso PATH          Use specific ISO file instead of auto-detection

EXAMPLES:
    $0                          # Test with default settings
    $0 -m 8G -c 4              # Test with 8GB RAM and 4 CPUs
    $0 --bios                  # Test in legacy BIOS mode
    $0 --headless              # Test without graphics
    $0 --iso /path/to/test.iso # Test specific ISO file

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
        --iso)
            CUSTOM_ISO="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

msg "Testing Custom Arch ISO with QEMU";

# Check if QEMU is installed
if ! command -v qemu-system-x86_64 &>/dev/null; then
    error "QEMU is not installed. Install with: pacman -S qemu-desktop";
    exit 1;
fi

# Find ISO file
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
        error "Run custom-archiso.sh first to build the ISO";
        exit 1;
    fi

    ISO_FILE=$(find "$OUTPUT_DIR" -name "*.iso" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -z "$ISO_FILE" ]]; then
        error "No ISO file found in $OUTPUT_DIR";
        error "Run custom-archiso.sh first to build the ISO";
        exit 1;
    fi
    
    msg2 "Auto-detected ISO: $ISO_FILE";
fi

# Check ISO file size and modification time
ISO_SIZE=$(du -h "$ISO_FILE" | cut -f1)
ISO_DATE=$(stat -c '%y' "$ISO_FILE" | cut -d'.' -f1)
msg2 "ISO size: $ISO_SIZE";
msg2 "ISO created: $ISO_DATE";

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
    "-cdrom" "$ISO_FILE"
    "-boot" "d"
    "-netdev" "user,id=net0"
    "-device" "e1000,netdev=net0"
)

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
msg2 "  Graphics: $([ "$HEADLESS" == true ] && echo "Headless (VNC)" || echo "GUI")";

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