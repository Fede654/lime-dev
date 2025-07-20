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
