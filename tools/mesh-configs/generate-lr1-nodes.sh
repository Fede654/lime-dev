#!/bin/bash
#
# LibreRouter v1 Node Configuration Generator
# Generates individual lime-node files for mesh deployment
#
# For LibreMesh IP allocation details, see:
# docs/libremesh/IP-ALLOCATION.md
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/lr1-nodes"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[GEN]${NC} $1"; }
print_success() { echo -e "${GREEN}[GEN]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[GEN]${NC} $1"; }

usage() {
    cat << EOF
LibreRouter v1 Node Configuration Generator

Usage: $0 <number_of_nodes> [options]

Options:
    --mesh-name <name>     Mesh network name (default: TestMesh)
    --ip-base <network>    Base network for mesh (default: 10.13.0.0/16)
    --password <pass>      WiFi password (default: TestMesh2024!)
    --output-dir <dir>     Output directory (default: ./lr1-nodes)
    -h, --help             Show this help

Examples:
    $0 3                           # Generate 3 node configs
    $0 5 --mesh-name MyMesh        # Generate 5 nodes for "MyMesh"
    $0 4 --ip-base 10.20.0.0/16    # Use different IP range

Generated Configuration:
    - Radio0 (2.4GHz): AP + Mesh, minimal power (10 dBm)
    - Radio1 (5GHz-1): Mesh only, minimal power (10 dBm)  
    - Radio2 (5GHz-2): DISABLED
    
Node IP Assignment:
    - Node 1: 10.13.0.1 (if MAC ends in 00:01)
    - Node 2: 10.13.0.2 (if MAC ends in 00:02)
    - etc. (actual IPs calculated from MAC address)

EOF
}

generate_node_config() {
    local node_num="$1"
    local mesh_name="$2"
    local ip_base="$3"
    local wifi_password="$4"
    local output_file="$5"
    
    # Extract network parts for IP calculation
    local network_part1=$(echo "$ip_base" | cut -d'.' -f1)
    local network_part2=$(echo "$ip_base" | cut -d'.' -f2)
    
    # Generate node-specific parameters
    local node_id=$(printf "%02d" "$node_num")
    local hostname_suffix=$(printf "%03d" "$node_num")
    
    # Channel assignments to avoid interference
    local ch_2ghz_array=(1 6 11 1 6 11 1 6 11 1)  # Cycle through non-overlapping channels
    local ch_5ghz_array=(36 44 149 157 36 44 149 157 36 44)  # Cycle through 5GHz channels
    
    local ch_2ghz=${ch_2ghz_array[$((node_num - 1))]}
    local ch_5ghz=${ch_5ghz_array[$((node_num - 1))]}
    
    cat > "$output_file" << EOF
# LibreRouter v1 Node Configuration - Node $node_num
# Generated for $mesh_name mesh network
# Hardware: LR1 with 3 radios (1x2.4GHz + 2x5GHz)
# 
# Radio Configuration:
# - Radio0 (2.4GHz wmac): AP + Mesh, minimal power
# - Radio1 (5GHz PCIe0): Mesh only, minimal power
# - Radio2 (5GHz PCIe1): DISABLED
#
# Expected Node IP: $network_part1.$network_part2.0.$node_num (if MAC ends in 00:$node_id)

config lime 'system'
	option hostname 'LR1-$mesh_name-$hostname_suffix'
	option domain 'mesh.local'
	option keep_on_upgrade 'libremesh base-files-essential /etc/sysupgrade.conf'

# Radio0: 2.4GHz built-in radio (wmac) - AP + Mesh
config wifi radio0
	option modes 'ap adhoc'
	option ap_ssid '$mesh_name.org'
	option ap_key '$wifi_password'
	option ap_encryption 'psk2'
	option adhoc_ssid '$mesh_name-mesh'
	option adhoc_bssid 'ca:fe:00:c0:ff:ee'
	option adhoc_mcast_rate_2ghz '24000'
	option distance_2ghz '1000'
	option channel_2ghz '$ch_2ghz'
	option txpower '10'  # Minimal power (10 dBm)

# Radio1: 5GHz PCIe radio 1 - Mesh only
config wifi radio1
	option modes 'adhoc'
	option adhoc_ssid '$mesh_name-mesh'
	option adhoc_bssid 'ca:fe:00:c0:ff:ee'
	option adhoc_mcast_rate_5ghz '6000'
	option distance_5ghz '1000'
	option channel_5ghz '$ch_5ghz'
	option txpower '10'  # Minimal power (10 dBm)

# Radio2: 5GHz PCIe radio 2 - DISABLED
config wifi radio2
	option modes ''  # Empty modes = disabled

# Gateway configuration for Node $node_num
config lime 'proto' 'batadv'
	option gw_mode 'client'  # All nodes as clients initially
	option gw_sel_class '20'

# Node-specific network tweaks
config lime 'network'
	# Use lower DHCP range offset for this node
	option anygw_dhcp_start '$(($node_num * 10 + 2))'
	option anygw_dhcp_limit '8'

EOF

    print_info "Generated node $node_num: $(basename "$output_file")"
}

generate_gateway_override() {
    local gateway_node="$1"
    local output_file="$2"
    
    cat > "$output_file" << EOF
# Gateway Override for Node $gateway_node
# Apply this configuration to designate a node as primary gateway
#
# Usage: Copy this content to /etc/config/lime-node on the gateway router

# Override gateway mode
config lime 'proto' 'batadv'
	option gw_mode 'server'
	option gw_sel_class '255'  # Highest priority
	option gw_bandwidth '50000/10000'  # 50 Mbps down / 10 Mbps up

# Enable WAN interface for internet access
config net 'wan'
	option proto 'dhcp'
	option auto '1'

EOF

    print_success "Generated gateway override: $(basename "$output_file")"
}

generate_deployment_script() {
    local num_nodes="$1"
    local mesh_name="$2"
    local output_file="$3"
    
    cat > "$output_file" << 'DEPLOY_SCRIPT_EOF'
#!/bin/bash
#
# TestMesh LR1 Deployment Script
# Deploy generated configurations to LibreRouter v1 devices
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER_PASSWORD="${ROUTER_PASSWORD:-toorlibre1}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[DEPLOY]${NC} $1"; }
print_success() { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
print_error() { echo -e "${RED}[DEPLOY]${NC} $1"; }

# SSH options for LibreRouter
SSH_OPTS="-oHostKeyAlgorithms=+ssh-rsa -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oPasswordAuthentication=yes -oPubkeyAuthentication=no"

ssh_cmd() {
    local router_ip="$1"
    shift
    sshpass -p "$ROUTER_PASSWORD" ssh $SSH_OPTS root@"$router_ip" "$@"
}

scp_cmd() {
    local router_ip="$1"
    local src="$2"
    local dest="$3"
    sshpass -p "$ROUTER_PASSWORD" scp $SSH_OPTS "$src" root@"$router_ip":"$dest"
}

deploy_node() {
    local node_num="$1"
    local router_ip="$2"
    local config_file="$SCRIPT_DIR/lime-node-$node_num"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Configuration file not found: $config_file"
        return 1
    fi
    
    print_info "Deploying Node $node_num configuration to $router_ip"
    
    # Test connection
    if ! ping -c 1 -W 3 "$router_ip" >/dev/null 2>&1; then
        print_error "Cannot reach router at $router_ip"
        return 1
    fi
    
    if ! ssh_cmd "$router_ip" "echo 'SSH OK'" >/dev/null 2>&1; then
        print_error "Cannot establish SSH connection to $router_ip"
        return 1
    fi
    
    # Backup existing config
    if ssh_cmd "$router_ip" "test -f /etc/config/lime-node"; then
        ssh_cmd "$router_ip" "cp /etc/config/lime-node /etc/config/lime-node.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Backed up existing lime-node configuration"
    fi
    
    # Deploy configuration
    scp_cmd "$router_ip" "$config_file" "/etc/config/lime-node"
    
    # Apply configuration
    print_info "Applying configuration..."
    ssh_cmd "$router_ip" "lime-config && /etc/init.d/network restart"
    
    print_success "Node $node_num deployed successfully to $router_ip"
    
    # Show expected IP
    local expected_ip=$(ssh_cmd "$router_ip" "ip addr show br-lan | grep 'inet ' | awk '{print \$2}' | cut -d'/' -f1" 2>/dev/null || echo "unknown")
    print_info "Node IP: $expected_ip"
}

usage() {
    cat << EOF
EOF
    cat << 'USAGE_EOF'
TestMesh LR1 Deployment Script

Usage: $0 <command> [options]

Commands:
    deploy <node_num> <router_ip>   Deploy specific node config
    deploy-all <ip_list>            Deploy to multiple routers sequentially
    verify <router_ip>              Verify deployment
    status <router_ip>              Show node status

Examples:
    $0 deploy 1 10.13.0.1          # Deploy node 1 config to router
    $0 deploy 2 thisnode.info       # Deploy node 2 config
    $0 deploy-all "10.13.0.1 10.13.0.2 10.13.0.3"  # Deploy to multiple
    $0 verify 10.13.0.1             # Check deployment
    $0 status 10.13.0.1             # Show mesh status

Environment:
    ROUTER_PASSWORD                 SSH password (default: toorlibre1)

USAGE_EOF
}

case "${1:-help}" in
    deploy)
        if [[ $# -lt 3 ]]; then
            echo "Usage: $0 deploy <node_num> <router_ip>"
            exit 1
        fi
        deploy_node "$2" "$3"
        ;;
    deploy-all)
        if [[ $# -lt 2 ]]; then
            echo "Usage: $0 deploy-all \"<ip1> <ip2> <ip3>\""
            exit 1
        fi
        node_num=1
        for router_ip in $2; do
            deploy_node "$node_num" "$router_ip"
            node_num=$((node_num + 1))
            echo
        done
        ;;
    verify)
        if [[ $# -lt 2 ]]; then
            echo "Usage: $0 verify <router_ip>"
            exit 1
        fi
        # Use existing verification script
        if [[ -f "$SCRIPT_DIR/verify-mesh-deployment.sh" ]]; then
            exec "$SCRIPT_DIR/verify-mesh-deployment.sh" "$2"
        else
            print_error "Verification script not found"
            exit 1
        fi
        ;;
    status)
        if [[ $# -lt 2 ]]; then
            echo "Usage: $0 status <router_ip>"
            exit 1
        fi
        print_info "Mesh status for $2:"
        ssh_cmd "$2" "batctl o; echo; batctl n; echo; iwinfo"
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "Unknown command: ${1:-help}"
        usage
        exit 1
        ;;
esac
DEPLOY_SCRIPT_EOF

    chmod +x "$output_file"
    print_success "Generated deployment script: $(basename "$output_file")"
}

main() {
    local num_nodes=""
    local mesh_name="TestMesh"
    local ip_base="10.13.0.0/16"
    local wifi_password="TestMesh2024!"
    local output_dir="$OUTPUT_DIR"
    
    # First argument should be number of nodes
    if [[ $# -gt 0 ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
        num_nodes="$1"
        shift
    fi
    
    # Parse remaining arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mesh-name)
                mesh_name="$2"
                shift 2
                ;;
            --ip-base)
                ip_base="$2"
                shift 2
                ;;
            --password)
                wifi_password="$2"
                shift 2
                ;;
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$num_nodes" ]] || ! [[ "$num_nodes" =~ ^[0-9]+$ ]] || [[ "$num_nodes" -lt 1 ]] || [[ "$num_nodes" -gt 20 ]]; then
        echo "Error: Number of nodes must be between 1 and 20"
        usage
        exit 1
    fi
    
    print_info "Generating LibreRouter v1 node configurations"
    print_info "Nodes: $num_nodes"
    print_info "Mesh: $mesh_name"
    print_info "Network: $ip_base"
    print_info "Output: $output_dir"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Generate individual node configurations
    for ((i=1; i<=num_nodes; i++)); do
        local output_file="$output_dir/lime-node-$i"
        generate_node_config "$i" "$mesh_name" "$ip_base" "$wifi_password" "$output_file"
    done
    
    # Generate gateway override
    generate_gateway_override "1" "$output_dir/gateway-override.conf"
    
    # Generate deployment script
    generate_deployment_script "$num_nodes" "$mesh_name" "$output_dir/deploy.sh"
    
    # Generate README
    cat > "$output_dir/README.md" << EOF
# LibreRouter v1 TestMesh Node Configurations

Generated configurations for $num_nodes LibreRouter v1 devices.

## Hardware Configuration

Each LibreRouter v1 has 3 WiFi radios:
- **Radio0 (2.4GHz)**: Client AP + Mesh, 10 dBm power
- **Radio1 (5GHz-1)**: Mesh only, 10 dBm power  
- **Radio2 (5GHz-2)**: DISABLED

## Files Generated

EOF
    
    for ((i=1; i<=num_nodes; i++)); do
        echo "- \`lime-node-$i\` - Configuration for Node $i" >> "$output_dir/README.md"
    done
    
    cat >> "$output_dir/README.md" << EOF
- \`gateway-override.conf\` - Gateway configuration override
- \`deploy.sh\` - Automated deployment script
- \`README.md\` - This file

## Deployment

### Option 1: Automated Deployment
\`\`\`bash
# Deploy to multiple routers
./deploy.sh deploy-all "10.13.0.1 10.13.0.2 10.13.0.3"

# Deploy single node
./deploy.sh deploy 1 thisnode.info
\`\`\`

### Option 2: Manual Deployment
\`\`\`bash
# Copy configuration to router
scp lime-node-1 root@10.13.0.1:/etc/config/lime-node

# Apply configuration
ssh root@10.13.0.1 "lime-config && /etc/init.d/network restart"
\`\`\`

## Gateway Setup

To designate Node 1 as internet gateway:
\`\`\`bash
# Copy gateway override to Node 1
scp gateway-override.conf root@10.13.0.1:/tmp/
ssh root@10.13.0.1 "cat /tmp/gateway-override.conf >> /etc/config/lime-node"
ssh root@10.13.0.1 "lime-config && /etc/init.d/network restart"
\`\`\`

## Verification

\`\`\`bash
# Check mesh status
./deploy.sh status 10.13.0.1

# Verify connectivity  
./deploy.sh verify 10.13.0.1
\`\`\`

## Network Details

- **Mesh Name**: $mesh_name
- **WiFi Network**: $mesh_name.org  
- **WiFi Password**: $wifi_password
- **IP Range**: $ip_base
- **Mesh Protocol**: BATMAN-adv + BMX6/BMX7 + Babel

## Expected Node IPs

Node IPs are calculated from MAC addresses: 10.13.{MAC5}.{MAC6}

If routers have sequential MACs ending in 00:01, 00:02, etc:
EOF
    
    for ((i=1; i<=num_nodes; i++)); do
        local node_id=$(printf "%02d" "$i")
        echo "- Node $i: 10.13.0.$i (if MAC ends in 00:$node_id)" >> "$output_dir/README.md"
    done
    
    echo
    print_success "✅ Generated $num_nodes LibreRouter v1 configurations in $output_dir"
    print_info "📖 See $output_dir/README.md for deployment instructions"
    print_warning "⚡ Power settings: All radios set to minimal power (10 dBm)"
    print_warning "📡 Radio2 (5GHz-2) is DISABLED as requested"
}

# Check dependencies
if ! command -v sshpass >/dev/null; then
    print_error "Missing dependency: sshpass"
    print_info "Install with: sudo apt install sshpass"
    exit 1
fi

main "$@"