#!/usr/bin/env bash
#
# Smart Network Setup for QEMU LibreMesh
# Uses direct system introspection instead of guessing
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[NET]${NC} $1"; }
print_success() { echo -e "${GREEN}[NET]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[NET]${NC} $1"; }
print_error() { echo -e "${RED}[NET]${NC} $1"; }

QEMU_IP="10.13.0.1"
SCREEN_NAME="libremesh"
TIMEOUT=30

# Send command and capture output
send_console_command() {
    local cmd="$1"
    local wait_time="${2:-2}"
    local output_file="/tmp/smart_net_output.log"
    
    # Send command
    sudo screen -S "$SCREEN_NAME" -X stuff "$cmd"$'\n' 2>/dev/null || return 1
    sleep "$wait_time"
    
    # Capture output
    sudo screen -S "$SCREEN_NAME" -X hardcopy "$output_file" 2>/dev/null || return 1
    
    # Return last few lines (filter out prompt noise)
    tail -20 "$output_file" | grep -v "Please press Enter" | head -10
}

# Get real system information
get_system_info() {
    print_status "Getting real system information..."
    
    local info_output
    info_output=$(send_console_command "uname -r && echo '---' && lsmod | head -5 && echo '---' && ip link show | grep -E '^[0-9]+:'" 3)
    
    if [[ -n "$info_output" ]]; then
        local kernel_version
        kernel_version=$(echo "$info_output" | head -1 | grep -E '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        
        local interfaces
        interfaces=$(echo "$info_output" | grep -E '^[0-9]+:' | wc -l || echo "0")
        
        print_success "Real kernel: $kernel_version"
        print_status "Available interfaces: $interfaces"
        
        echo "$kernel_version"
        return 0
    else
        print_error "Could not get system information"
        return 1
    fi
}

# Check what network drivers are already available
check_existing_drivers() {
    print_status "Checking existing network drivers..."
    
    local driver_output
    driver_output=$(send_console_command "find /lib/modules -name '*e1000*' -o -name '*8139*' -o -name '*virtio*' | head -5" 3)
    
    if echo "$driver_output" | grep -q "\.ko"; then
        print_success "Network drivers found in system:"
        echo "$driver_output" | grep "\.ko" | while read -r driver; do
            local driver_name=$(basename "$driver" .ko)
            print_status "  Available: $driver_name"
        done
        return 0
    else
        print_warning "No network drivers found in /lib/modules"
        return 1
    fi
}

# Try to load available drivers intelligently
load_smart_drivers() {
    print_status "Attempting to load network drivers..."
    
    # Try common QEMU network drivers
    local drivers=("e1000" "e1000e" "8139too" "8139cp" "virtio_net")
    local loaded_count=0
    
    for driver in "${drivers[@]}"; do
        print_status "Testing driver: $driver"
        local result
        result=$(send_console_command "modprobe $driver 2>&1 && echo 'OK' || echo 'FAIL'" 2)
        
        if echo "$result" | grep -q "OK"; then
            print_success "  Loaded: $driver"
            ((loaded_count++))
        else
            print_warning "  Failed: $driver"
        fi
    done
    
    if [[ $loaded_count -gt 0 ]]; then
        print_success "Loaded $loaded_count network drivers"
        return 0
    else
        print_error "No network drivers could be loaded"
        return 1
    fi
}

# Check interface availability after driver loading
check_interfaces() {
    print_status "Checking available network interfaces..."
    
    local interface_output
    interface_output=$(send_console_command "ip link show | grep -E '^[0-9]+: (eth|ens|enp)'" 2)
    
    if [[ -n "$interface_output" ]]; then
        print_success "Network interfaces found:"
        echo "$interface_output" | while read -r line; do
            local iface=$(echo "$line" | cut -d: -f2 | tr -d ' ')
            print_status "  Interface: $iface"
        done
        return 0
    else
        print_warning "No ethernet interfaces found"
        
        # Check for any interfaces at all
        local all_interfaces
        all_interfaces=$(send_console_command "ip link show | grep -E '^[0-9]+:' | grep -v lo" 2)
        if [[ -n "$all_interfaces" ]]; then
            print_status "Other interfaces available:"
            echo "$all_interfaces" | head -3
        fi
        return 1
    fi
}

# Configure network intelligently
configure_network() {
    print_status "Configuring network with IP $QEMU_IP..."
    
    # Try to configure any available interface
    local config_result
    config_result=$(send_console_command "
        for iface in \$(ip link show | grep -oE '^[0-9]+: [^:]+' | cut -d' ' -f2 | grep -E '(eth|ens|enp)'); do
            echo \"Trying \$iface...\"
            if ip addr add $QEMU_IP/16 dev \$iface 2>/dev/null && ip link set \$iface up 2>/dev/null; then
                echo \"SUCCESS: \$iface configured\"
                break
            fi
        done
        ping -c 1 10.13.0.2 2>/dev/null && echo 'PING_OK' || echo 'PING_FAIL'
    " 5)
    
    if echo "$config_result" | grep -q "SUCCESS"; then
        local configured_iface
        configured_iface=$(echo "$config_result" | grep "SUCCESS" | cut -d: -f2 | cut -d' ' -f2)
        print_success "Network configured on interface: $configured_iface"
        
        if echo "$config_result" | grep -q "PING_OK"; then
            print_success "Host connectivity verified"
            return 0
        else
            print_warning "Interface configured but host unreachable"
            return 1
        fi
    else
        print_error "Failed to configure any network interface"
        return 1
    fi
}

# Test final connectivity
test_connectivity() {
    print_status "Testing connectivity from host..."
    
    if ping -c 2 -W 3 "$QEMU_IP" >/dev/null 2>&1; then
        print_success "✅ Network fully operational - $QEMU_IP reachable"
        return 0
    else
        print_warning "⚠️  Network partially configured - host cannot reach VM"
        return 1
    fi
}

# Main execution
main() {
    print_status "🧠 Starting intelligent network setup..."
    
    # Step 1: Get real system information
    local kernel_version
    if ! kernel_version=$(get_system_info); then
        print_error "Cannot access system - check screen session"
        return 1
    fi
    
    # Step 2: Check existing drivers
    local drivers_available=false
    if check_existing_drivers; then
        drivers_available=true
    fi
    
    # Step 3: Load drivers
    if load_smart_drivers; then
        print_success "Driver loading completed"
    else
        if [[ "$drivers_available" == "false" ]]; then
            print_warning "This image may not include QEMU-compatible network drivers"
        fi
    fi
    
    # Step 4: Check for interfaces
    if check_interfaces; then
        print_success "Network interfaces detected"
    else
        print_error "No usable network interfaces found"
        print_status "ℹ️  This image may be hardware-specific"
        return 1
    fi
    
    # Step 5: Configure network
    if configure_network; then
        print_success "Network configuration completed"
    else
        print_error "Network configuration failed"
        return 1
    fi
    
    # Step 6: Test connectivity
    if test_connectivity; then
        print_success "🎉 Smart network setup completed successfully!"
        return 0
    else
        print_warning "⚠️  Setup partially successful - check configuration"
        return 1
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi