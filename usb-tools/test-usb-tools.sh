#!/bin/bash

# Test USB Tools Script
# Runs the complete workflow for creating and testing USB tools system
# Based on the Quick Start commands in README.md

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

# Check if running as root
if [[ "$(id -u)" != "0" ]]; then
    error "This script must be run as root";
    exit 1;
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DEVICE=""

# Parse command line arguments
SKIP_BUILD=false
SKIP_TEST=false
AUTO_YES=false

show_help() {
    cat << EOF
Usage: $0 --device DEVICE [OPTIONS]

Complete USB tools creation and test workflow

REQUIRED:
    --device DEVICE     Target device for flashing (e.g., /dev/sdb, /dev/mmcblk0)

OPTIONS:
    -h, --help          Show this help message
    --skip-build        Skip USB tools creation step
    --skip-test         Skip QEMU test step
    -y, --yes           Answer yes to all prompts in downstream scripts

EXAMPLES:
    $0 --device /dev/sdb                    # Full workflow
    $0 --device /dev/sdb --skip-build       # Skip creation, use existing USB system
    $0 --device /dev/sdb --skip-test        # Only create USB system
    $0 --device /dev/sdb --yes             # Full workflow, auto-answer prompts

EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-test)
            SKIP_TEST=true
            shift
            ;;
        --device)
            TEST_DEVICE="$2"
            shift 2
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

# Check that device is specified
if [[ -z "$TEST_DEVICE" ]]; then
    error "Device must be specified with --device"
    show_help
    exit 1
fi

msg "Starting complete USB tools workflow"
msg2 "Create USB tools: $([[ "$SKIP_BUILD" == true ]] && echo "SKIP" || echo "YES")"
msg2 "Test in QEMU: $([[ "$SKIP_TEST" == true ]] && echo "SKIP" || echo "YES")"

# Step 1: Create USB tools system
if [[ "$SKIP_BUILD" == false ]]; then
    msg "Step 1: Creating USB tools system"
    
    # Add --device and optional --force flag
    BUILD_ARGS=("--device" "$TEST_DEVICE")
    if [[ "$AUTO_YES" == true ]]; then
        BUILD_ARGS+=("--force")
    fi
    
    if ! "$SCRIPT_DIR/create-usb-tools.sh" "${BUILD_ARGS[@]}"; then
        error "USB tools creation failed"
        exit 1
    fi
    msg2 "USB tools creation completed successfully"
else
    msg "Step 1: Skipping USB tools creation"
fi

# USB tools system created directly on device - no ISO file needed
msg2 "USB tools system created on device: $TEST_DEVICE"

# Step 2: Test in QEMU
if [[ "$SKIP_TEST" == false ]]; then
    msg "Step 2: Testing in QEMU"
    
    # Add common QEMU args
    QEMU_ARGS=("--no-host-networking")
    if [[ "$AUTO_YES" == true ]]; then
        QEMU_ARGS+=("--yes")
    fi
    
    # Test with the USB device
    if ! "$SCRIPT_DIR/test-usb-tools-qemu.sh" "${QEMU_ARGS[@]}" --device "$TEST_DEVICE"; then
        error "QEMU test failed"
        exit 1
    fi
    msg2 "QEMU test completed successfully"
else
    msg "Step 2: Skipping QEMU test"
fi

msg "Complete USB tools workflow finished successfully!"
msg2 "USB device: $TEST_DEVICE"