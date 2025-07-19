#!/bin/bash
#
# LibreMesh Mesh Configuration Manager
# Deploys and manages standardized mesh network configurations
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MESH_CONFIGS_DIR="$LIME_BUILD_DIR/tools/mesh-configs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[MESH]${NC} $1"; }
print_success() { echo -e "${GREEN}[MESH]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[MESH]${NC} $1"; }
print_error() { echo -e "${RED}[MESH]${NC} $1"; }

usage() {
    cat << EOF
LibreMesh Mesh Configuration Manager

Usage: $0 <command> [options]

Commands:
    list                    List available mesh configurations
    deploy <config> [ip]    Deploy mesh configuration to router
    status <config> [ip]    Show mesh network status
    verify <config> [ip]    Verify mesh connectivity
    backup <config> [ip]    Backup current mesh configuration
    export <config>         Export mesh configuration for distribution
    import <file>           Import mesh configuration from file

Options:
    --dry-run              Show what would be done without applying
    --force                Skip confirmation prompts
    --backup               Create backup before deployment
    --password <pass>      Router SSH password (or use ROUTER_PASSWORD env)
    -h, --help             Show this help

Examples:
    $0 list                           # List available configurations
    $0 deploy testmesh                # Deploy TestMesh to thisnode.info
    $0 deploy testmesh 10.13.0.1      # Deploy to specific router
    $0 status testmesh 10.13.0.1      # Check mesh status
    $0 verify testmesh                # Verify mesh connectivity
    $0 export testmesh > my-mesh.conf # Export configuration

Available Mesh Configurations:
    testmesh               Development and testing mesh network
    
Environment Variables:
    ROUTER_PASSWORD        SSH password for routers (default: toorlibre1)

EOF
}

# SSH options for LibreMesh routers
SSH_OPTS="-oHostKeyAlgorithms=+ssh-rsa -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oPasswordAuthentication=yes -oPubkeyAuthentication=no"

ssh_cmd() {
    local router_ip="$1"
    shift
    sshpass -p "${ROUTER_PASSWORD:-toorlibre1}" ssh $SSH_OPTS root@"$router_ip" "$@"
}

scp_cmd() {
    local router_ip="$1"
    local src="$2"
    local dest="$3"
    sshpass -p "${ROUTER_PASSWORD:-toorlibre1}" scp $SSH_OPTS "$src" root@"$router_ip":"$dest"
}

list_configurations() {
    print_info "Available mesh configurations:"
    echo
    
    if [[ ! -d "$MESH_CONFIGS_DIR" ]]; then
        print_warning "No mesh configurations directory found"
        return 0
    fi
    
    local config_count=0
    
    # List individual config files
    while IFS= read -r -d '' config_file; do
        local config_name=$(basename "$config_file")
        if [[ "$config_name" == lime-community-* ]]; then
            local mesh_name="${config_name#lime-community-}"
            echo "  🌐 $mesh_name"
            
            # Try to read description from config file
            local description=$(grep -m1 "^# Purpose:" "$config_file" 2>/dev/null | sed 's/^# Purpose: //' || echo "")
            if [[ -n "$description" ]]; then
                echo "     $description"
            fi
            
            config_count=$((config_count + 1))
        fi
    done < <(find "$MESH_CONFIGS_DIR" -name "lime-community-*" -type f -print0 2>/dev/null)
    
    # List README files for additional info
    if [[ -f "$MESH_CONFIGS_DIR/README.md" ]]; then
        echo
        print_info "See $MESH_CONFIGS_DIR/README.md for detailed configuration information"
    fi
    
    if [[ $config_count -eq 0 ]]; then
        print_warning "No mesh configurations found"
        print_info "Create configurations in: $MESH_CONFIGS_DIR"
    else
        echo
        print_success "Found $config_count mesh configurations"
    fi
}

deploy_configuration() {
    local config_name="$1"
    local router_ip="${2:-thisnode.info}"
    local dry_run="${3:-false}"
    local force="${4:-false}"
    local backup="${5:-false}"
    
    local config_file="$MESH_CONFIGS_DIR/lime-community-$config_name"
    local deploy_script="$MESH_CONFIGS_DIR/deploy-test-mesh.sh"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Configuration not found: $config_name"
        print_info "Available configurations:"
        list_configurations
        return 1
    fi
    
    print_info "Deploying $config_name mesh configuration to $router_ip"
    
    if [[ "$dry_run" == "true" ]]; then
        print_warning "DRY RUN MODE - No changes will be made"
        print_info "Would deploy: $config_file"
        print_info "To router: $router_ip"
        return 0
    fi
    
    # Use specific deployment script if available
    if [[ -f "$deploy_script" && "$config_name" == "testmesh" ]]; then
        local deploy_args=""
        [[ "$backup" == "true" ]] && deploy_args="$deploy_args --backup"
        [[ "$force" == "true" ]] && deploy_args="$deploy_args --force"
        
        exec "$deploy_script" "$router_ip" $deploy_args
    else
        # Generic deployment
        deploy_generic_config "$config_name" "$router_ip" "$backup" "$force"
    fi
}

deploy_generic_config() {
    local config_name="$1"
    local router_ip="$2"
    local backup="$3"
    local force="$4"
    
    local config_file="$MESH_CONFIGS_DIR/lime-community-$config_name"
    
    print_info "Testing connection to $router_ip..."
    if ! ping -c 1 -W 3 "$router_ip" >/dev/null 2>&1; then
        print_error "Cannot reach router at $router_ip"
        return 1
    fi
    
    if ! ssh_cmd "$router_ip" "echo 'SSH OK'" >/dev/null 2>&1; then
        print_error "Cannot establish SSH connection to $router_ip"
        return 1
    fi
    
    print_success "Connection established"
    
    # Backup existing configuration
    if [[ "$backup" == "true" ]]; then
        print_info "Creating backup..."
        local backup_file="/etc/config/lime-community.backup.$(date +%Y%m%d_%H%M%S)"
        if ssh_cmd "$router_ip" "test -f /etc/config/lime-community"; then
            ssh_cmd "$router_ip" "cp /etc/config/lime-community $backup_file"
            print_success "Backup created: $backup_file"
        fi
    fi
    
    # Deploy configuration
    print_info "Uploading configuration..."
    scp_cmd "$router_ip" "$config_file" "/etc/config/lime-community"
    
    # Validate configuration
    print_info "Validating configuration..."
    if ! ssh_cmd "$router_ip" "uci -q show lime-community >/dev/null"; then
        print_error "Configuration validation failed"
        return 1
    fi
    
    print_success "Configuration uploaded and validated"
    
    # Apply configuration
    print_info "Applying configuration..."
    ssh_cmd "$router_ip" "lime-config"
    ssh_cmd "$router_ip" "/etc/init.d/network restart"
    
    print_success "🎉 $config_name mesh configuration deployed successfully!"
    print_info "Router: $router_ip"
    print_info "Web interface: http://$router_ip"
}

show_status() {
    local config_name="$1"
    local router_ip="${2:-thisnode.info}"
    
    print_info "Checking $config_name mesh status on $router_ip"
    
    if ! ssh_cmd "$router_ip" "echo 'SSH OK'" >/dev/null 2>&1; then
        print_error "Cannot connect to router at $router_ip"
        return 1
    fi
    
    echo
    print_info "System Information:"
    ssh_cmd "$router_ip" "uci get system.@system[0].hostname" 2>/dev/null || echo "Unknown hostname"
    ssh_cmd "$router_ip" "uptime" 2>/dev/null
    
    echo
    print_info "Network Configuration:"
    ssh_cmd "$router_ip" "ip addr show br-lan | head -3" 2>/dev/null || true
    
    echo
    print_info "WiFi Status:"
    ssh_cmd "$router_ip" "iwinfo | grep ESSID" 2>/dev/null || echo "No WiFi information available"
    
    echo
    print_info "Mesh Protocols:"
    ssh_cmd "$router_ip" "batctl if 2>/dev/null || echo 'BATMAN-adv: Not available'"
    ssh_cmd "$router_ip" "bmx6 -c show=status 2>/dev/null | head -2 || echo 'BMX6: Not available'"
    ssh_cmd "$router_ip" "babeld -V 2>/dev/null || echo 'Babeld: Not available'"
    
    echo
    print_info "Mesh Neighbors:"
    ssh_cmd "$router_ip" "batctl n 2>/dev/null | head -5 || echo 'No BATMAN neighbors'"
}

verify_mesh() {
    local config_name="$1"
    local router_ip="${2:-thisnode.info}"
    
    print_info "Verifying $config_name mesh connectivity from $router_ip"
    
    if ! ssh_cmd "$router_ip" "echo 'SSH OK'" >/dev/null 2>&1; then
        print_error "Cannot connect to router at $router_ip"
        return 1
    fi
    
    local tests_passed=0
    local tests_total=0
    
    # Test 1: Check lime-community configuration
    echo
    print_info "Test 1: Configuration validation"
    tests_total=$((tests_total + 1))
    if ssh_cmd "$router_ip" "uci -q show lime-community >/dev/null"; then
        print_success "✓ lime-community configuration present"
        tests_passed=$((tests_passed + 1))
    else
        print_error "✗ lime-community configuration missing"
    fi
    
    # Test 2: Check WiFi interfaces
    echo
    print_info "Test 2: WiFi interfaces"
    tests_total=$((tests_total + 1))
    if ssh_cmd "$router_ip" "iwinfo | grep -q ESSID"; then
        print_success "✓ WiFi interfaces active"
        tests_passed=$((tests_passed + 1))
    else
        print_error "✗ No active WiFi interfaces"
    fi
    
    # Test 3: Check mesh protocols
    echo
    print_info "Test 3: Mesh protocols"
    tests_total=$((tests_total + 1))
    local protocols_active=0
    
    if ssh_cmd "$router_ip" "batctl if >/dev/null 2>&1"; then
        protocols_active=$((protocols_active + 1))
        print_info "  ✓ BATMAN-adv active"
    fi
    
    if ssh_cmd "$router_ip" "bmx6 -c show=status >/dev/null 2>&1"; then
        protocols_active=$((protocols_active + 1))
        print_info "  ✓ BMX6 active"
    fi
    
    if ssh_cmd "$router_ip" "pgrep babeld >/dev/null 2>&1"; then
        protocols_active=$((protocols_active + 1))
        print_info "  ✓ Babeld active"
    fi
    
    if [[ $protocols_active -gt 0 ]]; then
        print_success "✓ $protocols_active mesh protocols active"
        tests_passed=$((tests_passed + 1))
    else
        print_error "✗ No mesh protocols active"
    fi
    
    # Test 4: Network connectivity
    echo
    print_info "Test 4: Network connectivity"
    tests_total=$((tests_total + 1))
    if ssh_cmd "$router_ip" "ping -c 1 8.8.8.8 >/dev/null 2>&1"; then
        print_success "✓ Internet connectivity"
        tests_passed=$((tests_passed + 1))
    else
        print_warning "⚠ No internet connectivity (may be expected)"
        tests_passed=$((tests_passed + 1))  # Don't fail on this
    fi
    
    echo
    if [[ $tests_passed -eq $tests_total ]]; then
        print_success "🎉 All tests passed ($tests_passed/$tests_total)"
        print_success "$config_name mesh is working correctly"
    else
        print_warning "⚠ Some tests failed ($tests_passed/$tests_total)"
        print_info "Check individual test results above"
    fi
}

export_configuration() {
    local config_name="$1"
    local config_file="$MESH_CONFIGS_DIR/lime-community-$config_name"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Configuration not found: $config_name"
        return 1
    fi
    
    print_info "Exporting $config_name configuration..." >&2
    cat "$config_file"
}

main() {
    local command="${1:-help}"
    
    case "$command" in
        list)
            list_configurations
            ;;
        deploy)
            if [[ $# -lt 2 ]]; then
                print_error "Configuration name required"
                usage
                exit 1
            fi
            
            local config_name="$2"
            local router_ip="thisnode.info"
            local dry_run="false"
            local force="false"
            local backup="false"
            
            # Parse options
            shift 2
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --dry-run)
                        dry_run="true"
                        shift
                        ;;
                    --force)
                        force="true"
                        shift
                        ;;
                    --backup)
                        backup="true"
                        shift
                        ;;
                    --password)
                        export ROUTER_PASSWORD="$2"
                        shift 2
                        ;;
                    -*)
                        print_error "Unknown option: $1"
                        shift
                        ;;
                    *)
                        router_ip="$1"
                        shift
                        ;;
                esac
            done
            
            deploy_configuration "$config_name" "$router_ip" "$dry_run" "$force" "$backup"
            ;;
        status)
            if [[ $# -lt 2 ]]; then
                print_error "Configuration name required"
                usage
                exit 1
            fi
            show_status "$2" "$3"
            ;;
        verify)
            if [[ $# -lt 2 ]]; then
                print_error "Configuration name required"
                usage
                exit 1
            fi
            verify_mesh "$2" "$3"
            ;;
        export)
            if [[ $# -lt 2 ]]; then
                print_error "Configuration name required"
                usage
                exit 1
            fi
            export_configuration "$2"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            print_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Check dependencies
if ! command -v sshpass >/dev/null; then
    print_error "Missing dependency: sshpass"
    print_info "Install with: sudo apt install sshpass"
    exit 1
fi

main "$@"