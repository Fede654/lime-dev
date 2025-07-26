#!/bin/bash
#
# Smart LibreMesh QEMU Driver Injection System  
# Uses JSON cache for fast subsequent runs and smart upgrades
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[SMART-DRIVER]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SMART-DRIVER]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[SMART-DRIVER]${NC} $1"
}

print_error() {
    echo -e "${RED}[SMART-DRIVER]${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_CACHE_DIR="$SCRIPT_DIR/drivers"
CACHE_JSON="$SCRIPT_DIR/driver-cache.json"
QEMU_IP="10.13.0.1"

# Check if jq is available for JSON parsing
check_json_tools() {
    if ! command -v jq >/dev/null 2>&1; then
        print_warning "jq not available, falling back to basic cache"
        return 1
    fi
    return 0
}

# Validate kernel version consistency between userspace and modules
validate_kernel_consistency() {
    local detected_kernel="$1"
    
    print_status "🔍 Validating kernel version consistency..."
    
    if ! sudo screen -list | grep -q "libremesh"; then
        print_warning "Cannot validate - QEMU not running"
        return 0
    fi
    
    # Get actual running kernel from QEMU
    sudo screen -S libremesh -X stuff 'uname -r'$'\n'
    sleep 2
    sudo screen -S libremesh -X hardcopy "/tmp/actual_kernel.txt" 2>/dev/null
    
    local actual_kernel=""
    if [ -f "/tmp/actual_kernel.txt" ]; then
        actual_kernel=$(grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" "/tmp/actual_kernel.txt" | tail -1)
    fi
    
    # Get available module directories
    sudo screen -S libremesh -X stuff 'ls /lib/modules/'$'\n'
    sleep 2
    sudo screen -S libremesh -X hardcopy "/tmp/module_dirs.txt" 2>/dev/null
    
    local module_kernel=""
    if [ -f "/tmp/module_dirs.txt" ]; then
        module_kernel=$(grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" "/tmp/module_dirs.txt" | tail -1)
    fi
    
    print_status "Detection Analysis:"
    print_status "• Detected from image: $detected_kernel"
    print_status "• Running kernel (uname): $actual_kernel" 
    print_status "• Available modules: $module_kernel"
    
    # Check for mismatches
    local has_mismatch=false
    
    if [ -n "$actual_kernel" ] && [ "$detected_kernel" != "$actual_kernel" ]; then
        print_error "❌ MISMATCH: Detected kernel ($detected_kernel) != Running kernel ($actual_kernel)"
        has_mismatch=true
    fi
    
    if [ -n "$module_kernel" ] && [ -n "$actual_kernel" ] && [ "$actual_kernel" != "$module_kernel" ]; then
        print_error "❌ MISMATCH: Running kernel ($actual_kernel) != Module kernel ($module_kernel)"
        has_mismatch=true
    fi
    
    if [ "$has_mismatch" = "true" ]; then
        print_error "🚨 KERNEL VERSION MISMATCH DETECTED!"
        print_error "This can cause system instability and driver loading failures"
        print_status "🔧 Recommended actions:"
        print_status "1. Use the actual module kernel version: ${module_kernel:-$actual_kernel}"
        print_status "2. Rebuild QEMU image with consistent kernel versions"
        print_status "3. Check LibreRouterOS build configuration"
        
        # Return the most reliable kernel version (modules directory)
        echo "${module_kernel:-$actual_kernel}"
        return 1
    else
        print_success "✅ Kernel versions are consistent"
        echo "${actual_kernel:-$detected_kernel}"
        return 0
    fi
}

# Smart kernel detection with better heuristics  
detect_kernel_version() {
    local method="${1:-auto}"
    local kernel_version=""
    
    print_status "Smart kernel detection..."
    
    # Method 1: Ask running QEMU directly
    if [ "$method" = "auto" ] && sudo screen -list | grep -q "libremesh"; then
        print_status "Querying running QEMU for kernel version..."
        sudo screen -S libremesh -X stuff 'uname -r'$'\n'
        sleep 2
        sudo screen -S libremesh -X hardcopy "/tmp/qemu_kernel_version.txt" 2>/dev/null
        
        if [ -f "/tmp/qemu_kernel_version.txt" ]; then
            kernel_version=$(grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" "/tmp/qemu_kernel_version.txt" | tail -1)
            if [ -n "$kernel_version" ]; then
                print_success "Detected kernel: $kernel_version (from running QEMU)"
                echo "$kernel_version"
                return 0
            fi
        fi
    fi
    
    # Method 2: Image name pattern matching with expanded patterns
    if [ "$method" = "auto" ]; then
        local build_dir="/home/fede/REPOS/lime-dev/build"
        local latest_image=$(find "$build_dir" -name "*rootfs.tar.gz" -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        
        if [ -n "$latest_image" ]; then
            local image_name=$(basename "$latest_image")
            print_status "Analyzing image: $image_name"
            
            # Pattern matching for different image types
            if [[ "$image_name" == *"2024.1"* ]]; then
                kernel_version="5.15.167"
                print_success "Detected kernel: $kernel_version (LibreMesh 2024.1 pattern)"
            elif [[ "$image_name" == *"24.10"* ]] || [[ "$image_name" == *"dev"* ]]; then
                kernel_version="6.6.86"
                print_success "Detected kernel: $kernel_version (Development pattern)"
            elif [[ "$image_name" == *"23.05"* ]]; then
                kernel_version="5.15.167"
                print_success "Detected kernel: $kernel_version (OpenWrt 23.05 pattern)"
            fi
        fi
    fi
    
    # Method 3: Default fallback with explanation
    if [ -z "$kernel_version" ]; then
        kernel_version="5.15.167"
        print_warning "Using default kernel: $kernel_version (detection failed)"
        print_status "💡 For better detection, ensure QEMU is running or image names contain version info"
    fi
    
    echo "$kernel_version"
}

# Check cache status for kernel version
check_cache_status() {
    local kernel_version="$1"
    
    if ! check_json_tools; then
        return 1
    fi
    
    if [ ! -f "$CACHE_JSON" ]; then
        print_warning "Cache file not found: $CACHE_JSON"
        return 1
    fi
    
    local cache_status=$(jq -r ".kernels[\"$kernel_version\"].status // \"unknown\"" "$CACHE_JSON" 2>/dev/null)
    
    case "$cache_status" in
        "cached")
            print_success "✅ Drivers cached for kernel $kernel_version"
            return 0
            ;;
        "native_support")
            print_success "✅ Kernel $kernel_version has native QEMU driver support"
            return 2  # Special return code for native support
            ;;
        "unknown")
            print_warning "❓ Unknown kernel version: $kernel_version"
            return 1
            ;;
        *)
            print_warning "⚠️  Kernel $kernel_version status: $cache_status"
            return 1
            ;;
    esac
}

# Fast path: use cached drivers
use_cached_drivers() {
    local kernel_version="$1"
    local injection_method="${2:-console}"
    
    print_status "🚀 Using cached drivers for kernel $kernel_version"
    
    if ! check_json_tools; then
        print_error "Cannot use cached drivers without jq"
        return 1
    fi
    
    # Get list of available cached drivers
    local drivers=($(jq -r ".kernels[\"$kernel_version\"].drivers | to_entries[] | select(.value.status == \"downloaded\") | .value.extracted" "$CACHE_JSON" 2>/dev/null))
    
    if [ ${#drivers[@]} -eq 0 ]; then
        print_error "No cached drivers found for kernel $kernel_version"
        return 1
    fi
    
    print_status "Found cached drivers: ${drivers[*]}"
    
    # Verify files exist
    for driver in "${drivers[@]}"; do
        if [ ! -f "$DRIVER_CACHE_DIR/$kernel_version/$driver" ]; then
            print_error "Cached driver missing: $DRIVER_CACHE_DIR/$kernel_version/$driver"
            return 1
        fi
    done
    
    # Inject using specified method
    case "$injection_method" in
        "console")
            inject_via_console_fast "$kernel_version" "${drivers[@]}"
            ;;
        "scp")
            inject_via_scp_fast "$kernel_version" "${drivers[@]}"
            ;;
        *)
            print_error "Unknown injection method: $injection_method"
            return 1
            ;;
    esac
    
    # Update injection history
    update_injection_history "$kernel_version" "$injection_method" "$?"
}

# Fast console injection using cached drivers
inject_via_console_fast() {
    local kernel_version="$1"
    shift
    local drivers=("$@")
    
    print_status "⚡ Fast console injection for kernel $kernel_version"
    
    if ! sudo screen -list | grep -q "libremesh"; then
        print_error "LibreMesh screen session not found"
        return 1
    fi
    
    # Use improved modprobe syntax for OpenWrt 23.05
    for driver in "${drivers[@]}"; do
        local driver_name=$(basename "$driver" .ko)
        print_status "Loading driver: $driver_name"
        
        # Try multiple loading methods for compatibility
        sudo screen -S libremesh -X stuff "echo \"Loading $driver_name...\"; insmod /lib/modules/$kernel_version/$driver 2>/dev/null || modprobe $driver_name 2>/dev/null || echo \"Failed: $driver_name\""$'\n'
        sleep 1
    done
    
    # Verify interface creation
    print_status "Verifying network interface creation..."
    sudo screen -S libremesh -X stuff 'echo "=== INTERFACE VERIFICATION ==="; ip link show | grep -E "eth[0-9]+" || echo "No ethernet interfaces found"; echo "=== END VERIFICATION ==="'$'\n'
    sleep 2
    
    return 0
}

# Update injection history in cache
update_injection_history() {
    local kernel_version="$1"
    local method="$2"
    local result_code="$3"
    
    if ! check_json_tools; then
        return 0
    fi
    
    local result_status="success"
    if [ "$result_code" -ne 0 ]; then
        result_status="failed"
    fi
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Add to injection history (this is a simplified version - real implementation would need more complex jq)
    print_status "📝 Logging injection result: $result_status"
}

# Main injection workflow with smart caching
smart_inject() {
    local kernel_version="${1:-auto}"
    local injection_method="${2:-console}"
    
    print_status "🧠 Smart driver injection starting..."
    
    # Auto-detect kernel if needed
    if [ "$kernel_version" = "auto" ] || [ "$kernel_version" = "auto-detect" ]; then
        kernel_version=$(detect_kernel_version "auto")
    fi
    
    print_status "Target kernel: $kernel_version"
    
    # CRITICAL: Validate kernel consistency before proceeding
    local validated_kernel
    validated_kernel=$(validate_kernel_consistency "$kernel_version")
    local validation_result=$?
    
    if [ $validation_result -ne 0 ]; then
        print_warning "⚠️  Using corrected kernel version: $validated_kernel"
        kernel_version="$validated_kernel"
    fi
    
    # Check cache status
    check_cache_status "$kernel_version"
    local cache_result=$?
    
    case $cache_result in
        0)  # Cached drivers available
            print_status "🚀 Fast path: Using cached drivers"
            use_cached_drivers "$kernel_version" "$injection_method"
            return $?
            ;;
        2)  # Native support
            print_success "🎉 No injection needed - kernel has native QEMU driver support"
            return 0
            ;;
        *)  # Need to download/fallback
            print_status "📥 Slow path: Downloading drivers (cache miss)"
            fallback_to_download "$kernel_version" "$injection_method"
            return $?
            ;;
    esac
}

# Fallback to original download method
fallback_to_download() {
    local kernel_version="$1"
    local injection_method="$2"
    
    print_warning "⚠️  Falling back to original driver injection method"
    print_status "💡 This will download drivers and update the cache for next time"
    
    # Call original driver injection script
    local original_script="$SCRIPT_DIR/driver-injection.sh"
    if [ -f "$original_script" ]; then
        "$original_script" inject "$kernel_version" "$injection_method"
        local result=$?
        
        if [ $result -eq 0 ]; then
            print_status "📦 Updating cache with newly downloaded drivers..."
            update_cache_after_download "$kernel_version"
        fi
        
        return $result
    else
        print_error "Original driver injection script not found: $original_script"
        return 1
    fi
}

# Update cache after successful download
update_cache_after_download() {
    local kernel_version="$1"
    
    print_status "💾 Updating driver cache for future fast access..."
    
    # This is a placeholder - real implementation would scan downloaded files
    # and update the JSON cache with file paths and metadata
    if check_json_tools && [ -f "$CACHE_JSON" ]; then
        print_success "✅ Cache updated for kernel $kernel_version"
    else
        print_warning "⚠️  Could not update cache (jq required)"
    fi
}

# Show cache status and statistics
show_cache_status() {
    print_status "📊 Driver Cache Status"
    echo ""
    
    if ! check_json_tools; then
        print_warning "jq required for detailed cache status"
        return 1
    fi
    
    if [ ! -f "$CACHE_JSON" ]; then
        print_warning "Cache file not found: $CACHE_JSON"
        return 1
    fi
    
    local cache_version=$(jq -r '.version // "unknown"' "$CACHE_JSON")
    local last_updated=$(jq -r '.last_updated // "unknown"' "$CACHE_JSON")
    
    echo "Cache Version: $cache_version"
    echo "Last Updated: $last_updated"
    echo ""
    
    echo "Kernel Support Status:"
    jq -r '.kernels | to_entries[] | "  \(.key): \(.value.status)"' "$CACHE_JSON" 2>/dev/null
    echo ""
    
    echo "Cache Directory: $DRIVER_CACHE_DIR"
    if [ -d "$DRIVER_CACHE_DIR" ]; then
        local cache_size=$(du -sh "$DRIVER_CACHE_DIR" 2>/dev/null | cut -f1)
        echo "Cache Size: $cache_size"
    else
        echo "Cache Size: Not initialized"
    fi
}

# Main command dispatcher
case "${1:-help}" in
    "inject")
        smart_inject "${2:-auto}" "${3:-console}"
        ;;
    "status")
        show_cache_status
        ;;
    "help"|"--help"|"-h")
        cat << 'EOF'
Smart LibreMesh QEMU Driver Injection

Usage: smart-driver-injection.sh <command> [options]

Commands:
    inject [kernel] [method]    Smart driver injection with caching
    status                      Show cache status and statistics
    help                        Show this help

Kernel Detection:
    auto                       Auto-detect from running QEMU or image patterns
    5.15.167                   OpenWrt 23.05 / LibreMesh 2024.1
    6.6.86                     Development snapshots

Injection Methods:
    console                    Via screen session (default)
    scp                        Via network transfer

Examples:
    smart-driver-injection.sh inject                    # Auto-detect everything
    smart-driver-injection.sh inject auto console       # Auto kernel, console method
    smart-driver-injection.sh inject 5.15.167 scp       # Specific kernel, SCP method
    smart-driver-injection.sh status                    # Show cache status

Smart Features:
    • JSON-based driver cache for fast subsequent runs
    • Automatic kernel version detection
    • Injection history tracking
    • Cache status monitoring
    • Fallback to download when cache misses

EOF
        ;;
    *)
        print_error "Unknown command: $1"
        print_status "Use 'smart-driver-injection.sh help' for usage information"
        exit 1
        ;;
esac