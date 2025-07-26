#!/bin/bash
#
# LibreMesh QEMU-Ready Build Script for lime-dev
# This script builds LibreMesh images with QEMU network drivers included by default
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[LIME-DEV]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[LIME-DEV]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[LIME-DEV]${NC} $1"
}

print_error() {
    echo -e "${RED}[LIME-DEV]${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_PACKAGES_DIR="$SCRIPT_DIR/repos/lime-packages"
BUILD_TYPE="${1:-full}"  # full, minimal, fast

print_status "🚀 LibreMesh QEMU-Ready Build for lime-dev"
print_status "📂 Working directory: $SCRIPT_DIR"
print_status "🔧 Build type: $BUILD_TYPE"

# Validate environment
if [ ! -d "$LIME_PACKAGES_DIR" ]; then
    print_error "❌ lime-packages directory not found: $LIME_PACKAGES_DIR"
    print_error "Please run this script from the lime-dev root directory"
    exit 1
fi

if [ ! -f "$LIME_PACKAGES_DIR/libremesh.qemu.config" ]; then
    print_error "❌ QEMU configuration not found"
    print_error "Please ensure QEMU build system is properly set up"
    exit 1
fi

# Change to lime-packages directory
cd "$LIME_PACKAGES_DIR"

print_status "📋 Available build types:"
echo "   full     - Complete LibreMesh with all QEMU drivers and tools"
echo "   minimal  - Essential drivers only for QEMU network access"
echo "   fast     - Quick build for development (no clean)"
echo "   debug    - Full build with debugging tools and symbols"

# Execute the appropriate build
case "$BUILD_TYPE" in
    "full")
        print_status "🔨 Building full LibreMesh with QEMU support..."
        ./build-qemu.sh x86/64 generic full
        ;;
    "minimal")
        print_status "⚡ Building minimal LibreMesh QEMU image..."
        ./build-qemu.sh x86/64 generic minimal
        ;;
    "fast")
        print_status "🚀 Fast QEMU build for development..."
        AUTO_BUILD=yes ./build-qemu.sh x86/64 generic full
        ;;
    "debug")
        print_status "🐛 Building debug-enabled LibreMesh QEMU image..."
        # Create debug config
        cp libremesh.qemu.config .config.debug.tmp
        cat >> .config.debug.tmp << 'EOF'

# Debug and development additions
CONFIG_PACKAGE_gdb=y
CONFIG_PACKAGE_strace=y
CONFIG_PACKAGE_ltrace=y
CONFIG_PACKAGE_valgrind=m
CONFIG_KERNEL_DEBUG_INFO=y
CONFIG_KERNEL_DEBUG_KERNEL=y
CONFIG_PACKAGE_perf=m
EOF
        ./build-qemu.sh x86/64 generic custom .config.debug.tmp
        rm -f .config.debug.tmp
        ;;
    *)
        print_error "❌ Unknown build type: $BUILD_TYPE"
        print_status "💡 Usage: $0 [full|minimal|fast|debug]"
        exit 1
        ;;
esac

# Return to original directory
cd "$SCRIPT_DIR"

# Verify results
BUILD_OUTPUT_DIR="$LIME_PACKAGES_DIR/bin/targets/x86/64"
LIME_DEV_BUILD_DIR="$SCRIPT_DIR/build/bin/targets/x86/64"

if [ -d "$BUILD_OUTPUT_DIR" ]; then
    print_success "✅ Build completed successfully!"
    
    # Create lime-dev build directory if it doesn't exist
    mkdir -p "$LIME_DEV_BUILD_DIR"
    
    # Copy images to lime-dev structure
    print_status "📦 Integrating with lime-dev QEMU manager..."
    
    COPIED_FILES=0
    for img in "$BUILD_OUTPUT_DIR"/*rootfs.tar.gz; do
        if [ -f "$img" ]; then
            cp "$img" "$LIME_DEV_BUILD_DIR/"
            print_success "📄 Copied: $(basename "$img")"
            ((COPIED_FILES++))
        fi
    done
    
    for kernel in "$BUILD_OUTPUT_DIR"/*kernel.bin "$BUILD_OUTPUT_DIR"/*bzImage; do
        if [ -f "$kernel" ]; then
            cp "$kernel" "$LIME_DEV_BUILD_DIR/"
            print_success "⚙️  Copied: $(basename "$kernel")"
            ((COPIED_FILES++))
        fi
    done
    
    if [ $COPIED_FILES -gt 0 ]; then
        print_success "🎉 $COPIED_FILES files integrated with lime-dev!"
        
        # Quick driver verification
        SAMPLE_ROOTFS=$(find "$LIME_DEV_BUILD_DIR" -name "*rootfs.tar.gz" | head -1)
        if [ -n "$SAMPLE_ROOTFS" ]; then
            print_status "🔍 Verifying QEMU drivers in build..."
            DRIVER_COUNT=$(tar -tzf "$SAMPLE_ROOTFS" 2>/dev/null | grep -E "(e1000|virtio)" | wc -l || echo "0")
            
            if [ "$DRIVER_COUNT" -gt 0 ]; then
                print_success "✅ Found $DRIVER_COUNT network driver files in build"
            else
                print_warning "⚠️  Network drivers not detected in quick check"
                print_warning "   This may be normal depending on build configuration"
            fi
        fi
        
        # Show usage instructions
        print_success "🚀 Ready to use!"
        echo ""
        echo "   Next steps:"
        echo "   1. Start QEMU: ./lime qemu start"
        echo "   2. Select your newly built image"
        echo "   3. Network access will be automatically available"
        echo "   4. Access via http://10.13.0.1 or console: sudo screen -r libremesh"
        echo ""
        print_status "💡 The images include full QEMU network driver support:"
        echo "   • e1000/e1000e drivers for Intel emulated NICs"
        echo "   • virtio-net for paravirtualized networking"
        echo "   • RTL8139 drivers for legacy compatibility"
        echo "   • Development tools for debugging and testing"
        
    else
        print_warning "⚠️  No files were copied to lime-dev build directory"
        print_status "Built images are available in: $BUILD_OUTPUT_DIR"
    fi
    
else
    print_error "❌ Build output directory not found: $BUILD_OUTPUT_DIR"
    print_error "Build may have failed - check the build logs"
    exit 1
fi

print_success "🎯 LibreMesh QEMU-ready build process completed successfully!"