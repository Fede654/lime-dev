#!/usr/bin/env bash
#
# LibreMesh QEMU startup for Debian systems without sudo
# 
# This script handles QEMU startup using 'su' for root privileges
# when sudo is not configured for the current user.
#

set -e

# Configuration
LIME_PACKAGES_DIR="../lime-packages"
ROOTFS_PATH="$LIME_PACKAGES_DIR/build/libremesh-2024.1-ow23.05.5-default-x86-64-generic-squashfs-rootfs.img.gz"
KERNEL_PATH="$LIME_PACKAGES_DIR/build/libremesh-2024.1-ow23.05.5-default-x86-64-generic-initramfs-kernel.bin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if [ ! -d "$LIME_PACKAGES_DIR" ]; then
        print_error "lime-packages directory not found at $LIME_PACKAGES_DIR"
        exit 1
    fi
    
    if [ ! -f "$ROOTFS_PATH" ]; then
        print_error "LibreMesh rootfs not found at $ROOTFS_PATH"
        exit 1
    fi
    
    if [ ! -f "$KERNEL_PATH" ]; then
        print_error "LibreMesh kernel not found at $KERNEL_PATH"
        exit 1
    fi
    
    print_status "Prerequisites check passed"
}

start_qemu_as_root() {
    print_status "Starting QEMU LibreMesh as root..."
    print_warning "You will be prompted for the root password"
    
    # Create the command that will run as root
    QEMU_CMD="$LIME_PACKAGES_DIR/tools/qemu_dev_start --libremesh-workdir $LIME_PACKAGES_DIR $ROOTFS_PATH $KERNEL_PATH"
    
    print_status "Command: $QEMU_CMD"
    print_status "Switching to root..."
    
    # Use 'su' to run the command as root
    su -c "$QEMU_CMD"
}

# Check if we're already root
if [ "$EUID" -eq 0 ]; then
    print_status "Already running as root"
    check_prerequisites
    
    # Run directly without su
    "$LIME_PACKAGES_DIR/tools/qemu_dev_start" \
        --libremesh-workdir "$LIME_PACKAGES_DIR" \
        "$ROOTFS_PATH" \
        "$KERNEL_PATH"
else
    print_status "=== LibreMesh QEMU Startup (Root Mode) ==="
    print_status "Running on Debian without sudo configuration"
    
    check_prerequisites
    start_qemu_as_root
fi