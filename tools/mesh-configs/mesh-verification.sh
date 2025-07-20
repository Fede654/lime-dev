#!/bin/bash
#
# LibreMesh Mesh Network Deployment Verification Script
# Verifies mesh configuration deployment and network behavior
#
# For detailed IP allocation analysis, see:
# docs/libremesh/IP-ALLOCATION.md
#

set -e

ROUTER_IPS="${@:-thisnode.info}"
ROUTER_PASSWORD="${ROUTER_PASSWORD:-toorlibre1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[VERIFY]${NC} $1"; }
print_success() { echo -e "${GREEN}[VERIFY]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[VERIFY]${NC} $1"; }
print_error() { echo -e "${RED}[VERIFY]${NC} $1"; }
print_header() { echo -e "${CYAN}=== $1 ===${NC}"; }

# SSH options for LibreMesh routers
SSH_OPTS="-oHostKeyAlgorithms=+ssh-rsa -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oPasswordAuthentication=yes -oPubkeyAuthentication=no"

ssh_cmd() {
    local router_ip="$1"
    shift
    sshpass -p "$ROUTER_PASSWORD" ssh $SSH_OPTS root@"$router_ip" "$@" 2>/dev/null
}

get_node_info() {
    local router_ip="$1"
    
    if ! ssh_cmd "$router_ip" "echo 'ok'" >/dev/null; then
        echo "OFFLINE|unknown|unknown|unknown"
        return 1
    fi
    
    local hostname=$(ssh_cmd "$router_ip" "uci get system.@system[0].hostname" || echo "unknown")
    local mac=$(ssh_cmd "$router_ip" "cat /sys/class/net/eth0/address" || echo "unknown")
    local node_ip=$(ssh_cmd "$router_ip" "ip addr show br-lan | grep 'inet ' | awk '{print \$2}' | cut -d'/' -f1" || echo "unknown")
    
    echo "ONLINE|$hostname|$mac|$node_ip"
}

verify_ip_allocation() {
    print_header "IP Allocation Analysis"
    
    echo
    printf "%-15s %-20s %-17s %-15s %-10s\n" "Router IP" "Hostname" "MAC Address" "Node IP" "Status"
    printf "%-15s %-20s %-17s %-15s %-10s\n" "----------" "--------" "-----------" "-------" "------"
    
    local total_nodes=0
    local online_nodes=0
    local ip_conflicts=()
    local node_ips=()
    
    for router_ip in $ROUTER_IPS; do
        total_nodes=$((total_nodes + 1))
        
        IFS='|' read -r status hostname mac node_ip <<< "$(get_node_info "$router_ip")"
        
        if [[ "$status" == "ONLINE" ]]; then
            online_nodes=$((online_nodes + 1))
            
            # Check for IP conflicts
            for existing_ip in "${node_ips[@]}"; do
                if [[ "$node_ip" == "$existing_ip" ]]; then
                    ip_conflicts+=("$node_ip")
                fi
            done
            node_ips+=("$node_ip")
            
            # Calculate expected IP from MAC
            if [[ "$mac" != "unknown" ]]; then
                local mac5=$(echo "$mac" | cut -d':' -f5)
                local mac6=$(echo "$mac" | cut -d':' -f6)
                local expected_ip="10.13.$((0x$mac5)).$((0x$mac6))"
                
                if [[ "$node_ip" == "$expected_ip" ]]; then
                    status="✓ OK"
                else
                    status="⚠ MISMATCH"
                fi
            fi
        fi
        
        printf "%-15s %-20s %-17s %-15s %-10s\n" "$router_ip" "$hostname" "$mac" "$node_ip" "$status"
    done
    
    echo
    print_info "Summary: $online_nodes/$total_nodes nodes online"
    
    if [[ ${#ip_conflicts[@]} -gt 0 ]]; then
        print_error "IP conflicts detected: ${ip_conflicts[*]}"
    else
        print_success "No IP conflicts detected"
    fi
}

verify_mesh_topology() {
    print_header "Mesh Topology Analysis"
    
    echo
    print_info "BATMAN-adv Mesh Topology:"
    
    for router_ip in $ROUTER_IPS; do
        if ssh_cmd "$router_ip" "echo 'ok'" >/dev/null; then
            local hostname=$(ssh_cmd "$router_ip" "uci get system.@system[0].hostname" || echo "unknown")
            
            echo
            print_info "Node: $hostname ($router_ip)"
            
            # BATMAN originators
            local originators=$(ssh_cmd "$router_ip" "batctl o 2>/dev/null | grep -v 'Originator' | wc -l" || echo "0")
            print_info "  BATMAN originators: $originators"
            
            # BATMAN neighbors
            local neighbors=$(ssh_cmd "$router_ip" "batctl n 2>/dev/null | grep -v 'Neighbor' | wc -l" || echo "0")
            print_info "  BATMAN neighbors: $neighbors"
            
            if [[ "$neighbors" -gt 0 ]]; then
                ssh_cmd "$router_ip" "batctl n 2>/dev/null | head -5" | while read line; do
                    if [[ "$line" != *"Neighbor"* ]] && [[ -n "$line" ]]; then
                        print_info "    $line"
                    fi
                done
            fi
        fi
    done
}

verify_routing_protocols() {
    print_header "Routing Protocols Status"
    
    for router_ip in $ROUTER_IPS; do
        if ssh_cmd "$router_ip" "echo 'ok'" >/dev/null; then
            local hostname=$(ssh_cmd "$router_ip" "uci get system.@system[0].hostname" || echo "unknown")
            
            echo
            print_info "Node: $hostname ($router_ip)"
            
            # Check BATMAN-adv
            if ssh_cmd "$router_ip" "batctl if >/dev/null 2>&1"; then
                local bat_if=$(ssh_cmd "$router_ip" "batctl if | wc -l")
                print_success "  ✓ BATMAN-adv: $bat_if interfaces"
            else
                print_error "  ✗ BATMAN-adv: Not running"
            fi
            
            # Check BMX6
            if ssh_cmd "$router_ip" "bmx6 -c show=status >/dev/null 2>&1"; then
                print_success "  ✓ BMX6: Running"
            else
                print_warning "  ⚠ BMX6: Not running or not installed"
            fi
            
            # Check BMX7
            if ssh_cmd "$router_ip" "bmx7 -c show=status >/dev/null 2>&1"; then
                print_success "  ✓ BMX7: Running"
            else
                print_warning "  ⚠ BMX7: Not running or not installed"
            fi
            
            # Check Babeld
            if ssh_cmd "$router_ip" "pgrep babeld >/dev/null 2>&1"; then
                print_success "  ✓ Babel: Running"
            else
                print_warning "  ⚠ Babel: Not running or not installed"
            fi
        fi
    done
}

verify_wifi_config() {
    print_header "WiFi Configuration"
    
    for router_ip in $ROUTER_IPS; do
        if ssh_cmd "$router_ip" "echo 'ok'" >/dev/null; then
            local hostname=$(ssh_cmd "$router_ip" "uci get system.@system[0].hostname" || echo "unknown")
            
            echo
            print_info "Node: $hostname ($router_ip)"
            
            # Check WiFi interfaces
            ssh_cmd "$router_ip" "iwinfo 2>/dev/null" | while read line; do
                if [[ "$line" == *"ESSID:"* ]]; then
                    local interface=$(echo "$line" | awk '{print $1}')
                    local essid=$(echo "$line" | grep -o 'ESSID: "[^"]*"' | cut -d'"' -f2)
                    
                    if [[ "$essid" == "TestMesh.org" ]]; then
                        print_success "  ✓ $interface: TestMesh.org (AP mode)"
                    elif [[ "$essid" == "TM-adhoc" ]]; then
                        print_success "  ✓ $interface: TM-adhoc (Mesh mode)"  
                    else
                        print_info "  • $interface: $essid"
                    fi
                fi
            done
        fi
    done
}

verify_dhcp_ranges() {
    print_header "DHCP Configuration"
    
    for router_ip in $ROUTER_IPS; do
        if ssh_cmd "$router_ip" "echo 'ok'" >/dev/null; then
            local hostname=$(ssh_cmd "$router_ip" "uci get system.@system[0].hostname" || echo "unknown")
            
            echo
            print_info "Node: $hostname ($router_ip)"
            
            # Check DHCP configuration
            local dhcp_start=$(ssh_cmd "$router_ip" "uci get dhcp.lan.start 2>/dev/null" || echo "unknown")
            local dhcp_limit=$(ssh_cmd "$router_ip" "uci get dhcp.lan.limit 2>/dev/null" || echo "unknown")
            
            if [[ "$dhcp_start" != "unknown" && "$dhcp_limit" != "unknown" ]]; then
                print_info "  DHCP range: .${dhcp_start} - .$((dhcp_start + dhcp_limit - 1))"
            fi
            
            # Check active DHCP leases
            local leases=$(ssh_cmd "$router_ip" "cat /tmp/dhcp.leases 2>/dev/null | wc -l" || echo "0")
            print_info "  Active DHCP leases: $leases"
            
            if [[ "$leases" -gt 0 ]]; then
                ssh_cmd "$router_ip" "cat /tmp/dhcp.leases 2>/dev/null | head -3" | while read lease; do
                    if [[ -n "$lease" ]]; then
                        local client_ip=$(echo "$lease" | awk '{print $3}')
                        local client_mac=$(echo "$lease" | awk '{print $2}')
                        print_info "    Client: $client_ip ($client_mac)"
                    fi
                done
            fi
        fi
    done
}

test_connectivity() {
    print_header "Connectivity Testing"
    
    local test_targets=("8.8.8.8" "1.1.1.1")
    
    for router_ip in $ROUTER_IPS; do
        if ssh_cmd "$router_ip" "echo 'ok'" >/dev/null; then
            local hostname=$(ssh_cmd "$router_ip" "uci get system.@system[0].hostname" || echo "unknown")
            
            echo
            print_info "Node: $hostname ($router_ip)"
            
            # Test internet connectivity
            for target in "${test_targets[@]}"; do
                if ssh_cmd "$router_ip" "ping -c 1 -W 3 $target >/dev/null 2>&1"; then
                    print_success "  ✓ Internet: $target reachable"
                    break
                else
                    print_warning "  ⚠ Internet: $target unreachable"
                fi
            done
            
            # Test inter-node connectivity
            for other_router in $ROUTER_IPS; do
                if [[ "$other_router" != "$router_ip" ]]; then
                    if ssh_cmd "$router_ip" "ping -c 1 -W 3 $other_router >/dev/null 2>&1"; then
                        print_success "  ✓ Mesh: $other_router reachable"
                    else
                        print_error "  ✗ Mesh: $other_router unreachable"
                    fi
                fi
            done
        fi
    done
}

generate_summary() {
    print_header "Deployment Summary"
    
    echo
    print_info "TestMesh Network Configuration:"
    print_info "• Network Range: 10.13.0.0/16"
    print_info "• WiFi SSID: TestMesh.org"
    print_info "• Mesh Network: TM-adhoc"
    print_info "• Protocols: BATMAN-adv, BMX6/BMX7, Babel"
    
    echo
    print_info "Expected Node IP Calculation:"
    print_info "• Node IP = 10.13.<MAC_byte_5>.<MAC_byte_6>"
    print_info "• DHCP Range: 10.13.200.2 - 10.13.200.199"
    print_info "• Gateway IPs: Automatically selected by protocols"
    
    echo
    print_info "Troubleshooting Commands:"
    print_info "• Check mesh: ssh root@<node> 'batctl o'"
    print_info "• Check WiFi: ssh root@<node> 'iwinfo'"
    print_info "• Check routes: ssh root@<node> 'ip route'"
    print_info "• Check DHCP: ssh root@<node> 'cat /tmp/dhcp.leases'"
    
    echo
    print_success "✅ Verification completed for TestMesh deployment"
}

main() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <router_ip_1> [router_ip_2] [router_ip_3] ..."
        echo "Example: $0 10.13.0.1 10.13.0.2 10.13.0.3"
        echo "Example: $0 thisnode.info"
        exit 1
    fi
    
    print_header "TestMesh Deployment Verification"
    print_info "Analyzing nodes: $ROUTER_IPS"
    
    echo
    verify_ip_allocation
    echo
    verify_mesh_topology  
    echo
    verify_routing_protocols
    echo
    verify_wifi_config
    echo
    verify_dhcp_ranges
    echo
    test_connectivity
    echo
    generate_summary
}

# Check dependencies
if ! command -v sshpass >/dev/null; then
    print_error "Missing dependency: sshpass"
    print_info "Install with: sudo apt install sshpass"
    exit 1
fi

main "$@"