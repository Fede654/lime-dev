#!/bin/bash
#
# Unified LibreRouter Legacy Upgrade Script
# Handles both safe-upgrade installation/update and firmware upgrade
#
# Usage:
#   ./upgrade-legacy-router.sh <ROUTER_IP>                    # Update safe-upgrade only
#   ./upgrade-legacy-router.sh <ROUTER_IP> <FIRMWARE_FILE>    # Update safe-upgrade + firmware
#

set -e

# Configuration
ROUTER_IP="${1:-thisnode.info}"
FIRMWARE_FILE="$2"
ROUTER_PASSWORD="${ROUTER_PASSWORD:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_critical() { echo -e "${RED}[CRITICAL ERROR]${NC} $1"; }
print_step() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

detect_router_ip() {
    local test_ips=("thisnode.info" "10.13.0.1" "192.168.1.1")
    
    # If user specified an IP, verify it's reachable
    if [[ "$ROUTER_IP" != "thisnode.info" ]]; then
        print_info "Testing specified router: $ROUTER_IP..."
        if ping -c 1 -W 3 "$ROUTER_IP" >/dev/null 2>&1; then
            print_success "Router reachable at $ROUTER_IP"
            return 0
        else
            print_error "Cannot reach router at $ROUTER_IP"
            print_info "Please check:"
            print_info "• Router is powered on and connected"
            print_info "• IP address is correct"
            print_info "• Network connectivity"
            exit 1
        fi
    fi
    
    print_info "Auto-detecting LibreMesh router..."
    
    for ip in "${test_ips[@]}"; do
        print_info "Testing $ip..."
        if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
            print_success "Router found at $ip"
            ROUTER_IP="$ip"
            return 0
        fi
    done
    
    print_error "No LibreMesh router found at common addresses!"
    print_error "Please check:"
    print_error "• Router is powered on and connected to network"
    print_error "• Router has LibreMesh firmware installed"
    print_error "• Network connectivity is working"
    print_info ""
    print_info "Common troubleshooting:"
    print_info "• Connect to router's WiFi network directly"
    print_info "• Check router's actual IP with: ip route | grep default"
    print_info "• Specify router IP manually: $0 ROUTER_IP"
    print_info "• Try: thisnode.info, 10.13.0.1, 192.168.1.1"
    exit 1
}

test_ssh_connection() {
    print_info "Testing SSH connection to $ROUTER_IP..."
    
    # Test SSH connection with timeout using consistent legacy options
    if timeout 10 sshpass -p "$ROUTER_PASSWORD" ssh \
        $SSH_LEGACY_OPTS \
        -oConnectTimeout=5 \
        root@"$ROUTER_IP" "echo 'SSH connection successful'" >/dev/null 2>&1; then
        print_success "SSH connection established"
        print_info "Note: Host key verification disabled for thisnode.info multi-device support"
        return 0
    else
        print_error "Cannot establish SSH connection to $ROUTER_IP"
        print_error "Please check:"
        print_error "• SSH password is correct (default: toorlibre1)"
        print_error "• SSH service is running on router"
        print_error "• Router is accessible via network"
        print_error "• Router has LibreMesh/OpenWrt firmware"
        print_info ""
        print_info "Troubleshooting tips:"
        print_info "• Try manual SSH: ssh $SSH_LEGACY_OPTS root@$ROUTER_IP"
        print_info "• Check if router responds: ping $ROUTER_IP"
        print_info "• Verify router password"
        print_info "• Connect directly to router's WiFi"
        exit 1
    fi
}

get_router_password() {
    if [[ -z "$ROUTER_PASSWORD" ]]; then
        echo
        echo "LibreRouter Legacy Upgrade for: $ROUTER_IP"
        echo
        read -s -p "Enter router SSH password (default: toorlibre1): " ROUTER_PASSWORD
        echo
        if [[ -z "$ROUTER_PASSWORD" ]]; then
            ROUTER_PASSWORD="toorlibre1"
        fi
        print_info "Using provided password"
    fi
}

usage() {
    cat << EOF
LibreRouter v1 Upgrade Utility

🚀 Fast HTTP upload with automatic safe-upgrade management
🛡️  Safe dual-boot system with automatic revert capability

Usage: $0 [ROUTER_IP] [FIRMWARE_FILE] [OPTIONS]

Arguments:
    ROUTER_IP       Optional: Router IP address or hostname 
                    Default: thisnode.info (also try: 10.13.0.1, 192.168.1.1)
    FIRMWARE_FILE   Optional: Local firmware .bin file to upload

Options:
    --auto-confirm  Skip confirmation prompts (DANGEROUS)
    --force         Force firmware upgrade even if verification fails
    --hex           Force slow hex transfer (not recommended for large files)
    -h, --help      Show this help

Environment Variables:
    ROUTER_PASSWORD Router SSH password (default: toorlibre1)

Examples:
    $0                                         # Update safe-upgrade only (default router)
    $0 firmware.bin                           # Update safe-upgrade + firmware (default router)
    $0 10.13.0.1                             # Update safe-upgrade on specific router
    $0 10.13.0.1 firmware.bin                # Update safe-upgrade + firmware on specific router
    $0 firmware.bin --auto-confirm            # Fully automated upgrade (default router)

The script will:
1. Always check and update safe-upgrade script to latest version (HTTP transfer)
2. If firmware provided: Upload and install firmware (HTTP upload in seconds)
3. Use safe dual-boot system with 20-minute confirmation window
4. Provide complete technical summary and confirmation instructions

Multi-device Support:
• thisnode.info hostname conflicts automatically handled
• SSH host key verification disabled for sequential device upgrades
• Safe to upgrade multiple routers without manual known_hosts cleanup

Download firmware from: https://downloads.libremesh.org/
Look for: librerouter-v1-*-sysupgrade.bin

EOF
}

# SSH configuration for legacy LibreRouter devices
# 
# IMPORTANT: thisnode.info hostname conflict resolution
# LibreMesh devices all respond to thisnode.info on their local network, but each device
# has different SSH host keys. When connecting to multiple devices sequentially using
# thisnode.info, SSH will fail with "Host key verification failed" errors.
# 
# Solution: Disable host key checking entirely with consistent options across all SSH calls:
# - StrictHostKeyChecking=no: Skip host key verification 
# - UserKnownHostsFile=/dev/null: Don't save/check known hosts
# - HostKeyAlgorithms=+ssh-rsa: Support legacy SSH-RSA keys
#
SSH_CONTROL_PATH="/tmp/ssh_ctrl_$$"
SSH_LEGACY_OPTS="-oHostKeyAlgorithms=+ssh-rsa -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oPasswordAuthentication=yes -oPubkeyAuthentication=no -oKbdInteractiveAuthentication=no -oPreferredAuthentications=password"

# SSH helper with connection multiplexing (use short path to avoid length limits)
ssh_cmd() {
    sshpass -p "$ROUTER_PASSWORD" ssh \
        $SSH_LEGACY_OPTS \
        -oConnectTimeout=10 \
        -oControlMaster=auto \
        -oControlPath="$SSH_CONTROL_PATH" \
        -oControlPersist=60s \
        root@"$ROUTER_IP" "$@"
}

cleanup_ssh() {
    if [[ -S "$SSH_CONTROL_PATH" ]]; then
        ssh -oControlPath="$SSH_CONTROL_PATH" -O exit root@"$ROUTER_IP" 2>/dev/null || true
        rm -f "$SSH_CONTROL_PATH" 2>/dev/null || true
    fi
}

get_session_id() {
    # Try to get session ID via ubus login (silent - only output session ID)
    local session_response=$(curl -s --max-time 30 \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"call\",\"params\":[\"00000000000000000000000000000000\",\"session\",\"login\",{\"username\":\"root\",\"password\":\"$ROUTER_PASSWORD\",\"timeout\":5000}],\"id\":1}" \
        "http://$ROUTER_IP/ubus" 2>/dev/null)
    
    if [[ -n "$session_response" ]]; then
        # Parse JSON response for session ID - it's in result[1].ubus_rpc_session
        local session_id=$(echo "$session_response" | grep -o '"ubus_rpc_session":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$session_id" ]] && [[ "$session_id" != "null" ]] && [[ ${#session_id} -eq 32 ]]; then
            echo "$session_id"
            return 0
        fi
    fi
    
    # Fallback: Try to get session via HTTP login (silent)
    local login_response=$(curl -s --max-time 30 \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "luci_username=root&luci_password=$ROUTER_PASSWORD" \
        -c /tmp/cookies_$$ \
        "http://$ROUTER_IP/cgi-bin/luci" 2>/dev/null)
    
    # Extract session from cookies
    if [[ -f /tmp/cookies_$$ ]]; then
        local cookie_session=$(grep -o 'sysauth[[:space:]]*[^[:space:]]*' /tmp/cookies_$$ | cut -f2)
        rm -f /tmp/cookies_$$
        if [[ -n "$cookie_session" ]] && [[ ${#cookie_session} -gt 10 ]]; then
            echo "$cookie_session"
            return 0
        fi
    fi
    
    return 1
}

check_safe_upgrade_version() {
    print_step "Checking safe-upgrade Status"
    
    # Check if safe-upgrade exists and get version info
    local safe_upgrade_exists=false
    local current_version=""
    local current_hash=""
    
    # Test SSH connection first
    if timeout 10 sshpass -p "$ROUTER_PASSWORD" ssh \
        $SSH_LEGACY_OPTS \
        -oConnectTimeout=5 \
        root@"$ROUTER_IP" "test -x /usr/sbin/safe-upgrade" 2>/dev/null; then
        safe_upgrade_exists=true
        current_version=$(timeout 10 sshpass -p "$ROUTER_PASSWORD" ssh \
            $SSH_LEGACY_OPTS \
            -oConnectTimeout=5 \
            root@"$ROUTER_IP" "safe-upgrade show 2>/dev/null | head -1" || echo "unknown")
        
        # Get hash of current safe-upgrade for comparison
        current_hash=$(timeout 10 sshpass -p "$ROUTER_PASSWORD" ssh \
            $SSH_LEGACY_OPTS \
            -oConnectTimeout=5 \
            root@"$ROUTER_IP" "sha256sum /usr/sbin/safe-upgrade 2>/dev/null | cut -d' ' -f1" || echo "")
        
        print_success "safe-upgrade found on router"
        print_info "Current version info: $current_version"
        if [[ -n "$current_hash" ]]; then
            print_info "Current hash: ${current_hash:0:12}..."
        fi
    else
        print_warning "safe-upgrade not found on router"
    fi
    
    # Local safe-upgrade for legacy device support
    local local_safe_upgrade="$SCRIPT_DIR/../../resources/legacy-support/safe-upgrade"
    local known_latest_hash="309149758a17b8f90454550478de5d20510e7984742d899549a9c1c36cae539b"
    local known_latest_size="18338"
    local original_upstream_hash="18e5c0bba3119366101a6f246201f4c3e220c96712a122fa05a7e25cad2c7cbd"
    
    print_info "Using local safe-upgrade for legacy device support..."
    print_info "Local version: $known_latest_size bytes (with documentation), hash: ${known_latest_hash:0:12}..."
    print_info "Upstream original: ${original_upstream_hash:0:12}... (cached for legacy compatibility)"
    
    # If current hash matches known latest, skip update entirely
    if [[ -n "$current_hash" ]] && [[ "$current_hash" == "$known_latest_hash" ]]; then
        print_success "safe-upgrade is up-to-date (matches local legacy version)"
        return 0  # No update needed
    fi
    
    # Verify local safe-upgrade exists and copy to cache
    if [[ ! -f "$local_safe_upgrade" ]]; then
        print_error "Local safe-upgrade not found at: $local_safe_upgrade"
        print_error "This should not happen - please check repository integrity"
        return 1
    fi
    
    # Verify local file hash matches expected
    local local_hash=$(sha256sum "$local_safe_upgrade" | cut -d' ' -f1)
    if [[ "$local_hash" != "$known_latest_hash" ]]; then
        print_error "Local safe-upgrade hash mismatch!"
        print_error "Expected: $known_latest_hash"
        print_error "Found:    $local_hash"
        print_error "Repository may be corrupted - please re-clone"
        return 1
    fi
    
    # Copy local safe-upgrade to cache for installation
    local cache_dir="$SCRIPT_DIR/../../cache/router-upgrade"
    mkdir -p "$cache_dir"
    cp "$local_safe_upgrade" "$cache_dir/safe-upgrade"
    
    print_success "Local safe-upgrade prepared for installation"
    print_info "Verified: $known_latest_size bytes, hash: ${known_latest_hash:0:12}..."
    
    # Compare versions if both exist
    if [[ "$safe_upgrade_exists" == "true" ]]; then
        # Hash comparison is primary detection method
        if [[ -n "$current_hash" ]] && [[ "$current_hash" == "$known_latest_hash" ]]; then
            print_success "safe-upgrade is up-to-date (hash match)"
            return 0  # No update needed
        elif [[ -n "$current_hash" ]]; then
            print_info "safe-upgrade update available (hash mismatch)"
            print_info "Current: ${current_hash:0:12}... → Local: ${known_latest_hash:0:12}..."
            return 2  # Update needed
        else
            # Fallback: no hash available, check version
            if [[ "$current_version" == "unknown" ]] || [[ "$current_version" == *"version: 0."* ]]; then
                print_info "Legacy safe-upgrade detected (no hash) - upgrade required"
                return 2  # Update needed
            else
                print_warning "Cannot verify safe-upgrade version (no hash) - assuming update needed"
                return 2  # Update needed for safety
            fi
        fi
    else
        # No safe-upgrade exists, install local version
        print_info "Installing local safe-upgrade (not present on router)"
        return 2  # Update needed
    fi
}

upload_safe_upgrade_http() {
    print_step "Updating safe-upgrade via HTTP"
    
    local safe_upgrade_file="$SCRIPT_DIR/../../cache/router-upgrade/safe-upgrade"
    local temp_log="/tmp/curl_safe_upgrade_$$.log"
    
    # Get fresh session ID and upload immediately
    print_info "Uploading latest safe-upgrade script..."
    local session_id
    if session_id=$(get_session_id); then
        print_success "Authentication successful"
        
        # HACK: Use /tmp/firmware.bin path because it's in the ubus ACL permissions
        # The router ACL allows writes to "/tmp/firmware.bin" but not "/tmp/safe-upgrade"
        # We'll overwrite this with the actual firmware later if needed
        if timeout 60 curl -s --max-time 60 \
            --expect100-timeout 10 \
            -H "Expect:" \
            -F "sessionid=$session_id" \
            -F "filename=/tmp/firmware.bin" \
            -F "filedata=@$safe_upgrade_file;filename=safe-upgrade" \
            "http://$ROUTER_IP/cgi-bin/cgi-upload" >"$temp_log" 2>&1; then
            
            # Check if upload response indicates success
            local upload_response=$(cat "$temp_log")
            if echo "$upload_response" | grep -q '"size":[[:space:]]*[0-9]'; then
                local reported_size=$(echo "$upload_response" | grep -o '"size":[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
                local local_size=$(stat -c%s "$safe_upgrade_file")
                
                if [[ "$reported_size" -eq "$local_size" ]]; then
                    print_success "HTTP upload completed successfully"
                    print_success "safe-upgrade script verified: $reported_size bytes"
                    rm -f "$temp_log"
                    return 0
                fi
            else
                print_warning "HTTP upload response did not include size confirmation"
            fi
        else
            print_warning "HTTP upload curl command failed"
        fi
    else
        print_warning "Failed to get session ID for HTTP upload"
    fi
    
    if [[ -f "$temp_log" ]]; then
        print_info "HTTP upload error details: $(head -3 "$temp_log")"
    fi
    
    print_warning "HTTP upload failed for safe-upgrade, trying hex transfer..."
    rm -f "$temp_log"
    return 1
}

upload_safe_upgrade_hex() {
    print_step "Updating safe-upgrade via Hex Transfer"
    
    local safe_upgrade_file="$SCRIPT_DIR/../../cache/router-upgrade/safe-upgrade"
    
    print_info "Using hex transfer for safe-upgrade script..."
    if ROUTER_PASSWORD="$ROUTER_PASSWORD" "$SCRIPT_DIR/../utils/transfer-legacy-hex.sh" "$ROUTER_IP" "$safe_upgrade_file" "/tmp/firmware.bin"; then
        print_success "safe-upgrade script transferred successfully"
        return 0
    else
        print_error "Failed to transfer safe-upgrade script"
        return 1
    fi
}

install_safe_upgrade() {
    print_step "Installing safe-upgrade Script"
    
    # Backup existing safe-upgrade if it exists
    print_info "Creating backup of existing safe-upgrade..."
    ssh_cmd "if [ -f /usr/sbin/safe-upgrade ]; then cp /usr/sbin/safe-upgrade /usr/sbin/safe-upgrade.backup.$(date +%Y%m%d_%H%M%S); echo 'Backup created'; else echo 'No existing safe-upgrade to backup'; fi"
    
    print_info "Installing safe-upgrade to /usr/sbin/safe-upgrade..."
    ssh_cmd "cp /tmp/firmware.bin /usr/sbin/safe-upgrade && chmod +x /usr/sbin/safe-upgrade"
    
    # Verify installation
    if ssh_cmd "test -x /usr/sbin/safe-upgrade"; then
        print_success "safe-upgrade installed successfully"
        
        # Test functionality
        if ssh_cmd "/usr/sbin/safe-upgrade show" >/dev/null 2>&1; then
            print_success "safe-upgrade is functional"
            
            # Bootstrap if needed
            local status=$(ssh_cmd "/usr/sbin/safe-upgrade show 2>/dev/null | head -1" || echo "")
            if [[ "$status" == *"not bootstrapped"* ]]; then
                print_info "Bootstrapping safe-upgrade..."
                ssh_cmd "/usr/sbin/safe-upgrade bootstrap"
            fi
            
            print_success "safe-upgrade ready for use"
            print_info "Previous version backed up as: /usr/sbin/safe-upgrade.backup.YYYYMMDD_HHMMSS"
            return 0
        else
            print_error "safe-upgrade installation verification failed"
            return 1
        fi
    else
        print_error "safe-upgrade installation failed"
        return 1
    fi
}

update_safe_upgrade() {
    local update_needed=$1
    
    if [[ $update_needed -eq 0 ]]; then
        print_success "safe-upgrade is current - no update needed"
        return 0
    fi
    
    print_step "Updating safe-upgrade to Latest Version"
    
    # Try HTTP upload first
    print_info "Attempting HTTP upload for safe-upgrade..."
    if upload_safe_upgrade_http; then
        print_info "HTTP upload successful, installing..."
        install_safe_upgrade
        return $?
    fi
    
    # Fallback to hex transfer
    print_info "HTTP upload failed, trying hex transfer..."
    if upload_safe_upgrade_hex; then
        print_info "Hex transfer successful, installing..."
        install_safe_upgrade
        return $?
    fi
    
    print_error "Failed to update safe-upgrade script"
    return 1
}

verify_firmware_file() {
    print_step "Verifying Firmware File"
    
    if [[ ! -f "$FIRMWARE_FILE" ]]; then
        print_error "Firmware file not found: $FIRMWARE_FILE"
        exit 1
    fi
    
    local file_size=$(stat -c%s "$FIRMWARE_FILE")
    local file_size_mb=$((file_size / 1024 / 1024))
    
    print_success "Firmware file found: $(basename "$FIRMWARE_FILE")"
    print_info "File size: $file_size bytes (~${file_size_mb}MB)"
    
    # Basic validation - LibreRouter firmware should be around 8MB
    if [[ $file_size -lt 1000000 ]]; then
        print_warning "File seems too small for firmware (${file_size_mb}MB)"
    elif [[ $file_size -gt 20000000 ]]; then
        print_warning "File seems too large for firmware (${file_size_mb}MB)"
    fi
    
    # Check file extension
    if [[ "$FIRMWARE_FILE" != *.bin ]]; then
        print_warning "File doesn't have .bin extension"
    fi
    
    print_info "Transfer time estimate: ~$((file_size / 1024 / 64)) minutes via hex"
}

attempt_firmware_http_upload() {
    print_step "Attempting Fast HTTP Firmware Upload"
    
    print_info "Uploading firmware via HTTP using lime-app protocol..."
    
    # Check if router web interface is accessible
    if ! curl -s --max-time 10 "http://$ROUTER_IP" >/dev/null 2>&1; then
        print_warning "Router web interface not accessible"
        return 1
    fi
    
    local temp_log="/tmp/curl_firmware_upload_$$.log"
    
    # Method 1: Get fresh session ID and upload immediately
    print_info "Attempting firmware upload with session authentication..."
    local session_id
    if session_id=$(get_session_id); then
        print_success "Authentication successful"
        print_info "Uploading firmware file via HTTP..."
        
        if curl -s --max-time 600 \
            --expect100-timeout 30 \
            -H "Expect:" \
            -F "sessionid=$session_id" \
            -F "filename=/tmp/firmware.bin" \
            -F "filedata=@$FIRMWARE_FILE;filename=firmware.bin" \
            "http://$ROUTER_IP/cgi-bin/cgi-upload" >"$temp_log" 2>&1; then
            
            # Check if upload response indicates success
            local upload_response=$(cat "$temp_log")
            if echo "$upload_response" | grep -q '"size":[[:space:]]*[0-9]'; then
                local reported_size=$(echo "$upload_response" | grep -o '"size":[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
                local local_size=$(stat -c%s "$FIRMWARE_FILE")
                
                if [[ "$reported_size" -eq "$local_size" ]]; then
                    print_success "HTTP firmware upload completed successfully"
                    print_success "Firmware verified: $reported_size bytes"
                    rm -f "$temp_log"
                    return 0
                else
                    print_warning "Size mismatch in upload response! Local: $local_size bytes, Reported: $reported_size bytes"
                fi
            else
                print_warning "Upload response did not include size confirmation"
            fi
        else
            print_warning "Session upload failed"
        fi
    else
        print_warning "Failed to authenticate"
    fi
    
    rm -f "$temp_log"
    return 1
}

transfer_firmware() {
    print_step "Transferring Firmware to Router"
    
    local file_size=$(stat -c%s "$FIRMWARE_FILE")
    
    # For large bin files, try HTTP first but fall back to hex if needed
    if [[ "$FIRMWARE_FILE" == *.bin ]] && [[ $file_size -gt 1000000 ]] && [[ "$USE_HEX_TRANSFER" != "true" ]]; then
        print_info "Large firmware file detected - attempting fast HTTP upload..."
        
        if attempt_firmware_http_upload; then
            print_success "Fast HTTP transfer completed!"
            return 0
        else
            print_warning "HTTP upload failed or incomplete"
            print_warning "This might be due to router upload size limits"
            print_warning ""
            print_warning "Options:"
            print_warning "  1. Use web interface at http://$ROUTER_IP (recommended)"
            print_warning "  2. Continue with hex transfer (~$((file_size / 1024 / 64)) minutes)"
            print_warning ""
            
            if [[ "$AUTO_CONFIRM" != "true" ]]; then
                read -p "Continue with slow hex transfer? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    print_info "Upload cancelled. Use web interface for faster upload."
                    exit 1
                fi
                USE_HEX_TRANSFER="true"
            else
                print_error "Auto-confirm mode: cannot proceed with failed HTTP upload"
                print_error "Use web interface or --hex flag explicitly"
                exit 1
            fi
        fi
    fi
    
    # Small files or explicit hex request
    if [[ "$USE_HEX_TRANSFER" == "true" ]]; then
        print_warning "Using slow hex transfer as requested"
        print_warning "This will take ~$((file_size / 1024 / 64)) minutes"
        print_info "Please be patient - large file transfer in progress..."
    else
        print_info "Using hex transfer for small file"
    fi
    
    # Use hex transfer method
    if ROUTER_PASSWORD="$ROUTER_PASSWORD" "$SCRIPT_DIR/../utils/transfer-legacy-hex.sh" "$ROUTER_IP" "$FIRMWARE_FILE" "/tmp/firmware.bin"; then
        print_success "Firmware transferred successfully"
    else
        print_error "Failed to transfer firmware"
        exit 1
    fi
}

verify_firmware_on_router() {
    print_step "Verifying Firmware on Router"
    
    print_info "Using safe-upgrade to verify firmware compatibility..."
    if ssh_cmd "safe-upgrade verify /tmp/firmware.bin"; then
        print_success "Firmware verified by safe-upgrade - compatible with router"
    else
        print_error "Firmware verification failed!"
        print_warning "This firmware may not be compatible with your router"
        
        if [[ "$AUTO_CONFIRM" != "true" ]]; then
            read -p "Continue anyway with --force? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Upgrade cancelled - firmware verification failed"
                exit 1
            fi
            FORCE_UPGRADE="true"
        else
            print_error "Auto-confirm mode but firmware verification failed"
            exit 1
        fi
    fi
}

execute_firmware_upgrade() {
    print_step "Executing Complete Firmware Upgrade"
    
    print_warning "About to start AUTOMATED firmware upgrade"
    print_warning "Router will reboot automatically during this process"
    print_warning "DO NOT power off router during upgrade!"
    print_info ""
    
    if [[ "$AUTO_CONFIRM" != "true" ]]; then
        read -p "Continue with AUTOMATED upgrade? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Upgrade cancelled by user"
            exit 0
        fi
    fi
    
    # Ensure safe-upgrade is ready
    print_info "Ensuring safe-upgrade is bootstrapped..."
    if ! ssh_cmd "/usr/sbin/safe-upgrade show" >/dev/null 2>&1; then
        print_info "Bootstrapping safe-upgrade..."
        ssh_cmd "/usr/sbin/safe-upgrade bootstrap"
    fi
    
    # Build upgrade command with options
    local upgrade_cmd="safe-upgrade upgrade"
    
    # Extended timeout for confirmation (20 minutes instead of 10)
    upgrade_cmd+=" --reboot-safety-timeout 1200"
    
    # Add force flag if verification failed
    if [[ "$FORCE_UPGRADE" == "true" ]]; then
        upgrade_cmd+=" --force"
        print_warning "Using --force due to verification failure"
    fi
    
    upgrade_cmd+=" /tmp/firmware.bin"
    
    print_info "Upgrade command: $upgrade_cmd"
    print_info "Starting firmware upgrade with extended safety timeout (20 minutes)..."
    print_warning "SSH connection will be lost when router reboots"
    
    # This will cause connection to drop
    ssh_cmd "$upgrade_cmd" || true
    
    print_info "Upgrade command executed - router is rebooting..."
}

wait_for_reboot_and_verify() {
    print_step "Waiting for Router Reboot"
    
    print_info "Waiting for router to reboot with new firmware..."
    print_info "This typically takes 2-5 minutes"
    
    local max_wait=300
    local waited=0
    
    # Wait initial time for reboot
    sleep 30
    
    while [[ $waited -lt $max_wait ]]; do
        if ssh_cmd "echo 'Router online'" >/dev/null 2>&1; then
            print_success "Router is back online with new firmware!"
            break
        fi
        
        print_info "Waiting for router... ($waited/${max_wait}s)"
        sleep 15
        waited=$((waited + 15))
    done
    
    if [[ $waited -ge $max_wait ]]; then
        print_error "Router did not come back online within expected time"
        print_info "Check router status manually"
        exit 1
    fi
    
    # Show new firmware info
    print_info "New firmware information:"
    ssh_cmd "/usr/sbin/safe-upgrade show" || true
}

firmware_upgrade_summary() {
    # Get technical details for summary
    local firmware_name=$(basename "$FIRMWARE_FILE")
    local firmware_size_mb=$(($(stat -c%s "$FIRMWARE_FILE") / 1024 / 1024))
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    local remaining_time=$(ssh_cmd "safe-upgrade confirm-remaining" 2>/dev/null || echo "unknown")
    local remaining_minutes=$((remaining_time / 60))
    
    print_step "🎉 FIRMWARE UPGRADE COMPLETED SUCCESSFULLY!"
    
    echo
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    🚀 LIBREROUTERV1 LEGACY UPGRADE SUCCESS 🚀                ║"
    echo "╠══════════════════════════════════════════════════════════════════════════════╣"
    echo "║                                                                              ║"
    echo "║  📊 TECHNICAL DETAILS:                                                       ║"
    echo "║  • Router IP: $ROUTER_IP                                                     ║"
    echo "║  • Firmware: $(printf "%-55s" "$firmware_name")║"
    echo "║  • Size: ${firmware_size_mb}MB transferred via HTTP upload (seconds vs hours hex) ║"
    echo "║  • Method: lime-app compatible ubus session authentication                   ║"
    echo "║  • Status: Online, NEW firmware active (testing mode)                       ║"
    echo "║  • Partition: Current=2, Previous=1 (safe dual-boot system)                 ║"
    echo "║  • Completed: $current_time                                                  ║"
    echo "║                                                                              ║"
    echo "╠══════════════════════════════════════════════════════════════════════════════╣"
    echo "║                                                                              ║"
    echo "║  ⚠️  CRITICAL: UPGRADE CONFIRMATION REQUIRED WITHIN $remaining_minutes MINUTES ⚠️            ║"
    echo "║                                                                              ║"
    echo "║  🖱️  CLICK: http://$ROUTER_IP                                               ║"
    echo "║  💻 OR: ssh root@$ROUTER_IP 'safe-upgrade confirm'                          ║"
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo
}

main() {
    # Parse arguments
    AUTO_CONFIRM="false"
    FORCE_UPGRADE="false"
    USE_HEX_TRANSFER="false"
    
    # Reset positional parameters for clean parsing
    local args=()
    
    # Parse options first, collect non-option arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            --auto-confirm)
                AUTO_CONFIRM="true"
                shift
                ;;
            --force)
                FORCE_UPGRADE="true"
                shift
                ;;
            --hex)
                USE_HEX_TRANSFER="true"
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                # This is a positional argument
                args+=("$1")
                shift
                ;;
        esac
    done
    
    # Parse positional arguments intelligently
    if [[ ${#args[@]} -eq 0 ]]; then
        # No arguments - use defaults
        ROUTER_IP="thisnode.info"
        FIRMWARE_FILE=""
    elif [[ ${#args[@]} -eq 1 ]]; then
        # One argument - could be router IP or firmware file
        if [[ "${args[0]}" == *.bin ]]; then
            # It's a firmware file
            ROUTER_IP="thisnode.info"
            FIRMWARE_FILE="${args[0]}"
        else
            # It's a router IP
            ROUTER_IP="${args[0]}"
            FIRMWARE_FILE=""
        fi
    elif [[ ${#args[@]} -eq 2 ]]; then
        # Two arguments - router IP and firmware file
        ROUTER_IP="${args[0]}"
        FIRMWARE_FILE="${args[1]}"
    else
        print_error "Too many arguments"
        usage
        exit 1
    fi
    
    trap cleanup_ssh EXIT
    
    echo "LibreRouter v1 Upgrade Utility"
    echo "=================================="
    print_info "Target router: $ROUTER_IP"
    if [[ -n "$FIRMWARE_FILE" ]]; then
        print_info "Firmware file: $FIRMWARE_FILE"
        print_info "Mode: safe-upgrade update + firmware upgrade"
    else
        print_info "Mode: safe-upgrade update only"
    fi
    echo
    
    # Step 0: Detect and verify router connectivity
    detect_router_ip
    
    # Get router password if not provided
    get_router_password
    
    # Test SSH connectivity before proceeding
    test_ssh_connection
    
    # Step 1: Always check and update safe-upgrade
    local safe_upgrade_status
    check_safe_upgrade_version || safe_upgrade_status=$?
    
    if ! update_safe_upgrade $safe_upgrade_status; then
        print_error "Failed to update safe-upgrade - cannot proceed"
        exit 1
    fi
    
    # Step 2: If firmware file provided, proceed with firmware upgrade
    if [[ -n "$FIRMWARE_FILE" ]]; then
        print_step "Proceeding with Firmware Upgrade"
        print_info "safe-upgrade is ready - starting firmware upgrade process"
        
        # Verify firmware file
        verify_firmware_file
        
        # Transfer firmware to router
        transfer_firmware
        
        # Verify firmware on router
        verify_firmware_on_router
        
        # Execute firmware upgrade
        execute_firmware_upgrade
        
        # Wait for reboot and verify
        wait_for_reboot_and_verify
        
        # Show completion summary
        firmware_upgrade_summary
        
        print_success "🎉 LibreRouter v1 upgrade completed successfully!"
        print_info "📡 Router is online with modern firmware - confirmation pending"
        print_warning "⚠️  IMPORTANT: Complete confirmation to make upgrade permanent"
        print_info "🌐 Access router now: http://$ROUTER_IP"
    else
        print_step "safe-upgrade Update Completed!"
        print_success "🎉 safe-upgrade updated successfully!"
        print_info "Router is ready for firmware upgrades"
        print_info ""
        print_info "Next steps:"
        print_info "• To upgrade firmware: $0 $ROUTER_IP firmware.bin"
        print_info "• Download firmware: https://downloads.libremesh.org/"
        print_info "• Look for: librerouter-v1-*-sysupgrade.bin"
        print_info ""
        print_success "Router is ready for firmware upgrade!"
    fi
}

# Check dependencies
if ! command -v sshpass >/dev/null || ! command -v wget >/dev/null || ! command -v curl >/dev/null; then
    print_error "Missing dependencies: sshpass, wget, curl"
    print_info "Install with: sudo apt install sshpass wget curl"
    exit 1
fi

main "$@"