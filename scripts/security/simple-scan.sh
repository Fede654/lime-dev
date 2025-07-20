#!/bin/bash
#
# Simple LibreMesh Security Scanner
# Quick and reliable security checks for lime-dev workflow
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCAN_PATH="${1:-$PROJECT_ROOT}"
CRITICAL_ISSUES=0

print_header() {
    echo -e "${BLUE}=================================${NC}"
    echo -e "${BLUE}  LibreMesh Security Scanner${NC}"
    echo -e "${BLUE}=================================${NC}"
    echo "Scanning: $SCAN_PATH"
    echo
}

check_secrets() {
    echo -e "${BLUE}🔍 Checking for hardcoded secrets...${NC}"
    
    # API keys pattern
    local api_matches=0
    if rg -i "api[_-]?key\s*[=:]\s*['\"][^'\"]{8,}['\"]" "$SCAN_PATH" --type-not binary -q 2>/dev/null; then
        api_matches=$(rg -i "api[_-]?key\s*[=:]\s*['\"][^'\"]{8,}['\"]" "$SCAN_PATH" --type-not binary 2>/dev/null | wc -l)
    fi
    
    # Password patterns
    local pwd_matches=0
    if rg -i "password\s*[=:]\s*['\"][^'\"]{6,}['\"]" "$SCAN_PATH" --type-not binary -q 2>/dev/null; then
        pwd_matches=$(rg -i "password\s*[=:]\s*['\"][^'\"]{6,}['\"]" "$SCAN_PATH" --type-not binary 2>/dev/null | wc -l)
    fi
    
    # Secret tokens
    local secret_matches=0
    if rg -i "secret[_-]?key\s*[=:]\s*['\"][^'\"]{8,}['\"]" "$SCAN_PATH" --type-not binary -q 2>/dev/null; then
        secret_matches=$(rg -i "secret[_-]?key\s*[=:]\s*['\"][^'\"]{8,}['\"]" "$SCAN_PATH" --type-not binary 2>/dev/null | wc -l)
    fi
    
    local total_secrets=$((api_matches + pwd_matches + secret_matches))
    
    if [[ $total_secrets -gt 0 ]]; then
        echo -e "${RED}❌ Found $total_secrets potential secrets${NC}"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + total_secrets))
        
        if [[ $api_matches -gt 0 ]]; then
            echo -e "   ${RED}API keys: $api_matches${NC}"
        fi
        if [[ $pwd_matches -gt 0 ]]; then
            echo -e "   ${RED}Passwords: $pwd_matches${NC}"
        fi
        if [[ $secret_matches -gt 0 ]]; then
            echo -e "   ${RED}Secret keys: $secret_matches${NC}"
        fi
    else
        echo -e "${GREEN}✅ No hardcoded secrets detected${NC}"
    fi
    echo
}

check_dangerous_functions() {
    echo -e "${BLUE}🔍 Checking for dangerous functions...${NC}"
    
    local eval_matches=0
    local exec_matches=0  
    local system_matches=0
    
    if rg "eval\s*\(" "$SCAN_PATH" --type-not binary -q 2>/dev/null; then
        eval_matches=$(rg "eval\s*\(" "$SCAN_PATH" --type-not binary 2>/dev/null | wc -l)
    fi
    
    if rg "exec\s*\(" "$SCAN_PATH" --type-not binary -q 2>/dev/null; then
        exec_matches=$(rg "exec\s*\(" "$SCAN_PATH" --type-not binary 2>/dev/null | wc -l)
    fi
    
    if rg "system\s*\(" "$SCAN_PATH" --type-not binary -q 2>/dev/null; then
        system_matches=$(rg "system\s*\(" "$SCAN_PATH" --type-not binary 2>/dev/null | wc -l)
    fi
    
    local total_dangerous=$((eval_matches + exec_matches + system_matches))
    
    if [[ $total_dangerous -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Found $total_dangerous dangerous function calls${NC}"
        
        if [[ $eval_matches -gt 0 ]]; then
            echo -e "   ${YELLOW}eval(): $eval_matches${NC}"
        fi
        if [[ $exec_matches -gt 0 ]]; then
            echo -e "   ${YELLOW}exec(): $exec_matches${NC}"
        fi
        if [[ $system_matches -gt 0 ]]; then
            echo -e "   ${YELLOW}system(): $system_matches${NC}"
        fi
    else
        echo -e "${GREEN}✅ No dangerous functions detected${NC}"
    fi
    echo
}

check_libremesh_creds() {
    echo -e "${BLUE}🔍 Checking LibreMesh credentials...${NC}"
    
    local default_creds=0
    local ssh_keys=0
    
    if rg -i "toorlibre1" "$SCAN_PATH" --type-not binary -q 2>/dev/null; then
        default_creds=$(rg -i "toorlibre1" "$SCAN_PATH" --type-not binary 2>/dev/null | wc -l)
    fi
    
    if rg -i "BEGIN.*PRIVATE KEY|ssh-rsa|ssh-ed25519" "$SCAN_PATH" --type-not binary -q 2>/dev/null; then
        ssh_keys=$(rg -i "BEGIN.*PRIVATE KEY|ssh-rsa|ssh-ed25519" "$SCAN_PATH" --type-not binary 2>/dev/null | wc -l)
    fi
    
    if [[ $default_creds -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Default credentials found: $default_creds${NC}"
    fi
    
    if [[ $ssh_keys -gt 0 ]]; then
        echo -e "${RED}❌ SSH key material found: $ssh_keys${NC}"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + ssh_keys))
    fi
    
    if [[ $default_creds -eq 0 && $ssh_keys -eq 0 ]]; then
        echo -e "${GREEN}✅ LibreMesh security checks passed${NC}"
    fi
    echo
}

main() {
    print_header
    
    # Quick dependency check
    if ! command -v rg >/dev/null; then
        echo -e "${RED}Error: ripgrep (rg) is required${NC}"
        exit 1
    fi
    
    # Run security checks
    check_secrets
    check_dangerous_functions
    check_libremesh_creds
    
    # Summary
    echo -e "${BLUE}=================================${NC}"
    if [[ $CRITICAL_ISSUES -eq 0 ]]; then
        echo -e "${GREEN}✅ Security scan completed - No critical issues found${NC}"
        echo -e "${GREEN}Your LibreMesh development environment looks secure! 🛡️${NC}"
    else
        echo -e "${RED}❌ Security scan completed - $CRITICAL_ISSUES critical issues found${NC}"
        echo -e "${RED}Please review and fix the security issues above${NC}"
        exit 1
    fi
    echo -e "${BLUE}=================================${NC}"
}

# Show usage
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << EOF
LibreMesh Simple Security Scanner

Usage:
  $0 [directory]     # Scan specific directory
  $0                # Scan entire lime-dev project

Examples:
  $0                    # Full scan
  $0 repos/lime-app    # Scan lime-app only
  $0 scripts/          # Scan scripts directory

EOF
    exit 0
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi