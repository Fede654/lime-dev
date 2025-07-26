#!/usr/bin/env bash
#
# QEMU LibreMesh/LibreRouterOS Image Diagnostic Tool
# 
# This script performs comprehensive diagnostics on booted QEMU VMs to determine
# image condition, service availability, and functionality completeness.
#
# Usage: ./qemu-diagnostics.sh [options]
#
# Options:
#   --vm-ip IP          Target VM IP address (default: 10.13.0.1)
#   --screen-name NAME  Screen session name (default: libremesh)
#   --timeout SECONDS   Test timeout in seconds (default: 30)
#   --verbose           Enable verbose output
#   --json              Output results in JSON format
#   --help              Show this help message
#
# Exit codes:
#   0 - All tests passed (image fully functional)
#   1 - Critical failures (image unusable)
#   2 - Partial functionality (some services missing)
#   3 - Network connectivity issues
#   4 - Script execution errors

set -euo pipefail

# Default configuration
VM_IP="10.13.0.1"
SCREEN_NAME="libremesh"
TIMEOUT=30
VERBOSE=false
JSON_OUTPUT=false
MONITOR_PORT="45400"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results storage
declare -A TEST_RESULTS
declare -A TEST_DETAILS
OVERALL_STATUS="UNKNOWN"
EXIT_CODE=0

# Logging functions
log_info() {
    if [[ "$VERBOSE" == "true" || "$1" == "ALWAYS" ]]; then
        echo -e "${BLUE}[INFO]${NC} $2" >&2
    fi
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

# Helper functions
usage() {
    grep '^#' "$0" | tail -n +3 | head -n -1 | cut -c 3-
}

cleanup() {
    # Clean up temporary files
    rm -f /tmp/qemu_diag_*.log /tmp/qemu_diag_*.tmp 2>/dev/null || true
}

trap cleanup EXIT

# Send command to QEMU console via screen
send_console_command() {
    local cmd="$1"
    local wait_time="${2:-2}"
    
    if ! sudo screen -S "$SCREEN_NAME" -X stuff "$cmd"$'\n' 2>/dev/null; then
        log_error "Failed to send command to screen session '$SCREEN_NAME'"
        return 1
    fi
    
    sleep "$wait_time"
    return 0
}

# Capture console output
capture_console() {
    local output_file="$1"
    sudo screen -S "$SCREEN_NAME" -X hardcopy "$output_file" 2>/dev/null || return 1
    return 0
}

# Test: Basic network connectivity
test_network_connectivity() {
    log_info VERBOSE "Testing network connectivity to $VM_IP"
    
    local ping_result
    if ping_result=$(ping -c 3 -W 5 "$VM_IP" 2>&1); then
        TEST_RESULTS[network_ping]="PASS"
        TEST_DETAILS[network_ping]="Ping successful"
        log_success "Network connectivity: PASS"
        return 0
    else
        TEST_RESULTS[network_ping]="FAIL"
        TEST_DETAILS[network_ping]="Ping failed: $ping_result"
        log_error "Network connectivity: FAIL"
        return 1
    fi
}

# Test: Port availability
test_port_availability() {
    log_info VERBOSE "Testing port availability"
    
    local nmap_result
    if command -v nmap >/dev/null 2>&1; then
        nmap_result=$(nmap -p 22,80,443 "$VM_IP" 2>/dev/null | grep -E "22/tcp|80/tcp|443/tcp" || true)
    else
        # Fallback to nc if nmap not available
        local ports=("22" "80" "443")
        nmap_result=""
        for port in "${ports[@]}"; do
            if timeout 3 nc -z "$VM_IP" "$port" 2>/dev/null; then
                nmap_result+="$port/tcp open"$'\n'
            else
                nmap_result+="$port/tcp closed"$'\n'
            fi
        done
    fi
    
    # Analyze port results
    local ssh_status="CLOSED"
    local http_status="CLOSED"
    local https_status="CLOSED"
    
    if echo "$nmap_result" | grep -q "22/tcp.*open"; then
        ssh_status="OPEN"
    fi
    if echo "$nmap_result" | grep -q "80/tcp.*open"; then
        http_status="OPEN"
    fi
    if echo "$nmap_result" | grep -q "443/tcp.*open"; then
        https_status="OPEN"
    fi
    
    TEST_RESULTS[port_ssh]="$ssh_status"
    TEST_RESULTS[port_http]="$http_status"
    TEST_RESULTS[port_https]="$https_status"
    TEST_DETAILS[port_scan]="SSH:$ssh_status HTTP:$http_status HTTPS:$https_status"
    
    log_info ALWAYS "Port Status - SSH:$ssh_status HTTP:$http_status HTTPS:$https_status"
}

# Test: Console accessibility
test_console_access() {
    log_info VERBOSE "Testing console access via screen session"
    
    if sudo screen -list | grep -q "$SCREEN_NAME"; then
        TEST_RESULTS[console_access]="PASS"
        TEST_DETAILS[console_access]="Screen session active"
        log_success "Console access: PASS"
        
        # Try to activate console
        if send_console_command "" 1; then
            TEST_RESULTS[console_interactive]="PASS"
            TEST_DETAILS[console_interactive]="Console responds to input"
        else
            TEST_RESULTS[console_interactive]="FAIL"
            TEST_DETAILS[console_interactive]="Console unresponsive"
        fi
        return 0
    else
        TEST_RESULTS[console_access]="FAIL"
        TEST_DETAILS[console_access]="No screen session found"
        log_error "Console access: FAIL - No screen session '$SCREEN_NAME'"
        return 1
    fi
}

# Test: System information gathering
test_system_info() {
    log_info VERBOSE "Gathering system information"
    
    local console_log="/tmp/qemu_diag_sysinfo.log"
    
    # Send system info commands
    send_console_command "uname -a" 2
    send_console_command "cat /etc/banner 2>/dev/null || echo 'No banner'" 2
    send_console_command "uptime" 1
    
    if capture_console "$console_log"; then
        local system_info
        system_info=$(tail -10 "$console_log" | grep -v "Please press Enter" || true)
        
        # Extract key information
        local os_version="Unknown"
        local uptime_info="Unknown"
        
        if echo "$system_info" | grep -q "LibreMesh\|LibreRouterOS\|OpenWrt"; then
            os_version=$(echo "$system_info" | grep -E "LibreMesh|LibreRouterOS|OpenWrt" | head -1 | sed 's/.*-//' | tr -d '\r\n')
        fi
        
        if echo "$system_info" | grep -q "up"; then
            uptime_info=$(echo "$system_info" | grep "up" | head -1 | tr -d '\r\n')
        fi
        
        TEST_RESULTS[system_info]="PASS"
        TEST_DETAILS[system_version]="$os_version"
        TEST_DETAILS[system_uptime]="$uptime_info"
        
        log_success "System info: $os_version"
        return 0
    else
        TEST_RESULTS[system_info]="FAIL"
        TEST_DETAILS[system_info]="Could not capture system information"
        return 1
    fi
}

# Test: Service availability
test_services() {
    log_info VERBOSE "Testing service availability"
    
    local console_log="/tmp/qemu_diag_services.log"
    
    # Test uhttpd availability
    send_console_command "which uhttpd" 2
    send_console_command "ls -la /usr/sbin/uhttpd 2>/dev/null || echo 'uhttpd not found'" 2
    send_console_command "/etc/init.d/uhttpd status 2>/dev/null || echo 'uhttpd service unavailable'" 2
    
    # Test ubus availability
    send_console_command "which ubus" 2
    send_console_command "/etc/init.d/ubus status 2>/dev/null || echo 'ubus service unavailable'" 2
    
    # Test package information
    send_console_command "opkg list-installed | grep -E '(uhttpd|luci|ubus)' | head -5" 3
    
    if capture_console "$console_log"; then
        local service_info
        service_info=$(tail -20 "$console_log" | grep -v "Please press Enter" || true)
        
        # Analyze service availability
        local uhttpd_binary="NOT_FOUND"
        local uhttpd_service="UNAVAILABLE"
        local ubus_available="NO"
        local luci_packages="NONE"
        
        if echo "$service_info" | grep -q "/usr/sbin/uhttpd"; then
            uhttpd_binary="FOUND"
        fi
        
        if echo "$service_info" | grep -q "running\|started"; then
            uhttpd_service="RUNNING"
        elif echo "$service_info" | grep -q "stopped\|inactive"; then
            uhttpd_service="STOPPED"
        fi
        
        if echo "$service_info" | grep -q "ubus.*-"; then
            ubus_available="YES"
        fi
        
        local luci_count=0
        if echo "$service_info" | grep -q "luci-"; then
            luci_count=$(echo "$service_info" | grep -c "luci-")
            luci_packages="$luci_count packages"
        fi
        
        TEST_RESULTS[uhttpd_binary]="$uhttpd_binary"
        TEST_RESULTS[uhttpd_service]="$uhttpd_service"
        TEST_RESULTS[ubus_available]="$ubus_available"
        TEST_RESULTS[luci_packages]="$luci_packages"
        
        TEST_DETAILS[service_analysis]="uhttpd:$uhttpd_binary/$uhttpd_service ubus:$ubus_available luci:$luci_packages"
        
        log_info ALWAYS "Services - uhttpd:$uhttpd_binary/$uhttpd_service ubus:$ubus_available luci:$luci_packages"
        return 0
    else
        TEST_RESULTS[services]="FAIL"
        TEST_DETAILS[services]="Could not capture service information"
        return 1
    fi
}

# Test: Web interface functionality
test_web_interface() {
    log_info VERBOSE "Testing web interface functionality"
    
    local curl_result
    local web_status="FAIL"
    local web_details="No response"
    
    # Test HTTP connectivity
    if curl_result=$(curl -s --connect-timeout 10 --max-time 15 "http://$VM_IP/" 2>&1); then
        if [[ -n "$curl_result" ]] && echo "$curl_result" | grep -qE "(html|LuCI|LibreMesh|lime-app)"; then
            web_status="PASS"
            web_details="Web interface responding"
            if echo "$curl_result" | grep -q "LuCI"; then
                web_details="LuCI interface active"
            elif echo "$curl_result" | grep -q "lime-app"; then
                web_details="lime-app interface active"
            fi
        else
            web_status="PARTIAL"
            web_details="HTTP responds but no web interface"
        fi
    else
        web_details="HTTP connection failed: $curl_result"
    fi
    
    TEST_RESULTS[web_interface]="$web_status"
    TEST_DETAILS[web_interface]="$web_details"
    
    # Test lime-app specifically
    local limeapp_result
    if limeapp_result=$(curl -s --connect-timeout 5 "http://$VM_IP/app/" 2>&1); then
        if echo "$limeapp_result" | grep -qE "(html|app|lime)"; then
            TEST_RESULTS[lime_app]="PASS"
            TEST_DETAILS[lime_app]="lime-app accessible"
        else
            TEST_RESULTS[lime_app]="FAIL"
            TEST_DETAILS[lime_app]="lime-app not responding"
        fi
    else
        TEST_RESULTS[lime_app]="FAIL"
        TEST_DETAILS[lime_app]="lime-app connection failed"
    fi
    
    log_info ALWAYS "Web Interface: $web_status ($web_details)"
}

# Test: Web content availability
test_web_content() {
    log_info VERBOSE "Testing web content availability"
    
    local console_log="/tmp/qemu_diag_webcontent.log"
    
    # Check web directories and content
    send_console_command "ls -la /www/" 3
    send_console_command "ls -la /www/app/ 2>/dev/null || echo 'No lime-app directory'" 2
    send_console_command "head -3 /www/index.html 2>/dev/null || echo 'No index.html'" 2
    
    if capture_console "$console_log"; then
        local content_info
        content_info=$(tail -15 "$console_log" | grep -v "Please press Enter" || true)
        
        local www_exists="NO"
        local app_exists="NO"
        local index_exists="NO"
        
        if echo "$content_info" | grep -q "drwx.*www"; then
            www_exists="YES"
        fi
        
        if echo "$content_info" | grep -q "app.*drwx\|drwx.*app"; then
            app_exists="YES"
        fi
        
        if echo "$content_info" | grep -q "index.html\|<html\|<HTML"; then
            index_exists="YES"
        fi
        
        TEST_RESULTS[www_directory]="$www_exists"
        TEST_RESULTS[app_directory]="$app_exists"
        TEST_RESULTS[index_html]="$index_exists"
        
        TEST_DETAILS[web_content]="www:$www_exists app:$app_exists index:$index_exists"
        
        log_info ALWAYS "Web Content - www:$www_exists app:$app_exists index:$index_exists"
        return 0
    else
        TEST_RESULTS[web_content]="FAIL"
        TEST_DETAILS[web_content]="Could not check web content"
        return 1
    fi
}

# Calculate overall status
calculate_overall_status() {
    local critical_failures=0
    local warnings=0
    local total_tests=0
    
    # Critical tests that must pass
    local critical_tests=(
        "network_ping"
        "console_access"
        "system_info"
    )
    
    # Important tests (warnings if failed)
    local important_tests=(
        "uhttpd_binary"
        "web_interface"
        "port_http"
    )
    
    # Count critical failures
    for test in "${critical_tests[@]}"; do
        ((total_tests++))
        if [[ "${TEST_RESULTS[$test]:-FAIL}" == "FAIL" ]]; then
            ((critical_failures++))
        fi
    done
    
    # Count warnings
    for test in "${important_tests[@]}"; do
        ((total_tests++))
        if [[ "${TEST_RESULTS[$test]:-FAIL}" != "PASS" ]] && [[ "${TEST_RESULTS[$test]:-FAIL}" != "FOUND" ]] && [[ "${TEST_RESULTS[$test]:-FAIL}" != "OPEN" ]]; then
            ((warnings++))
        fi
    done
    
    # Determine overall status and exit code
    if [[ $critical_failures -gt 0 ]]; then
        if [[ "${TEST_RESULTS[network_ping]}" == "FAIL" ]]; then
            OVERALL_STATUS="NETWORK_FAILURE"
            EXIT_CODE=3
        else
            OVERALL_STATUS="CRITICAL_FAILURE"
            EXIT_CODE=1
        fi
    elif [[ $warnings -gt 2 ]]; then
        OVERALL_STATUS="PARTIAL_FUNCTIONALITY"
        EXIT_CODE=2
    elif [[ $warnings -gt 0 ]]; then
        OVERALL_STATUS="FUNCTIONAL_WITH_ISSUES"
        EXIT_CODE=2
    else
        OVERALL_STATUS="FULLY_FUNCTIONAL"
        EXIT_CODE=0
    fi
    
    TEST_RESULTS[overall_status]="$OVERALL_STATUS"
    TEST_DETAILS[overall_status]="Critical failures: $critical_failures, Warnings: $warnings"
}

# Generate report
generate_report() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        generate_json_report
    else
        generate_text_report
    fi
}

generate_json_report() {
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"vm_ip\": \"$VM_IP\","
    echo "  \"overall_status\": \"$OVERALL_STATUS\","
    echo "  \"exit_code\": $EXIT_CODE,"
    echo "  \"test_results\": {"
    
    local first=true
    for key in "${!TEST_RESULTS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    \"$key\": \"${TEST_RESULTS[$key]}\""
    done
    echo ""
    echo "  },"
    echo "  \"test_details\": {"
    
    first=true
    for key in "${!TEST_DETAILS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    \"$key\": \"${TEST_DETAILS[$key]}\""
    done
    echo ""
    echo "  }"
    echo "}"
}

generate_text_report() {
    echo
    echo "=========================================="
    echo "QEMU LibreMesh Diagnostic Report"
    echo "=========================================="
    echo "Timestamp: $(date)"
    echo "VM IP: $VM_IP"
    echo "Screen Session: $SCREEN_NAME"
    echo "Overall Status: $OVERALL_STATUS"
    echo
    
    echo "Test Results:"
    echo "----------------------------------------"
    printf "%-25s %-15s %s\n" "Test" "Result" "Details"
    echo "----------------------------------------"
    
    # Sort and display results
    for key in $(printf '%s\n' "${!TEST_RESULTS[@]}" | sort); do
        local result="${TEST_RESULTS[$key]}"
        local details="${TEST_DETAILS[$key]:-}"
        
        # Color code results
        local color=""
        case "$result" in
            "PASS"|"FOUND"|"OPEN"|"YES") color="$GREEN" ;;
            "FAIL"|"NOT_FOUND"|"CLOSED"|"NO") color="$RED" ;;
            "PARTIAL"|"STOPPED"|"UNAVAILABLE") color="$YELLOW" ;;
            *) color="$NC" ;;
        esac
        
        printf "%-25s ${color}%-15s${NC} %s\n" "$key" "$result" "$details"
    done
    
    echo "----------------------------------------"
    echo
    
    # Recommendations
    echo "Recommendations:"
    echo "----------------------------------------"
    
    case "$OVERALL_STATUS" in
        "NETWORK_FAILURE")
            echo "❌ Network connectivity failed. Check QEMU network configuration."
            echo "   - Verify TAP interfaces are up and bridged"
            echo "   - Check VM network settings"
            echo "   - Ensure VM has booted completely"
            ;;
        "CRITICAL_FAILURE")
            echo "❌ Critical system failures detected. Image may be corrupted or incomplete."
            echo "   - Try using a different LibreMesh image"
            echo "   - Check QEMU startup logs for errors"
            echo "   - Consider rebuilding the image"
            ;;
        "PARTIAL_FUNCTIONALITY")
            echo "⚠️  Image has partial functionality. Web services missing or incomplete."
            echo "   - uhttpd web server may not be installed"
            echo "   - Consider using a stable/recommended image"
            echo "   - For development: install missing packages manually"
            ;;
        "FUNCTIONAL_WITH_ISSUES")
            echo "✅ Image is functional with minor issues."
            echo "   - Most services working correctly"
            echo "   - Some optional features may be unavailable"
            ;;
        "FULLY_FUNCTIONAL")
            echo "✅ Image is fully functional!"
            echo "   - All critical services operational"
            echo "   - Web interface accessible"
            echo "   - Ready for development/testing"
            ;;
    esac
    
    echo "----------------------------------------"
    echo "Exit Code: $EXIT_CODE"
    echo
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vm-ip)
                VM_IP="$2"
                shift 2
                ;;
            --screen-name)
                SCREEN_NAME="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage >&2
                exit 4
                ;;
        esac
    done
    
    log_info ALWAYS "Starting QEMU LibreMesh diagnostics for $VM_IP"
    
    # Run tests in sequence
    test_network_connectivity
    test_port_availability
    test_console_access && {
        test_system_info
        test_services
        test_web_content
    }
    test_web_interface
    
    # Calculate overall status
    calculate_overall_status
    
    # Generate report
    generate_report
    
    # Exit with appropriate code
    exit $EXIT_CODE
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi