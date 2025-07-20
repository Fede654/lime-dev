#!/usr/bin/env bash
#
# Standardized QEMU LibreMesh Management Script
# Handles QEMU lifecycle with proper cleanup and restart
#
# Usage: ./scripts/qemu-manager.sh {start|stop|restart|status|deploy}
#

set -e

# Configuration - Updated for lime-dev/tools/qemu/ location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_DEV_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIME_PACKAGES_DIR="$LIME_DEV_DIR/repos/lime-packages"
LIME_APP_DIR="$LIME_DEV_DIR/repos/lime-app"
LIME_APP_FILES_DIR="$LIME_PACKAGES_DIR/packages/lime-app/files/www/app"

# Use unified lime-dev build directory structure
BUILD_DIR="$LIME_DEV_DIR/build"
BIN_DIR="$BUILD_DIR/bin/targets/x86/64"

# Auto-detect available images in the new build structure
detect_build_images() {
    # Find all available rootfs images (tar.gz format only for QEMU)
    local rootfs_files=()
    local kernel_files=()
    local search_location=""
    
    # Search in entire unified build directory first
    print_status "Searching for firmware images..."
    while IFS= read -r -d '' file; do
        rootfs_files+=("$file")
    done < <(find "$BUILD_DIR" -name "*-x86-64-*rootfs.tar.gz" -print0 2>/dev/null)
    
    if [ ${#rootfs_files[@]} -gt 0 ]; then
        search_location="unified build directory"
    else
        # First fallback: dl/ directory
        print_warning "No images found in build/, searching in dl/ directory..."
        local dl_dir="$LIME_DEV_DIR/dl"
        if [ -d "$dl_dir" ]; then
            while IFS= read -r -d '' file; do
                rootfs_files+=("$file")
            done < <(find "$dl_dir" -name "*-x86-64-*rootfs.tar.gz" -print0 2>/dev/null)
            
            if [ ${#rootfs_files[@]} -gt 0 ]; then
                search_location="dl/ fallback directory"
                print_warning "⚠️  Using fallback location: $dl_dir"
                print_warning "   Consider moving images to build/ for standard workflow"
            fi
        fi
    fi
    
    # Second fallback: legacy lime-packages/build
    if [ ${#rootfs_files[@]} -eq 0 ]; then
        print_warning "No images found in dl/, searching in legacy lime-packages/build..."
        if [ -d "$LIME_PACKAGES_DIR/build" ]; then
            while IFS= read -r -d '' file; do
                rootfs_files+=("$file")
            done < <(find "$LIME_PACKAGES_DIR/build" -name "*-x86-64-*rootfs.tar.gz" -print0 2>/dev/null)
            
            if [ ${#rootfs_files[@]} -gt 0 ]; then
                search_location="legacy lime-packages/build"
                print_warning "⚠️  Using legacy fallback: $LIME_PACKAGES_DIR/build"
                print_warning "   This is deprecated - please use unified build structure"
            fi
        fi
    fi
    
    # If no images found, error out
    if [ ${#rootfs_files[@]} -eq 0 ]; then
        print_error "No compatible rootfs images found (*.tar.gz format required)"
        print_error "Searched locations:"
        print_error "  1. $BUILD_DIR (primary)"
        print_error "  2. $LIME_DEV_DIR/dl (fallback)"
        print_error "  3. $LIME_PACKAGES_DIR/build (legacy)"
        exit 1
    fi
    
    print_status "Found ${#rootfs_files[@]} image(s) in $search_location"
    
    # If only one image found, use it automatically
    if [ ${#rootfs_files[@]} -eq 1 ]; then
        ROOTFS_PATH="${rootfs_files[0]}"
        # Find matching kernel
        local rootfs_base=$(basename "$ROOTFS_PATH" | sed 's/-rootfs.tar.gz//')
        KERNEL_PATH=$(find "$(dirname "$ROOTFS_PATH")" -name "${rootfs_base}*kernel.bin" 2>/dev/null | head -1)
        
        if [ -z "$KERNEL_PATH" ]; then
            # Try generic kernel pattern
            KERNEL_PATH=$(find "$(dirname "$ROOTFS_PATH")" -name "*-x86-64-*kernel.bin" 2>/dev/null | head -1)
        fi
        return
    fi
    
    # Multiple images found - show picker
    print_status "Multiple firmware images found. Please select one:"
    echo
    
    # Display options
    local i=1
    for rootfs in "${rootfs_files[@]}"; do
        local name=$(basename "$rootfs")
        # Highlight working/recommended images
        if [[ "$name" == *"libremesh-2024.1"* ]]; then
            echo "  $i) $name [RECOMMENDED - Working]"
        elif [[ "$name" == *"libremesh"* ]]; then
            echo "  $i) $name [LibreMesh]"
        elif [[ "$name" == *"librerouteros"* ]]; then
            echo "  $i) $name [LibreRouterOS - Boot issues]"
        else
            echo "  $i) $name"
        fi
        ((i++))
    done
    
    echo
    read -p "Select image number (1-${#rootfs_files[@]}): " selection
    
    # Validate selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#rootfs_files[@]} ]; then
        print_error "Invalid selection"
        exit 1
    fi
    
    # Set selected image
    ROOTFS_PATH="${rootfs_files[$((selection-1))]}"
    
    # Find matching kernel
    local rootfs_base=$(basename "$ROOTFS_PATH" | sed 's/-rootfs.tar.gz//')
    KERNEL_PATH=$(find "$(dirname "$ROOTFS_PATH")" -name "${rootfs_base}*kernel.bin" 2>/dev/null | head -1)
    
    if [ -z "$KERNEL_PATH" ]; then
        # Try to find any kernel in the same directory
        print_warning "Could not find exact matching kernel, searching for compatible kernel..."
        local kernel_files=()
        while IFS= read -r -d '' file; do
            kernel_files+=("$file")
        done < <(find "$(dirname "$ROOTFS_PATH")" -name "*-x86-64-*kernel.bin" -print0 2>/dev/null)
        
        if [ ${#kernel_files[@]} -eq 1 ]; then
            KERNEL_PATH="${kernel_files[0]}"
        elif [ ${#kernel_files[@]} -gt 1 ]; then
            print_status "Multiple kernels found. Please select one:"
            echo
            local i=1
            for kernel in "${kernel_files[@]}"; do
                echo "  $i) $(basename "$kernel")"
                ((i++))
            done
            echo
            read -p "Select kernel number (1-${#kernel_files[@]}): " kernel_selection
            
            if ! [[ "$kernel_selection" =~ ^[0-9]+$ ]] || [ "$kernel_selection" -lt 1 ] || [ "$kernel_selection" -gt ${#kernel_files[@]} ]; then
                print_error "Invalid selection"
                exit 1
            fi
            
            KERNEL_PATH="${kernel_files[$((kernel_selection-1))]}"
        fi
    fi
}

# Note: Image validation is done in check_prerequisites function

QEMU_IP="10.13.0.1"
TELNET_PORT="45400"

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

# Check if QEMU is running by testing connectivity and process
check_qemu_running() {
    # First check if QEMU process is running
    if ! pgrep -f "qemu-system-x86_64" >/dev/null 2>&1; then
        return 1  # No process running
    fi
    
    # Then check if we can reach the QEMU instance
    if ping -c 1 -W 1 "$QEMU_IP" >/dev/null 2>&1; then
        return 0  # Running and accessible
    else
        return 1  # Process running but not accessible
    fi
}

# Check for existing QEMU processes and screen sessions
check_existing_qemu() {
    local qemu_pids=()
    local screen_sessions=()
    
    # Find QEMU processes
    while IFS= read -r -d '' pid; do
        qemu_pids+=("$pid")
    done < <(pgrep -f "qemu-system-x86_64" -z 2>/dev/null)
    
    # Find screen sessions that might be QEMU-related
    local screen_list=$(sudo screen -list 2>/dev/null | grep -E "(libremesh|qemu)" || true)
    if [ -n "$screen_list" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ [[:space:]]*([0-9]+\.[^[:space:]]+) ]]; then
                screen_sessions+=("${BASH_REMATCH[1]}")
            fi
        done <<< "$screen_list"
    fi
    
    # If we have running processes or sessions, offer management options
    if [ ${#qemu_pids[@]} -gt 0 ] || [ ${#screen_sessions[@]} -gt 0 ]; then
        print_warning "Found existing QEMU processes or screen sessions:"
        echo
        
        if [ ${#qemu_pids[@]} -gt 0 ]; then
            print_status "QEMU processes:"
            for pid in "${qemu_pids[@]}"; do
                local cmd=$(ps -p "$pid" -o cmd --no-headers 2>/dev/null | cut -c1-80)
                echo "  PID $pid: $cmd..."
            done
            echo
        fi
        
        if [ ${#screen_sessions[@]} -gt 0 ]; then
            print_status "Screen sessions:"
            local i=1
            for session in "${screen_sessions[@]}"; do
                echo "  $i) $session"
                ((i++))
            done
            echo
        fi
        
        echo "Options:"
        echo "  1) Stop all and start fresh"
        [ ${#screen_sessions[@]} -gt 0 ] && echo "  2) Connect to existing screen session"
        echo "  3) Cancel"
        echo
        
        read -p "Select option: " choice
        
        case "$choice" in
            1)
                print_status "Stopping all existing QEMU processes and sessions..."
                kill_qemu_processes
                return 0  # Continue with new startup
                ;;
            2)
                if [ ${#screen_sessions[@]} -eq 0 ]; then
                    print_error "No screen sessions available"
                    exit 1
                elif [ ${#screen_sessions[@]} -eq 1 ]; then
                    print_status "Connecting to screen session: ${screen_sessions[0]}"
                    sudo screen -r "${screen_sessions[0]}"
                    exit 0
                else
                    echo "Select screen session:"
                    local i=1
                    for session in "${screen_sessions[@]}"; do
                        echo "  $i) $session"
                        ((i++))
                    done
                    echo
                    read -p "Select session number (1-${#screen_sessions[@]}): " session_choice
                    
                    if ! [[ "$session_choice" =~ ^[0-9]+$ ]] || [ "$session_choice" -lt 1 ] || [ "$session_choice" -gt ${#screen_sessions[@]} ]; then
                        print_error "Invalid selection"
                        exit 1
                    fi
                    
                    local selected_session="${screen_sessions[$((session_choice-1))]}"
                    print_status "Connecting to screen session: $selected_session"
                    sudo screen -r "$selected_session"
                    exit 0
                fi
                ;;
            3|*)
                print_status "Cancelled"
                exit 0
                ;;
        esac
    fi
}

# Auto-configure LibreMesh network after boot
setup_libremesh_network() {
    print_status "Waiting for LibreMesh boot to complete..."
    
    # Wait for LibreMesh to fully boot (look for specific boot messages)
    for i in {1..15}; do
        # Check if we can see the root prompt or system is ready
        sudo screen -S libremesh -X hardcopy /tmp/boot_check.txt 2>/dev/null
        if grep -q "root@.*:/#" /tmp/boot_check.txt 2>/dev/null; then
            print_status "✓ LibreMesh boot completed"
            break
        fi
        
        # Send Enter periodically to activate console
        if [ $((i % 3)) -eq 0 ]; then
            sudo screen -S libremesh -X stuff $'\n' 2>/dev/null || true
        fi
        
        sleep 2
        echo -n "."
    done
    echo
    
    print_status "Running smart network diagnosis and configuration..."
    
    # Step 1: Comprehensive interface detection
    print_status "📊 Detecting available network interfaces..."
    sudo screen -S libremesh -X stuff 'echo "=== INTERFACE DETECTION ==="; ip link show; echo "=== END INTERFACES ==="'$'\n'
    sleep 3
    
    # Step 2: Check for missing network drivers (common QEMU issue)
    print_status "🔍 Checking for network driver availability..."
    sudo screen -S libremesh -X stuff 'echo "=== DRIVER CHECK ==="; find /lib/modules -name "*e1000*" -o -name "*virtio*" 2>/dev/null | head -5; echo "=== MODPROBE TEST ==="; modprobe e1000 2>&1 || echo "e1000 not available"; modprobe virtio_net 2>&1 || echo "virtio_net not available"; echo "=== DRIVERS LOADED ==="; lsmod | grep -E "(e1000|virtio)" || echo "No QEMU network drivers found"; echo "=== END DRIVER CHECK ==="'$'\n'
    sleep 4
    
    # Step 3: Re-scan interfaces after driver loading attempt
    print_status "🔄 Re-scanning interfaces after driver loading..."
    sudo screen -S libremesh -X stuff 'echo "=== POST-DRIVER INTERFACES ==="; ip link show; echo "=== END POST-DRIVER ==="'$'\n'
    sleep 2
    
    # Step 4: Smart interface configuration with multiple strategies
    print_status "⚙️  Applying smart network configuration..."
    
    # Strategy 1: Try to configure any available ethernet interface
    sudo screen -S libremesh -X stuff 'echo "=== NETWORK CONFIG ATTEMPT ==="; for iface in $(ip link show | grep -o "^[0-9]*: eth[0-9]*" | cut -d: -f2 | tr -d " "); do echo "Trying interface: $iface"; if ip addr add 10.13.0.1/16 dev $iface 2>/dev/null && ip link set $iface up 2>/dev/null; then echo "✓ Successfully configured $iface"; break; fi; done'$'\n'
    sleep 3
    
    # Strategy 2: Try bridge interfaces (LibreMesh default)
    sudo screen -S libremesh -X stuff 'for iface in br-lan br0 lime; do if ip link show $iface >/dev/null 2>&1; then echo "Trying bridge: $iface"; if ! ip addr show $iface | grep -q "10.13.0.1"; then ip addr add 10.13.0.1/16 dev $iface 2>/dev/null && ip link set $iface up 2>/dev/null && echo "✓ Bridge $iface configured"; fi; fi; done'$'\n'
    sleep 2
    
    # Strategy 3: Check final network status
    sudo screen -S libremesh -X stuff 'echo "=== FINAL NETWORK STATUS ==="; ip addr show | grep -A1 "10.13.0.1" || echo "❌ No IP configured - this is a driver/compatibility issue"; echo "=== CONNECTIVITY TEST ==="; ping -c 1 10.13.0.2 2>/dev/null && echo "✓ Host connectivity working" || echo "⚠️  Host not reachable (normal if no IP configured)"; echo "=== END NETWORK STATUS ==="'$'\n'
    sleep 3
    
    # Step 5: Service configuration
    print_status "🚀 Starting essential services..."
    sudo screen -S libremesh -X stuff 'echo -e "admin\\nadmin" | passwd root'$'\n'
    sleep 2
    
    sudo screen -S libremesh -X stuff '/etc/init.d/uhttpd start 2>/dev/null && echo "✓ uHTTPd started" || echo "⚠️  uHTTPd start failed"'$'\n'
    sleep 2
    
    sudo screen -S libremesh -X stuff '/etc/init.d/ubus start 2>/dev/null && echo "✓ ubus started" || echo "⚠️  ubus not available in this image"'$'\n'
    sleep 2
    
    # Step 6: Comprehensive status report
    print_status "📋 Generating final diagnosis report..."
    sudo screen -S libremesh -X stuff 'echo "=== QEMU NETWORK DIAGNOSIS REPORT ==="; echo "Firmware: $(cat /etc/openwrt_release | grep DISTRIB_DESCRIPTION | cut -d\"'"'"'\" -f2)"; echo "Kernel: $(uname -r)"; echo "Network Interfaces:"; ip link show | grep -E "^[0-9]+:" | grep -v lo; echo "IP Configuration:"; ip addr show | grep "inet " | grep -v "127.0.0.1"; echo "Running Services:"; ps | grep -E "(uhttpd|ubus)" | grep -v grep || echo "No web services running"; echo "=== END DIAGNOSIS ==="; echo "Default credentials: root/admin"'$'\n'
    sleep 3
    
    # Capture final diagnosis for host-side analysis
    sudo screen -S libremesh -X hardcopy /tmp/qemu_diagnosis.txt 2>/dev/null
    
    print_status "Network configuration completed - check console for detailed diagnosis"
    sudo rm -f /tmp/boot_check.txt 2>/dev/null || true
    
    # Parse diagnosis and provide intelligent feedback with actual results
    if [ -f /tmp/qemu_diagnosis.txt ]; then
        # Convert binary file to strings and analyze
        local diagnosis_text=$(strings /tmp/qemu_diagnosis.txt 2>/dev/null || cat /tmp/qemu_diagnosis.txt 2>/dev/null)
        
        if echo "$diagnosis_text" | grep -q "No QEMU network drivers found" 2>/dev/null; then
            print_warning "⚠️  Network drivers missing - this LibreMesh build lacks QEMU support"
            print_warning "   This is common with hardware-specific builds"
            print_warning "   Console access available via: sudo screen -r libremesh"
        elif echo "$diagnosis_text" | grep -q "10.13.0.1" 2>/dev/null; then
            print_status "✓ Network configured successfully at 10.13.0.1"
        elif echo "$diagnosis_text" | grep -q "No IP configured.*driver.*compatibility" 2>/dev/null; then
            print_warning "⚠️  Network failed: LibreMesh image missing QEMU network drivers (e1000/virtio_net)"
            print_warning "   → This hardware-specific build can't create eth0/eth1 interfaces in QEMU"
            print_warning "   → Solution: Use console access via 'sudo screen -r libremesh'"
        elif echo "$diagnosis_text" | grep -q "e1000 not available\|virtio_net not available" 2>/dev/null; then
            print_warning "⚠️  Network failed: QEMU drivers (e1000, virtio_net) not available in this build"
            print_warning "   → This LibreMesh image was compiled for real hardware, not virtualization"
            print_warning "   → Use console: 'sudo screen -r libremesh' (root/admin)"
        else
            # Extract the actual error from diagnosis
            local actual_error=$(echo "$diagnosis_text" | grep -o "No.*configured.*" | head -1)
            if [ -n "$actual_error" ]; then
                print_warning "⚠️  Network configuration failed: $actual_error"
            else
                print_warning "⚠️  Network configuration incomplete - unknown issue detected"
            fi
            print_warning "   → Console access: 'sudo screen -r libremesh' (root/admin)"
        fi
    else
        print_warning "⚠️  Network configuration status unknown - diagnosis file not available"
        print_warning "   → Console access: 'sudo screen -r libremesh' (root/admin)"
    fi
}

# Find and kill QEMU processes
kill_qemu_processes() {
    print_status "Stopping existing QEMU processes..."
    
    # Kill screen session first if it exists
    if sudo screen -list | grep -q "libremesh"; then
        print_status "Stopping screen session 'libremesh'"
        sudo screen -S libremesh -X quit 2>/dev/null || true
        sleep 2
    fi
    
    # Find and kill any remaining QEMU processes
    QEMU_PIDS=$(pgrep -f "qemu-system-x86_64" || true)
    
    if [ -z "$QEMU_PIDS" ]; then
        print_status "No QEMU processes found"
    else
        for pid in $QEMU_PIDS; do
            print_status "Stopping QEMU process $pid"
            sudo kill -TERM "$pid" 2>/dev/null || true
        done
        
        # Wait a moment for graceful shutdown
        sleep 3
        
        # Force kill if still running
        QEMU_PIDS=$(pgrep -f "qemu-system-x86_64" || true)
        if [ -n "$QEMU_PIDS" ]; then
            for pid in $QEMU_PIDS; do
                print_warning "Force killing QEMU process $pid"
                sudo kill -KILL "$pid" 2>/dev/null || true
            done
        fi
    fi
    
    # Clean up LibreMesh-specific network interfaces
    print_status "Cleaning up network interfaces..."
    
    # Clean up lime bridge and TAP interfaces for node 00 (default)
    for ifc in lime_br0 lime_tap00_0 lime_tap00_1 lime_tap00_2; do
        if ip link show "$ifc" >/dev/null 2>&1; then
            print_status "Removing interface $ifc"
            sudo ip link delete "$ifc" 2>/dev/null || true
        fi
    done
    
    # Clean up any remaining lime_tap* interfaces
    for ifc in $(ip link show | grep -o 'lime_tap[^:]*' || true); do
        if [ -n "$ifc" ]; then
            print_status "Removing remaining interface $ifc"
            sudo ip link delete "$ifc" 2>/dev/null || true
        fi
    done
    
    # Clean up temporary files (with sudo if needed)
    sudo rm -f /tmp/lime_rootfs_*.cpio /tmp/qemu-libremesh.log 2>/dev/null || true
    
    print_status "QEMU processes and network cleanup completed"
}

# Check prerequisites
check_prerequisites() {
    if [ ! -d "$LIME_PACKAGES_DIR" ]; then
        print_error "lime-packages directory not found at $LIME_PACKAGES_DIR"
        exit 1
    fi
    
    # Detect available images
    detect_build_images
    
    # Validate that we have a compatible rootfs (must be tar.gz, not squashfs img.gz)
    if [[ "$ROOTFS_PATH" == *.img.gz ]]; then
        print_error "Detected squashfs image format: $(basename "$ROOTFS_PATH")"
        print_error "QEMU development requires tar.gz format rootfs, not squashfs img.gz"
        print_error "Please use LibreMesh 2020.4 images or convert the image format"
        # Try fallback to 2020.4 if it exists
        FALLBACK_ROOTFS="$LIME_PACKAGES_DIR/build/libremesh-2020.4-ow19-x86-64-rootfs.tar.gz"
        FALLBACK_KERNEL="$LIME_PACKAGES_DIR/build/libremesh-2020.4-ow19-x86-64-ramfs.bzImage"
        if [ -f "$FALLBACK_ROOTFS" ] && [ -f "$FALLBACK_KERNEL" ]; then
            print_status "Falling back to LibreMesh 2020.4 compatible images"
            ROOTFS_PATH="$FALLBACK_ROOTFS"
            KERNEL_PATH="$FALLBACK_KERNEL"
        else
            print_error "No compatible tar.gz rootfs images found"
            exit 1
        fi
    fi
    
    if [ ! -f "$ROOTFS_PATH" ]; then
        print_error "Rootfs not found at $ROOTFS_PATH"
        print_error "Available images in unified build directory:"
        ls -la "$BIN_DIR/" 2>/dev/null | grep -E "\.(img\.gz|tar\.gz)$" || echo "No images found in $BIN_DIR"
        print_error "Available images in lime-packages build directory:"
        ls -la "$LIME_PACKAGES_DIR/build/" 2>/dev/null | grep -E "\.(img\.gz|tar\.gz)$" || echo "No images found"
        exit 1
    fi
    
    if [ ! -f "$KERNEL_PATH" ]; then
        print_error "Kernel not found at $KERNEL_PATH"
        print_error "Available kernels in unified build directory:"
        ls -la "$BIN_DIR/" 2>/dev/null | grep -E "\.(bin|bzImage)$" || echo "No kernels found in $BIN_DIR"
        print_error "Available kernels in lime-packages build directory:"
        ls -la "$LIME_PACKAGES_DIR/build/" 2>/dev/null | grep -E "\.(bin|bzImage)$" || echo "No kernels found"
        exit 1
    fi
    
    # Test if rootfs can be extracted with tar
    if ! tar -tf "$ROOTFS_PATH" >/dev/null 2>&1; then
        print_error "Rootfs file $ROOTFS_PATH is not a valid tar archive"
        print_error "QEMU development requires extractable tar.gz format"
        exit 1
    fi
    
    print_status "✓ Prerequisites check passed"
}

# Start QEMU
start_qemu() {
    print_status "Starting QEMU LibreMesh..."
    
    # Check for existing QEMU processes first
    check_existing_qemu
    
    check_prerequisites
    
    if check_qemu_running; then
        print_warning "QEMU already running at $QEMU_IP"
        return 0
    fi
    
    cd "$LIME_PACKAGES_DIR"
    
    # Start QEMU in a screen session for proper console interaction
    print_status "Starting QEMU in screen session 'libremesh'..."
    print_status "Using rootfs: $(basename "$ROOTFS_PATH")"
    print_status "Using kernel: $(basename "$KERNEL_PATH")"
    
    sudo screen -dmS libremesh ./tools/qemu_dev_start \
        --libremesh-workdir . \
        "$ROOTFS_PATH" \
        "$KERNEL_PATH"
    
    print_status "QEMU starting in screen session..."
    print_status "Use 'sudo screen -r libremesh' to access console"
    
    # Wait for QEMU to be ready and auto-configure network
    print_status "Waiting for QEMU to boot..."
    for i in {1..8}; do
        if pgrep -f "qemu-system-x86_64" >/dev/null 2>&1; then
            break
        fi
        sleep 2
        echo -n "."
    done
    
    if ! pgrep -f "qemu-system-x86_64" >/dev/null 2>&1; then
        echo
        print_error "QEMU process failed to start"
        return 1
    fi
    
    # Auto-configure LibreMesh network
    print_status "Auto-configuring LibreMesh network..."
    setup_libremesh_network
    
    # Verify it's working
    if check_qemu_running; then
        print_status "✓ QEMU LibreMesh ready at http://$QEMU_IP"
        print_status "✓ lime-app available at http://$QEMU_IP/app"
        print_status "✓ Default credentials: root/admin"
        print_status "✓ Console accessible via: sudo screen -r libremesh"
        return 0
    else
        print_warning "LibreMesh started but network not fully ready"
        print_status "✓ Default credentials: root/admin"
        print_status "✓ Console accessible via: sudo screen -r libremesh"
        return 0
    fi
    
    echo
    print_error "QEMU failed to start or become ready"
    print_error "Check logs: cat /tmp/qemu-libremesh.log"
    return 1
}

# Stop QEMU
stop_qemu() {
    print_status "Stopping QEMU LibreMesh..."
    kill_qemu_processes
}

# Restart QEMU
restart_qemu() {
    print_status "Restarting QEMU LibreMesh..."
    stop_qemu
    sleep 2
    start_qemu
}

# Show QEMU status
show_status() {
    print_status "QEMU LibreMesh Status:"
    
    if check_qemu_running; then
        print_status "✓ QEMU is running at $QEMU_IP"
        print_status "✓ Default credentials: root/admin"
        
        # Test ubus connectivity
        if curl -s --max-time 3 "http://$QEMU_IP/ubus" >/dev/null 2>&1; then
            print_status "✓ ubus service accessible"
        else
            print_warning "✗ ubus service not accessible"
        fi
        
        # Test lime-app
        if curl -s --max-time 3 "http://$QEMU_IP/app/" | grep -q "lime-app\|html\|Index"; then
            print_status "✓ lime-app accessible at http://$QEMU_IP/app/"
        else
            print_warning "✗ lime-app not found at http://$QEMU_IP/app/"
            print_warning "  Run: npm run deploy:qemu to deploy lime-app"
        fi
        
        # Test authentication with default credentials
        auth_test=$(curl -s --max-time 3 "http://$QEMU_IP/ubus" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"admin"}]}' \
            2>/dev/null || echo '{"error":"failed"}')
        
        if echo "$auth_test" | grep -q '"result":\s*\[0'; then
            print_status "✓ Authentication working with default credentials"
        else
            print_warning "✗ Authentication may need configuration"
        fi
    else
        print_warning "✗ QEMU is not running"
        print_status "  Run: npm run qemu:start to start QEMU"
    fi
}

# Deploy lime-app using official LibreMesh method
deploy_to_qemu() {
    print_status "Deploying lime-app using official LibreMesh method..."
    
    # Build lime-app first
    print_status "Building lime-app..."
    npm run build:production
    
    # Deploy to lime-packages (official LibreMesh method)
    print_status "Deploying to lime-packages structure..."
    mkdir -p "$LIME_APP_FILES_DIR"
    cp -r build/* "$LIME_APP_FILES_DIR/"
    print_status "✓ Files copied to lime-packages/packages/lime-app/files/www/app/"
    
    # Check if QEMU is running to determine deployment strategy
    if check_qemu_running; then
        print_status "QEMU is running - attempting live deployment..."
        
        # Try direct SCP as quick method (fallback approach)
        if scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
            -r build/* root@"$QEMU_IP":/www/app/ 2>/dev/null; then
            print_status "✓ Live deployment successful"
            print_status "✓ lime-app available at http://$QEMU_IP/app/"
        else
            print_warning "Live deployment failed, restarting QEMU to pick up changes..."
            print_status "This will ensure lime-packages overlay is properly applied..."
            restart_qemu
        fi
    else
        print_status "QEMU is not running"
        print_status "Files deployed to lime-packages structure"
        print_status "Start QEMU with: npm run qemu:start"
        print_status "The lime-app will be available via workdir overlay"
    fi
    
    print_status "✓ Deployment completed using official LibreMesh method"
}

# Main script logic
case "${1:-help}" in
    start)
        start_qemu
        ;;
    stop)
        stop_qemu
        ;;
    restart)
        restart_qemu
        ;;
    status)
        show_status
        ;;
    deploy)
        deploy_to_qemu
        ;;
    help|--help|-h)
        echo "Usage: $0 {start|stop|restart|status|deploy}"
        echo ""
        echo "Commands:"
        echo "  start    - Start QEMU LibreMesh"
        echo "  stop     - Stop QEMU LibreMesh"
        echo "  restart  - Restart QEMU LibreMesh"
        echo "  status   - Show QEMU and lime-app status"
        echo "  deploy   - Build and deploy lime-app using official LibreMesh method"
        echo "  help     - Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 start     # Start QEMU"
        echo "  $0 deploy    # Deploy lime-app using official LibreMesh method"
        echo "  $0 status    # Check status"
        echo "  $0 restart   # Restart QEMU"
        ;;
    *)
        print_error "Unknown command: $1"
        print_error "Use '$0 help' for usage information"
        exit 1
        ;;
esac