#!/usr/bin/env bash
#
# Official LibreMesh lime-app development integration script
# 
# This script follows the official workflow documented in:
# - lime-packages/TESTING.md (line 241)
# - lime-packages/packages/lime-app/Makefile (lines 39-40)
#
# Usage: ./scripts/deploy-to-qemu.sh [--build-only] [--start-qemu]
#

set -e

# Configuration
LIME_PACKAGES_DIR="../lime-packages"
LIME_APP_FILES_DIR="$LIME_PACKAGES_DIR/packages/lime-app/files/www/app"
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

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if [ ! -d "$LIME_PACKAGES_DIR" ]; then
        print_error "lime-packages directory not found at $LIME_PACKAGES_DIR"
        print_error "Please ensure lime-packages is cloned in the parent directory"
        exit 1
    fi
    
    if [ ! -f "$ROOTFS_PATH" ]; then
        print_error "LibreMesh rootfs not found at $ROOTFS_PATH"
        print_error "Please download the LibreMesh development images"
        exit 1
    fi
    
    if [ ! -f "$KERNEL_PATH" ]; then
        print_error "LibreMesh kernel not found at $KERNEL_PATH"
        print_error "Please download the LibreMesh development images"
        exit 1
    fi
    
    print_status "Prerequisites check passed"
}

# Build lime-app for router environment
build_lime_app() {
    print_status "Building lime-app for LibreMesh router..."
    
    # Check if build:production exists, fallback to build
    if npm run | grep -q "build:production"; then
        npm run build:production
    else
        npm run build
    fi
    
    if [ ! -d "build" ]; then
        print_error "Build directory not found. Build failed?"
        exit 1
    fi
    
    print_status "lime-app build completed"
}

# Deploy to lime-packages (official method)
deploy_to_lime_packages() {
    print_status "Deploying lime-app to lime-packages (official method)..."
    
    # Create the app directory in lime-packages
    mkdir -p "$LIME_APP_FILES_DIR"
    
    # Copy build files (official LibreMesh workflow)
    cp -r build/* "$LIME_APP_FILES_DIR/"
    
    print_status "lime-app deployed to lime-packages/packages/lime-app/files/www/app/"
    print_status "Files deployed:"
    ls -la "$LIME_APP_FILES_DIR" | head -10
}

# Start QEMU with lime-app integration
start_qemu() {
    print_status "Starting QEMU LibreMesh with lime-app integration..."
    
    print_warning "LibreMesh will be available at: http://10.13.0.1"
    print_warning "lime-app will be available at: http://10.13.0.1/app"
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_status "Running as root..."
        "$LIME_PACKAGES_DIR/tools/qemu_dev_start" \
            --libremesh-workdir "$LIME_PACKAGES_DIR" \
            "$ROOTFS_PATH" \
            "$KERNEL_PATH"
    # Check if sudo is available and user is in sudoers
    elif command -v sudo >/dev/null 2>&1 && sudo -l >/dev/null 2>&1; then
        print_status "Running with sudo..."
        sudo "$LIME_PACKAGES_DIR/tools/qemu_dev_start" \
            --libremesh-workdir "$LIME_PACKAGES_DIR" \
            "$ROOTFS_PATH" \
            "$KERNEL_PATH"
    else
        print_warning "sudo not available or user not in sudoers"
        print_status "Using 'su' to run as root..."
        print_warning "You will be prompted for the root password"
        
        QEMU_CMD="$LIME_PACKAGES_DIR/tools/qemu_dev_start --libremesh-workdir $LIME_PACKAGES_DIR $ROOTFS_PATH $KERNEL_PATH"
        su -c "$QEMU_CMD"
    fi
}

# Parse command line arguments
BUILD_ONLY=false
START_QEMU=false

for arg in "$@"; do
    case $arg in
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --start-qemu)
            START_QEMU=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--build-only] [--start-qemu]"
            echo ""
            echo "Options:"
            echo "  --build-only    Only build and deploy lime-app, don't start QEMU"
            echo "  --start-qemu    Also start QEMU after building and deploying"
            echo "  --help          Show this help message"
            echo ""
            echo "Default behavior: Build and deploy lime-app only"
            echo ""
            echo "Examples:"
            echo "  $0                    # Build and deploy only"
            echo "  $0 --start-qemu       # Build, deploy, and start QEMU"
            echo "  $0 --build-only       # Same as default"
            exit 0
            ;;
        *)
            print_error "Unknown option: $arg"
            print_error "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main execution
print_status "=== LibreMesh lime-app Development Integration ==="
print_status "Following official LibreMesh development workflow"

check_prerequisites
build_lime_app
deploy_to_lime_packages

if [ "$START_QEMU" = true ]; then
    start_qemu
else
    print_status "=== Deployment Complete ==="
    print_status "lime-app has been deployed to lime-packages"
    print_status ""
    print_status "To start QEMU LibreMesh:"
    print_status "  $0 --start-qemu"
    print_status ""
    print_status "Or manually:"
    print_status "  cd $LIME_PACKAGES_DIR"
    print_status "  sudo ./tools/qemu_dev_start --libremesh-workdir . $ROOTFS_PATH $KERNEL_PATH"
fi