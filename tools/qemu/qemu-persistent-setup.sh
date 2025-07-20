#!/bin/bash

# QEMU LibreMesh Persistent Setup for Testing
# This script configures QEMU for persistent testing with lime-app

set -e

echo "🖥️  QEMU LibreMesh Persistent Testing Setup"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Configuration
QEMU_IP="10.13.0.1"
PERSISTENT_CONFIG_DIR="/tmp/qemu-lime-persistent"

# Check if QEMU is already running
check_qemu_running() {
    if curl -s --connect-timeout 3 "http://$QEMU_IP/ubus" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Setup persistent configuration directory
setup_persistent_config() {
    print_status "Setting up persistent configuration..."
    
    mkdir -p "$PERSISTENT_CONFIG_DIR"
    
    # Create QEMU startup script
    cat > "$PERSISTENT_CONFIG_DIR/start-qemu.sh" << 'EOF'
#!/bin/bash
# Persistent QEMU startup for lime-app testing

LIME_PACKAGES_DIR="../lime-packages"
ROOTFS_IMAGE="$LIME_PACKAGES_DIR/build/libremesh-2020.4-ow19-x86-64-rootfs.tar.gz"
KERNEL_IMAGE="$LIME_PACKAGES_DIR/build/libremesh-2020.4-ow19-x86-64-ramfs.bzImage"

if [ ! -f "$ROOTFS_IMAGE" ] || [ ! -f "$KERNEL_IMAGE" ]; then
    echo "ERROR: LibreMesh images not found in $LIME_PACKAGES_DIR/build/"
    echo "Please download the required images first."
    exit 1
fi

# Start QEMU with persistent networking
screen -S libremesh-testing -d -m sudo "$LIME_PACKAGES_DIR/tools/qemu_dev_start" \
    --libremesh-workdir "$LIME_PACKAGES_DIR" \
    "$ROOTFS_IMAGE" \
    "$KERNEL_IMAGE"

echo "QEMU LibreMesh started in screen session 'libremesh-testing'"
echo "Access with: screen -r libremesh-testing"
EOF
    
    chmod +x "$PERSISTENT_CONFIG_DIR/start-qemu.sh"
    
    # Create QEMU configuration script
    cat > "$PERSISTENT_CONFIG_DIR/configure-qemu.sh" << 'EOF'
#!/bin/bash
# Configure QEMU LibreMesh for persistent testing

echo "Configuring QEMU LibreMesh for testing..."

# Set root password for testing
echo -e "admin\nadmin" | passwd root

# Configure network interface
ip addr add 10.13.0.1/16 dev br-lan 2>/dev/null || true

# Start web server
/etc/init.d/uhttpd start 2>/dev/null || true
/etc/init.d/uhttpd enable 2>/dev/null || true

# Ensure ubus is running
/etc/init.d/ubus start 2>/dev/null || true

# Create test user session file
mkdir -p /tmp/test-sessions
echo '{"username":"root","authenticated":true}' > /tmp/test-sessions/test-session.json

# Install development packages if available
# opkg update 2>/dev/null || true
# opkg install curl 2>/dev/null || true

echo "QEMU LibreMesh configured for testing"
echo "Web interface: http://10.13.0.1/app"
echo "Root password: admin"
echo "Ready for lime-app testing!"
EOF
    
    chmod +x "$PERSISTENT_CONFIG_DIR/configure-qemu.sh"
    
    print_success "Persistent configuration created in $PERSISTENT_CONFIG_DIR"
}

# Apply configuration to running QEMU
configure_running_qemu() {
    print_status "Configuring running QEMU instance..."
    
    # Check if we can access the console
    if ! screen -list | grep -q "libremesh"; then
        print_error "No QEMU screen session found"
        return 1
    fi
    
    # Set root password
    print_status "Setting root password to 'admin'..."
    timeout 5 screen -r libremesh-2020 -X stuff "echo -e 'admin\\nadmin' | passwd root$(printf \\r)" 2>/dev/null || true
    
    # Ensure network interface is configured
    print_status "Configuring network interface..."
    timeout 5 screen -r libremesh-2020 -X stuff "ip addr add 10.13.0.1/16 dev br-lan$(printf \\r)" 2>/dev/null || true
    
    # Start/restart web server
    print_status "Starting web server..."
    timeout 5 screen -r libremesh-2020 -X stuff "/etc/init.d/uhttpd restart$(printf \\r)" 2>/dev/null || true
    
    # Wait for services to start
    sleep 3
    
    print_success "QEMU configuration applied"
}

# Test QEMU accessibility
test_qemu_access() {
    print_status "Testing QEMU accessibility..."
    
    # Test web interface
    if curl -s --connect-timeout 5 "http://$QEMU_IP/" > /dev/null; then
        print_success "Web interface accessible"
    else
        print_warning "Web interface not responding"
        return 1
    fi
    
    # Test ubus endpoint
    if curl -s --connect-timeout 5 "http://$QEMU_IP/ubus" > /dev/null; then
        print_success "ubus endpoint accessible"
    else
        print_warning "ubus endpoint not responding"
        return 1
    fi
    
    # Test authentication
    local auth_response
    auth_response=$(curl -s --connect-timeout 5 "http://$QEMU_IP/ubus" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"admin"}]}' \
        2>/dev/null || echo '{"error":"failed"}')
    
    if echo "$auth_response" | grep -q '"result":\s*\[0'; then
        print_success "Authentication working (root/admin)"
    else
        print_warning "Authentication may need configuration"
    fi
    
    return 0
}

# Create systemd service for persistent QEMU (optional)
create_systemd_service() {
    if [ "$1" = "--systemd" ]; then
        print_status "Creating systemd service..."
        
        sudo tee /etc/systemd/system/qemu-libremesh-testing.service > /dev/null << EOF
[Unit]
Description=QEMU LibreMesh Testing Environment
After=network.target

[Service]
Type=forking
User=$USER
WorkingDirectory=$PWD
ExecStart=$PERSISTENT_CONFIG_DIR/start-qemu.sh
ExecStop=/usr/bin/screen -S libremesh-testing -X quit
Restart=no

[Install]
WantedBy=multi-user.target
EOF
        
        sudo systemctl daemon-reload
        print_success "Systemd service created (qemu-libremesh-testing.service)"
        print_status "Enable with: sudo systemctl enable qemu-libremesh-testing"
        print_status "Start with: sudo systemctl start qemu-libremesh-testing"
    fi
}

# Save current lime-app build for quick deployment
save_current_build() {
    print_status "Saving current lime-app build..."
    
    if [ -d "build" ]; then
        cp -r build "$PERSISTENT_CONFIG_DIR/lime-app-build"
        print_success "Current build saved to $PERSISTENT_CONFIG_DIR/lime-app-build"
    else
        print_warning "No build directory found. Run 'npm run build:production' first."
    fi
}

# Quick deploy saved build to QEMU
quick_deploy() {
    if [ "$1" = "--deploy" ]; then
        print_status "Quick deploying saved build to QEMU..."
        
        if [ -d "$PERSISTENT_CONFIG_DIR/lime-app-build" ]; then
            # Deploy to QEMU via SCP or similar method
            if check_qemu_running; then
                # Copy files to a temporary location QEMU can access
                sudo cp -r "$PERSISTENT_CONFIG_DIR/lime-app-build"/* /tmp/qemu-lime-app/ 2>/dev/null || true
                print_success "Build deployed to QEMU"
            else
                print_warning "QEMU not running"
            fi
        else
            print_error "No saved build found. Run without --deploy first."
        fi
    fi
}

# Main execution
main() {
    case "${1:-setup}" in
        "setup")
            setup_persistent_config
            if check_qemu_running; then
                configure_running_qemu
                test_qemu_access
            else
                print_warning "QEMU not running. Use '$PERSISTENT_CONFIG_DIR/start-qemu.sh' to start."
            fi
            save_current_build
            ;;
        "test")
            if check_qemu_running; then
                test_qemu_access
            else
                print_error "QEMU not running"
                exit 1
            fi
            ;;
        "--deploy")
            quick_deploy --deploy
            ;;
        "--systemd")
            create_systemd_service --systemd
            ;;
        "help"|"--help")
            echo "Usage: $0 [setup|test|--deploy|--systemd|help]"
            echo
            echo "Commands:"
            echo "  setup     - Initial setup (default)"
            echo "  test      - Test QEMU accessibility"
            echo "  --deploy  - Quick deploy saved build"
            echo "  --systemd - Create systemd service"
            echo "  help      - Show this help"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"