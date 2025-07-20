#!/bin/bash
#
# LibreMesh Development Security Scanner
# Practical security checks for lime-dev workflow
#
# Usage:
#   ./scripts/security/scan-secrets.sh                    # Scan all repos
#   ./scripts/security/scan-secrets.sh repos/lime-app    # Scan specific repo
#   ./scripts/security/scan-secrets.sh --quick           # Quick scan (secrets only)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCAN_PATH="${1:-$PROJECT_ROOT}"
QUICK_MODE=false
EXIT_ON_FAIL=false

if [[ "${1:-}" == "--quick" ]]; then
    QUICK_MODE=true
    SCAN_PATH="$PROJECT_ROOT"
elif [[ "${1:-}" == "--fail-fast" ]]; then
    EXIT_ON_FAIL=true
    SCAN_PATH="$PROJECT_ROOT"
fi

print_header() {
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE}  LibreMesh Security Scanner${NC}"
    echo -e "${BLUE}===================================${NC}"
    echo "Scanning: $SCAN_PATH"
    if [[ "$QUICK_MODE" == true ]]; then
        echo "Mode: Quick scan (secrets only)"
    fi
    echo
}

print_result() {
    local level="$1"
    local message="$2"
    local count="${3:-}"
    
    case "$level" in
        "error")
            echo -e "${RED}❌ $message${NC}" 
            [[ -n "$count" ]] && echo -e "   Count: $count"
            ;;
        "warning")
            echo -e "${YELLOW}⚠️  $message${NC}"
            [[ -n "$count" ]] && echo -e "   Count: $count"
            ;;
        "info")
            echo -e "${BLUE}ℹ️  $message${NC}"
            [[ -n "$count" ]] && echo -e "   Count: $count"
            ;;
        "success")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
    esac
}

# Critical security patterns for LibreMesh development
check_hardcoded_secrets() {
    local path="$1"
    local total_issues=0
    
    echo -e "${BLUE}🔍 Scanning for hardcoded secrets...${NC}"
    
    # API keys and tokens (critical for LibreMesh apps)
    local api_patterns=(
        "api[_-]?key\s*[=:]\s*['\"][^'\"]{8,}['\"]"
        "secret[_-]?key\s*[=:]\s*['\"][^'\"]{8,}['\"]"
        "access[_-]?token\s*[=:]\s*['\"][^'\"]{20,}['\"]"
        "password\s*[=:]\s*['\"][^'\"]{6,}['\"]"
        "client[_-]?secret\s*[=:]\s*['\"][^'\"]{10,}['\"]"
    )
    
    for pattern in "${api_patterns[@]}"; do
        local matches
        local count_output
        count_output=$(rg -i "$pattern" "$path" --type-not binary -c 2>/dev/null || echo "")
        matches=$(echo "$count_output" | awk 'BEGIN{sum=0} {if($1 ~ /^[0-9]+$/) sum+=$1} END{print sum}')
        
        matches=${matches:-0}
        if [[ $matches -gt 0 ]]; then
            local pattern_name
            pattern_name=$(echo "$pattern" | sed 's/\\s\*.*$//' | sed 's/\[_-\]//' | sed 's/\\//g')
            print_result "error" "Potential $pattern_name found" "$matches"
            total_issues=$((total_issues + matches))
            
            # Show actual matches for investigation
            echo "   Files:"
            rg -i "$pattern" "$path" --type-not binary -l 2>/dev/null | head -3 | sed 's/^/     /'
            echo
        fi
    done
    
    # LibreMesh specific credentials
    local libremesh_creds=(
        "toorlibre"
        "LibreMesh"
        "admin.*123"
        "root.*password"
    )
    
    for cred in "${libremesh_creds[@]}"; do
        local matches
        matches=$(rg -i "$cred" "$path" --type-not binary -c 2>/dev/null | awk 'BEGIN{sum=0} {if($1 ~ /^[0-9]+$/) sum+=$1} END{print sum}')
        
        matches=${matches:-0}
        if [[ $matches -gt 0 ]]; then
            print_result "warning" "LibreMesh default credential pattern: $cred" "$matches"
            total_issues=$((total_issues + matches))
        fi
    done
    
    if [[ $total_issues -eq 0 ]]; then
        print_result "success" "No hardcoded secrets detected"
    else
        print_result "error" "Total security issues found: $total_issues"
        echo
    fi
    
    return $total_issues
}

# Check for dangerous code patterns in LibreMesh context
check_dangerous_patterns() {
    local path="$1"
    local total_issues=0
    
    echo -e "${BLUE}🔍 Scanning for dangerous patterns...${NC}"
    
    # Shell injection risks (critical for OpenWrt/LibreMesh)
    local dangerous_functions=(
        "eval\s*\("
        "exec\s*\("
        "system\s*\("
        "shell_exec\s*\("
        "passthru\s*\("
        "\$\(.*\$.*\)"  # Command substitution with variables
    )
    
    for pattern in "${dangerous_functions[@]}"; do
        local matches
        matches=$(rg "$pattern" "$path" --type-not binary -c 2>/dev/null | awk 'BEGIN{sum=0} {if($1 ~ /^[0-9]+$/) sum+=$1} END{print sum}')
        
        matches=${matches:-0}
        if [[ $matches -gt 0 ]]; then
            local func_name
            func_name=$(echo "$pattern" | sed 's/\\s\*.*$//' | sed 's/\\//g' | sed 's/\$//g')
            print_result "warning" "Dangerous function: $func_name" "$matches"
            total_issues=$((total_issues + matches))
        fi
    done
    
    # Insecure protocols (important for mesh networking)
    local insecure_protocols=(
        "http://[^'\"\s]+"
        "ftp://[^'\"\s]+"
        "telnet://"
    )
    
    for pattern in "${insecure_protocols[@]}"; do
        local matches
        matches=$(rg "$pattern" "$path" --type-not binary -c 2>/dev/null | awk 'BEGIN{sum=0} {if($1 ~ /^[0-9]+$/) sum+=$1} END{print sum}')
        
        matches=${matches:-0}
        if [[ $matches -gt 0 ]]; then
            print_result "info" "Unencrypted protocol usage" "$matches"
        fi
    done
    
    if [[ $total_issues -eq 0 ]]; then
        print_result "success" "No dangerous patterns detected"
    fi
    
    return $total_issues
}

# Check file permissions (important for scripts and configs)
check_file_permissions() {
    local path="$1"
    local issues=0
    
    echo -e "${BLUE}🔍 Checking file permissions...${NC}"
    
    # Check for world-writable files
    local world_writable
    world_writable=$(find "$path" -type f -perm -002 2>/dev/null | wc -l || echo "0")
    
    if [[ $world_writable -gt 0 ]]; then
        print_result "error" "World-writable files found" "$world_writable"
        find "$path" -type f -perm -002 2>/dev/null | head -3 | sed 's/^/   /'
        issues=$((issues + world_writable))
    fi
    
    # Check for executable files that shouldn't be
    local suspicious_exec
    suspicious_exec=$(find "$path" -type f -perm /111 \( -name "*.txt" -o -name "*.md" -o -name "*.json" \) 2>/dev/null | wc -l || echo "0")
    
    if [[ $suspicious_exec -gt 0 ]]; then
        print_result "warning" "Suspicious executable files" "$suspicious_exec"
        find "$path" -type f -perm /111 \( -name "*.txt" -o -name "*.md" -o -name "*.json" \) 2>/dev/null | head -3 | sed 's/^/   /'
        issues=$((issues + suspicious_exec))
    fi
    
    if [[ $issues -eq 0 ]]; then
        print_result "success" "File permissions look good"
    fi
    
    return $issues
}

# LibreMesh-specific security checks
check_libremesh_security() {
    local path="$1"
    local issues=0
    
    echo -e "${BLUE}🔍 LibreMesh-specific security checks...${NC}"
    
    # Check for default LibreRouter credentials
    local default_creds=$(rg -i "toorlibre1|changeme|admin123" "$path" --type-not binary -c 2>/dev/null | awk 'BEGIN{sum=0} {if($1 ~ /^[0-9]+$/) sum+=$1} END{print sum}')
    default_creds=${default_creds:-0}
    if [[ $default_creds -gt 0 ]]; then
        print_result "warning" "Default credential patterns" "$default_creds"
        issues=$((issues + default_creds))
    fi
    
    # Check for hardcoded IP addresses (except documentation)
    local hardcoded_ips=$(rg -E "\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b" "$path" --type-not binary -c 2>/dev/null | awk 'BEGIN{sum=0} {if($1 ~ /^[0-9]+$/) sum+=$1} END{print sum}')
    hardcoded_ips=${hardcoded_ips:-0}
    if [[ $hardcoded_ips -gt 20 ]]; then  # Threshold for docs vs actual hardcoding
        print_result "info" "Many hardcoded IP addresses (check if intentional)" "$hardcoded_ips"
    fi
    
    # Check for SSH key material
    local ssh_keys=$(rg -i "BEGIN.*PRIVATE KEY|ssh-rsa|ssh-ed25519" "$path" --type-not binary -c 2>/dev/null | awk 'BEGIN{sum=0} {if($1 ~ /^[0-9]+$/) sum+=$1} END{print sum}')
    ssh_keys=${ssh_keys:-0}
    if [[ $ssh_keys -gt 0 ]]; then
        print_result "error" "SSH key material found" "$ssh_keys"
        issues=$((issues + ssh_keys))
    fi
    
    if [[ $issues -eq 0 ]]; then
        print_result "success" "LibreMesh-specific checks passed"
    fi
    
    return $issues
}

# Main security scan
perform_scan() {
    local path="$1"
    local total_issues=0
    
    print_header
    
    # Always check for secrets (most critical)
    check_hardcoded_secrets "$path"
    total_issues=$((total_issues + $?))
    echo
    
    # LibreMesh-specific checks
    check_libremesh_security "$path"
    total_issues=$((total_issues + $?))
    echo
    
    if [[ "$QUICK_MODE" != true ]]; then
        # Additional checks for full scan
        check_dangerous_patterns "$path"
        total_issues=$((total_issues + $?))
        echo
        
        check_file_permissions "$path"
        total_issues=$((total_issues + $?))
        echo
    fi
    
    # Summary
    echo -e "${BLUE}===================================${NC}"
    if [[ $total_issues -eq 0 ]]; then
        print_result "success" "Security scan completed - No critical issues found"
        echo -e "${GREEN}Your LibreMesh development environment looks secure! 🛡️${NC}"
    elif [[ $total_issues -lt 5 ]]; then
        print_result "warning" "Security scan completed - Minor issues found"
        echo -e "${YELLOW}Consider reviewing the issues above${NC}"
    else
        print_result "error" "Security scan completed - Multiple issues found"
        echo -e "${RED}Please review and fix the security issues above${NC}"
        
        if [[ "$EXIT_ON_FAIL" == true ]]; then
            exit 1
        fi
    fi
    echo -e "${BLUE}===================================${NC}"
    
    return $total_issues
}

# Usage help
show_usage() {
    cat << EOF
LibreMesh Security Scanner

Usage:
  $0                          # Scan entire lime-dev project
  $0 repos/lime-app          # Scan specific directory
  $0 --quick                 # Quick scan (secrets only)
  $0 --fail-fast            # Exit with error if issues found

Examples:
  $0                         # Full security scan
  $0 --quick                # Quick check before commit
  $0 repos/lime-packages    # Check specific repository
  $0 --fail-fast           # For CI/CD integration

EOF
}

# Main execution
main() {
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        --quick)
            QUICK_MODE=true
            SCAN_PATH="$PROJECT_ROOT"
            ;;
        --fail-fast)
            EXIT_ON_FAIL=true
            SCAN_PATH="$PROJECT_ROOT"
            ;;
        *)
            if [[ -n "${1:-}" ]] && [[ -d "$1" ]]; then
                SCAN_PATH="$1"
            elif [[ -n "${1:-}" ]]; then
                echo "Error: Directory '$1' not found"
                exit 1
            fi
            ;;
    esac
    
    # Check dependencies
    if ! command -v rg >/dev/null; then
        echo "Error: ripgrep (rg) is required but not installed"
        echo "Install with: sudo apt install ripgrep"
        exit 1
    fi
    
    perform_scan "$SCAN_PATH"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi