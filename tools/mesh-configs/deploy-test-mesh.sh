#!/bin/bash
#
# Deploy TestMesh Community Configuration
# Deploys the test mesh configuration to LibreMesh routers
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/lime-community-testmesh"
ROUTER_IP="${1:-thisnode.info}"
ROUTER_PASSWORD="${ROUTER_PASSWORD:-toorlibre1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[DEPLOY]${NC} $1"; }
print_success() { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[DEPLOY]${NC} $1"; }
print_error() { echo -e "${RED}[DEPLOY]${NC} $1"; }

# SSH options for LibreMesh routers (handles thisnode.info conflicts)
SSH_OPTS="-oHostKeyAlgorithms=+ssh-rsa -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oPasswordAuthentication=yes -oPubkeyAuthentication=no"

usage() {
    cat << EOF
Deploy TestMesh Community Configuration

Usage: $0 [ROUTER_IP] [OPTIONS]

Arguments:
    ROUTER_IP       Router IP address or hostname (default: thisnode.info)

Environment Variables:
    ROUTER_PASSWORD SSH password for router (default: toorlibre1)

Options:
    --dry-run       Show what would be deployed without applying
    --backup        Create backup of existing configuration
    --force         Skip confirmation prompts
    -h, --help      Show this help

Examples:
    $0                          # Deploy to thisnode.info
    $0 10.13.0.1               # Deploy to specific router
    $0 --dry-run               # Preview deployment
    ROUTER_PASSWORD=mypass $0  # Use custom password

This script deploys the TestMesh community configuration to LibreMesh routers,
creating a test mesh network suitable for development and testing.

TestMesh Configuration:
• Network: TestMesh.org (10.13.0.0/16)
• WiFi Password: TestMesh2024!
• Dual-band with ad-hoc mesh backhaul
• Multiple routing protocols enabled
• Development-friendly settings

EOF
}

ssh_cmd() {
    sshpass -p "$ROUTER_PASSWORD" ssh $SSH_OPTS root@"$ROUTER_IP" "$@"
}

scp_cmd() {
    sshpass -p "$ROUTER_PASSWORD" scp $SSH_OPTS "$@"
}

test_connection() {
    print_info "Testing connection to $ROUTER_IP..."
    
    if ping -c 1 -W 3 "$ROUTER_IP" >/dev/null 2>&1; then
        print_success "Router reachable at $ROUTER_IP"
    else
        print_error "Cannot reach router at $ROUTER_IP"
        exit 1
    fi
    
    if ssh_cmd "echo 'SSH OK'" >/dev/null 2>&1; then
        print_success "SSH connection established"
    else
        print_error "Cannot establish SSH connection"
        print_error "Check password and router accessibility"
        exit 1
    fi
}

backup_config() {
    print_info "Creating backup of existing configuration..."
    
    local backup_file="/etc/config/lime-community.backup.$(date +%Y%m%d_%H%M%S)"
    
    if ssh_cmd "test -f /etc/config/lime-community"; then
        ssh_cmd "cp /etc/config/lime-community $backup_file"
        print_success "Backup created: $backup_file"
    else
        print_info "No existing lime-community configuration found"
    fi
}

deploy_config() {
    print_info "Deploying TestMesh community configuration..."
    
    # Upload configuration file
    scp_cmd "$CONFIG_FILE" root@"$ROUTER_IP":/etc/config/lime-community
    print_success "Configuration uploaded"
    
    # Validate configuration
    print_info "Validating configuration..."
    if ssh_cmd "uci -q show lime-community >/dev/null"; then
        print_success "Configuration syntax valid"
    else
        print_error "Configuration validation failed"
        return 1
    fi
}

apply_config() {
    print_info "Applying configuration..."
    
    # Generate configuration
    print_info "Generating LibreMesh configuration..."
    ssh_cmd "lime-config"
    
    # Restart networking
    print_info "Restarting network services..."
    ssh_cmd "/etc/init.d/network restart"
    
    print_success "Configuration applied successfully"
}

show_deployment_info() {
    print_success "🎉 TestMesh Configuration Deployed Successfully!"
    echo
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                             📡 TESTMESH DEPLOYED 📡                          ║"
    echo "╠══════════════════════════════════════════════════════════════════════════════╣"
    echo "║                                                                              ║"
    echo "║  🌐 Network Information:                                                     ║"
    echo "║  • Router IP: $ROUTER_IP                                                     ║"
    echo "║  • Network Range: 10.13.0.0/16                                              ║"
    echo "║  • WiFi SSID: TestMesh.org                                                   ║"
    echo "║  • WiFi Password: TestMesh2024!                                              ║"
    echo "║  • Mesh Protocol: BATMAN-adv + BMX6/BMX7 + Babel                            ║"
    echo "║                                                                              ║"
    echo "║  🔧 Access Information:                                                      ║"
    echo "║  • Web Interface: http://$ROUTER_IP                                         ║"
    echo "║  • SSH Access: ssh root@$ROUTER_IP                                          ║"
    echo "║  • lime-app: http://$ROUTER_IP/app (if installed)                          ║"
    echo "║                                                                              ║"
    echo "║  📋 Next Steps:                                                              ║"
    echo "║  1. Connect additional routers with same configuration                       ║"
    echo "║  2. Verify mesh connectivity between nodes                                   ║"
    echo "║  3. Test WiFi access with TestMesh.org network                              ║"
    echo "║  4. Monitor routing tables and mesh status                                   ║"
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo
}

main() {
    local dry_run="false"
    local backup="false"
    local force="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --backup)
                backup="true"
                shift
                ;;
            --force)
                force="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                ROUTER_IP="$1"
                shift
                ;;
        esac
    done
    
    print_info "TestMesh Community Configuration Deployment"
    print_info "Target router: $ROUTER_IP"
    
    if [[ "$dry_run" == "true" ]]; then
        print_warning "DRY RUN MODE - No changes will be made"
    fi
    
    echo
    
    # Validate configuration file
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Show configuration preview
    print_info "Configuration preview:"
    echo "• Network: TestMesh.org (10.13.0.0/16)"
    echo "• WiFi Password: TestMesh2024!"
    echo "• Routing: BATMAN-adv + BMX6/BMX7 + Babel"
    echo "• Purpose: Development and testing"
    echo
    
    if [[ "$force" != "true" && "$dry_run" != "true" ]]; then
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        print_info "Would perform the following actions:"
        print_info "1. Test connection to $ROUTER_IP"
        print_info "2. Upload configuration file"
        print_info "3. Validate configuration syntax"
        print_info "4. Apply configuration with lime-config"
        print_info "5. Restart network services"
        print_info ""
        print_info "Dry run completed - no changes made"
        exit 0
    fi
    
    # Execute deployment
    test_connection
    
    if [[ "$backup" == "true" ]]; then
        backup_config
    fi
    
    deploy_config
    apply_config
    show_deployment_info
    
    print_success "🚀 TestMesh deployment completed successfully!"
}

# Check dependencies
if ! command -v sshpass >/dev/null; then
    print_error "Missing dependency: sshpass"
    print_info "Install with: sudo apt install sshpass"
    exit 1
fi

main "$@"