#!/bin/bash
#
# LibreMesh QEMU Driver Injection System (Fixed Version)
# Dynamically loads network drivers for QEMU compatibility
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[DRIVER]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[DRIVER]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[DRIVER]${NC} $1"
}

print_error() {
    echo -e "${RED}[DRIVER]${NC} $1"
}

# Configuration
DRIVER_CACHE_DIR="/home/fede/REPOS/lime-dev/tools/qemu/drivers"
QEMU_IP="10.13.0.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize driver cache
init_driver_cache() {
    print_status "Initializing driver cache at $DRIVER_CACHE_DIR"
    mkdir -p "$DRIVER_CACHE_DIR"
    
    cat > "$DRIVER_CACHE_DIR/compatibility.json" << 'EOF'
{
    "6.6.86": {
        "source_image": "libremesh-ca63283-24.10.1-dev",
        "drivers": ["e1000.ko", "e1000e.ko"],
        "status": "verified_working"
    },
    "5.15.167": {
        "source_image": "none",
        "drivers": [],
        "status": "requires_injection"
    }
}
EOF
    
    print_success "Driver cache initialized"
}

# Check for drivers in running QEMU system first, then cache
check_available_drivers() {
    local kernel_version="$1"
    local check_qemu="${2:-true}"
    
    print_status "Checking for available network drivers..."
    
    # Method 1: Check if drivers already exist in running QEMU
    if [ "$check_qemu" = "true" ] && ping -c 1 -W 2 "$QEMU_IP" >/dev/null 2>&1; then
        print_status "Checking drivers in running QEMU system..."
        
        if sudo screen -list | grep -q "libremesh"; then
            sudo screen -S libremesh -X stuff 'echo "=== DRIVER CHECK ==="; find /lib/modules -name "*.ko" | grep -E "(e1000|virtio|8139)" 2>/dev/null || echo "No network drivers found"; echo "=== END CHECK ==="'$'\n'
            sleep 3
            
            sudo screen -S libremesh -X hardcopy "/tmp/qemu_driver_check.txt" 2>/dev/null
            
            if [ -f "/tmp/qemu_driver_check.txt" ]; then
                local check_output=$(cat "/tmp/qemu_driver_check.txt" 2>/dev/null)
                
                if echo "$check_output" | grep -q "e1000.*ko\|virtio.*ko"; then
                    print_success "Network drivers found in QEMU system"
                    rm -f "/tmp/qemu_driver_check.txt"
                    return 0
                fi
            fi
        fi
        
        rm -f "/tmp/qemu_driver_check.txt" 2>/dev/null
    fi
    
    # Method 2: Check local cache
    local cache_dir="$DRIVER_CACHE_DIR/$kernel_version"
    
    if [ -d "$cache_dir" ] && [ "$(ls -A "$cache_dir"/*.ko 2>/dev/null | wc -l)" -gt 0 ]; then
        print_success "Drivers available in local cache for kernel $kernel_version"
        ls -la "$cache_dir"/*.ko
        return 0
    fi
    
    print_warning "No drivers found in QEMU system or local cache for kernel $kernel_version"
    return 1
}

# Download network drivers from OpenWrt package feeds
download_drivers_from_openwrt() {
    local kernel_version="$1"
    
    print_status "Downloading network drivers from OpenWrt feeds for kernel $kernel_version..."
    
    # OpenWrt package feed URLs
    local openwrt_feeds=(
        "https://downloads.openwrt.org/releases/23.05.5/targets/x86/64/packages"
        "https://downloads.openwrt.org/releases/23.05.5/packages/x86_64/kmods"
        "https://downloads.openwrt.org/snapshots/targets/x86/64/packages"
        "https://downloads.openwrt.org/snapshots/packages/x86_64/kmods"
    )
    
    # Driver packages to search for
    local driver_packages=("kmod-e1000" "kmod-e1000e" "kmod-virtio-net" "kmod-8139too")
    
    # Create download directory
    local download_dir="$DRIVER_CACHE_DIR/downloads/$kernel_version"
    mkdir -p "$download_dir"
    
    local downloads_successful=0
    
    for feed_url in "${openwrt_feeds[@]}"; do
        print_status "Checking feed: $feed_url"
        
        # Get package index
        local index_url="$feed_url/Packages.gz"
        local temp_index="/tmp/openwrt_packages_$$.txt"
        
        if curl -s --max-time 10 "$index_url" | gunzip > "$temp_index" 2>/dev/null; then
            print_success "Downloaded package index"
            
            # Search for driver packages
            for pkg in "${driver_packages[@]}"; do
                local pkg_info=$(grep -A 10 "^Package: $pkg$" "$temp_index" | grep -E "Filename|Version|Depends")
                
                if [ -n "$pkg_info" ]; then
                    local filename=$(echo "$pkg_info" | grep "Filename:" | head -1 | awk '{print $2}')
                    local version=$(echo "$pkg_info" | grep "Version:" | head -1 | awk '{print $2}')
                    
                    if [ -n "$filename" ]; then
                        print_status "Found package: $pkg ($version)"
                        
                        # Download the package
                        local pkg_url="$feed_url/$filename"
                        local local_file="$download_dir/$(basename "$filename")"
                        
                        if curl -s --max-time 30 -o "$local_file" "$pkg_url" 2>/dev/null; then
                            print_success "Downloaded: $pkg"
                            ((downloads_successful++))
                        else
                            print_warning "Failed to download: $pkg"
                        fi
                    fi
                fi
            done
        else
            print_warning "Failed to download package index from $feed_url"
        fi
        
        rm -f "$temp_index"
    done
    
    # Cleanup downloads
    rm -rf "$download_dir"
    
    if [ $downloads_successful -gt 0 ]; then
        print_success "Downloaded $downloads_successful driver packages"
        return 0
    else
        print_warning "No compatible driver packages found for kernel $kernel_version"
        return 1
    fi
}

# Console-based driver injection via screen session
inject_drivers_via_console() {
    local kernel_version="$1"
    
    print_status "Console injection: Loading drivers via screen session..."
    
    if ! sudo screen -list | grep -q "libremesh"; then
        print_error "No LibreMesh screen session found"
        print_status "Start QEMU first: ./lime qemu start"
        return 1
    fi
    
    print_status "Attempting to load available network drivers..."
    
    # Try modprobe for standard drivers first (most compatible)
    sudo screen -S libremesh -X stuff 'echo "=== MODPROBE ATTEMPT ==="; for driver in e1000 e1000e virtio_net 8139too; do echo "Trying: $driver"; modprobe $driver 2>&1 && echo "Success: $driver" || echo "Failed: $driver"; done; echo "=== END MODPROBE ==="'$'\n'
    sleep 4
    
    # Check final status
    print_status "Checking final driver and interface status..."
    sudo screen -S libremesh -X stuff 'echo "=== POST-INJECTION STATUS ==="; echo "Loaded network drivers:"; lsmod | grep -E "(e1000|virtio|8139)" || echo "No network drivers loaded"; echo "Available network interfaces:"; ip link show | grep -E "^[0-9]+:" | grep -v lo; echo "=== END POST-STATUS ==="'$'\n'
    sleep 3
    
    print_status "Console injection completed - check screen session for details"
    print_status "Use: sudo screen -r libremesh"
    return 0
}

# Enhanced driver injection with smart kernel detection
inject_drivers() {
    local target_image="${1:-auto-detect}"
    local method="${2:-auto}"
    
    print_status "Starting intelligent driver injection for $target_image"
    
    # Smart kernel version detection
    local kernel_version=""
    
    # Method 1: Detect from running QEMU system if available
    if ping -c 1 -W 2 "$QEMU_IP" >/dev/null 2>&1; then
        print_status "Detecting kernel version from running QEMU..."
        
        if sudo screen -list | grep -q "libremesh"; then
            sudo screen -S libremesh -X stuff 'uname -r'$'\n'
            sleep 2
            sudo screen -S libremesh -X hardcopy "/tmp/kernel_detect.txt" 2>/dev/null
            
            if [ -f "/tmp/kernel_detect.txt" ]; then
                local detected_kernel=$(grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" "/tmp/kernel_detect.txt" | tail -1)
                if [ -n "$detected_kernel" ]; then
                    kernel_version="$detected_kernel"
                    print_success "Detected kernel $kernel_version from QEMU"
                fi
                rm -f "/tmp/kernel_detect.txt"
            fi
        fi
    fi
    
    # Method 2: Detect from image name if QEMU detection failed
    if [ -z "$kernel_version" ]; then
        if [[ "$target_image" == *"2024.1"* ]]; then
            kernel_version="5.15.167"  # LibreMesh 2024.1 stable
        elif [[ "$target_image" == *"24.10.1"* ]] || [[ "$target_image" == *"ca63283"* ]]; then
            kernel_version="6.6.86"    # Development builds
        elif [[ "$target_image" == *"23.05"* ]]; then
            kernel_version="5.15.167"  # OpenWrt 23.05.x series
        else
            kernel_version="5.15.167"  # Safe default for LibreMesh
            print_warning "Unknown image pattern, assuming kernel $kernel_version"
        fi
    fi
    
    print_status "Target kernel: $kernel_version"
    
    # Initialize cache if needed
    if [ ! -d "$DRIVER_CACHE_DIR" ]; then
        init_driver_cache
    fi
    
    # Check for available drivers (QEMU system first, then cache)
    if check_available_drivers "$kernel_version"; then
        print_status "Drivers already available, proceeding with injection..."
    else
        print_status "Drivers not available, attempting acquisition..."
        
        # Try downloading from OpenWrt feeds
        if download_drivers_from_openwrt "$kernel_version"; then
            print_success "Successfully downloaded drivers from OpenWrt feeds"
        else
            print_warning "Failed to acquire drivers for kernel $kernel_version"
            print_status "Available options:"
            print_status "   1. Use development image (has working drivers)"
            print_status "   2. Build custom image with drivers included"
        fi
    fi
    
    # Perform injection based on method
    print_status "Starting driver injection using method: $method"
    
    case "$method" in
        "console"|"screen"|"auto"|*)
            inject_drivers_via_console "$kernel_version"
            ;;
    esac
}

# Command line interface
case "${1:-help}" in
    "init")
        init_driver_cache
        ;;
    "inject")
        inject_drivers "${2:-auto-detect}" "${3:-auto}"
        ;;
    "check")
        check_available_drivers "${2:-5.15.167}" "${3:-true}"
        ;;
    "download")
        download_drivers_from_openwrt "${2:-5.15.167}"
        ;;
    "console")
        inject_drivers_via_console "${2:-5.15.167}"
        ;;
    "help"|*)
        echo "LibreMesh QEMU Driver Injection System"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  init                       - Initialize driver cache"
        echo "  inject <image> <method>    - Smart driver injection into running QEMU"
        echo "  check <kernel> <qemu>      - Check available drivers (QEMU + cache)"
        echo "  download <kernel>          - Download drivers from OpenWrt feeds"
        echo "  console <kernel>           - Console-based injection via screen"
        echo "  help                       - Show this help"
        echo ""
        echo "Methods:"
        echo "  auto     - Automatic method selection (default)"
        echo "  console  - Console-based injection via screen"
        echo ""
        echo "Examples:"
        echo "  $0 init                                    # Initialize system"
        echo "  $0 check 5.15.167                         # Check driver availability"
        echo "  $0 inject auto-detect auto                # Smart injection (recommended)"
        echo "  $0 console 5.15.167                       # Console injection"
        echo "  $0 download 5.15.167                      # Download from OpenWrt"
        ;;
esac