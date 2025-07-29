#!/bin/bash
#
# Configuration Integrity Validation for lime-dev
# Detects config corruption and provides recovery options
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="${CONFIG_FILE:-$LIME_BUILD_DIR/configs/versions.conf}"

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
print_critical() { echo -e "${RED}[CRITICAL]${NC} $1"; }

# Check if configuration file exists
check_config_exists() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_critical "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    return 0
}

# Validate expected sections exist
validate_sections() {
    local expected_sections=("repositories" "sources" "build_defaults" "makefile_patches" "build_targets" "firmware_versions" "qemu_config" "node_config" "build_validation")
    local missing_sections=()
    
    for section in "${expected_sections[@]}"; do
        if ! grep -q "^\[$section\]" "$CONFIG_FILE"; then
            missing_sections+=("$section")
        fi
    done
    
    if [[ ${#missing_sections[@]} -gt 0 ]]; then
        print_error "Missing configuration sections: ${missing_sections[*]}"
        return 1
    fi
    
    return 0
}

# Validate key naming conventions
validate_key_naming() {
    local corruption_found=false
    local ambiguous_keys=()
    
    print_info "Validating key naming conventions..."
    
    # Check for actual ambiguous patterns - keys that appear in wrong sections
    # These patterns are problematic only if they appear outside their intended sections
    # Note: Current config uses proper INI sections, so most keys are actually valid
    
    # Special handling for lime-app: check if it's in makefile_patches section (allowed) or elsewhere (not allowed)
    if grep -q "^lime-app=" "$CONFIG_FILE"; then
        local lime_app_sections=$(grep -B 10 "^lime-app=" "$CONFIG_FILE" | grep "^\[" | tail -1 | tr -d '[]')
        if [[ "$lime_app_sections" != "makefile_patches" ]]; then
            ambiguous_keys+=("lime-app (not in makefile_patches section)")
            corruption_found=true
        fi
    fi
    
    # Instead of flagging all instances, check for actual problematic patterns:
    # 1. Keys outside of proper sections (orphaned keys)
    # 2. Duplicate keys within the same section
    
    # Check for keys that appear before any section (orphaned keys)
    local orphaned_keys=$(awk '/^\[/ {section=1} /^[a-zA-Z].*=/ && !section {print $0}' "$CONFIG_FILE")
    if [[ -n "$orphaned_keys" ]]; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local key=$(echo "$line" | cut -d'=' -f1)
                ambiguous_keys+=("$key (orphaned - no section)")
                corruption_found=true
            fi
        done <<< "$orphaned_keys"
    fi
    
    if [[ "$corruption_found" == "true" ]]; then
        print_error "Found ${#ambiguous_keys[@]} ambiguous keys that could cause conflicts:"
        for key in "${ambiguous_keys[@]}"; do
            print_error "  • $key (line $(grep -n "^$key=" "$CONFIG_FILE" | cut -d':' -f1))"
        done
        return 1
    fi
    
    return 0
}

# Validate required keys exist with new naming scheme
validate_required_keys() {
    local missing_keys=()
    
    # Repository keys (should end with -repo)
    local required_repo_keys=("lime-app-repo" "lime-packages-repo" "librerouteros-repo" "kconfig-utils-repo" "openwrt-repo")
    for key in "${required_repo_keys[@]}"; do
        if ! grep -q "^$key=" "$CONFIG_FILE"; then
            missing_keys+=("$key in [repositories]")
        fi
    done
    
    # Source keys (should have both -source-default and -source-local variants)
    local required_source_packages=("lime-app" "lime-packages")
    for package in "${required_source_packages[@]}"; do
        local default_key="${package}-source-default"
        local local_key="${package}-source-local"
        
        if ! grep -q "^$default_key=" "$CONFIG_FILE"; then
            missing_keys+=("$default_key in [sources]")
        fi
        if ! grep -q "^$local_key=" "$CONFIG_FILE"; then
            missing_keys+=("$local_key in [sources]")
        fi
    done
    
    # Other required keys with specific naming
    local other_keys=(
        "lime-app:makefile_patches"
        "default_target_hardware:build_targets"
        "development_target_hardware:build_targets"
        "openwrt_base_version:firmware_versions"
        "qemu_bridge_interface:qemu_config"
        "node_minimum_version:node_config"
        "validate_git_integrity_enabled:build_validation"
    )
    
    for entry in "${other_keys[@]}"; do
        local key="${entry%:*}"
        local section="${entry#*:}"
        if ! grep -q "^$key=" "$CONFIG_FILE"; then
            missing_keys+=("$key in [$section]")
        fi
    done
    
    if [[ ${#missing_keys[@]} -gt 0 ]]; then
        print_error "Missing required keys:"
        for key in "${missing_keys[@]}"; do
            print_error "  • $key"
        done
        return 1
    fi
    
    return 0
}

# Check for duplicate keys (corruption indicator)
validate_no_duplicates() {
    local duplicates_found=false
    
    print_info "Checking for duplicate keys..."
    
    # Find keys that appear more than once
    local duplicate_keys=$(grep -E "^[^#\[].*=" "$CONFIG_FILE" | cut -d'=' -f1 | sort | uniq -d)
    
    if [[ -n "$duplicate_keys" ]]; then
        print_error "Found duplicate keys (indicates corruption):"
        while IFS= read -r key; do
            if [[ -n "$key" ]]; then
                print_error "  • '$key' appears $(grep -c "^$key=" "$CONFIG_FILE") times"
                grep -n "^$key=" "$CONFIG_FILE" | while IFS=':' read -r line_num line_content; do
                    print_error "    Line $line_num: $line_content"
                done
            fi
        done <<< "$duplicate_keys"
        duplicates_found=true
    fi
    
    if [[ "$duplicates_found" == "true" ]]; then
        return 1
    fi
    
    return 0
}

# Show configuration corruption summary
show_corruption_summary() {
    local corruption_type="$1"
    
    print_critical "🔍 CONFIGURATION CORRUPTION DETECTED"
    echo
    print_warning "Corruption type: $corruption_type"
    print_warning "Configuration file: $CONFIG_FILE"
    echo
    print_info "This corruption can cause:"
    print_info "• Unpredictable build behavior"
    print_info "• Wrong repository sources being used"
    print_info "• Silent failures during builds"
    print_info "• Inconsistent behavior between runs"
    echo
}

# Show recovery options
show_recovery_options() {
    print_info "🛠️  RECOVERY OPTIONS:"
    echo
    print_info "1. AUTOMATIC FIX (Recommended):"
    print_info "   • Fix key naming automatically"
    print_info "   • Preserve all configuration values"
    print_info "   • Create backup of current config"
    echo
    print_info "2. MANUAL REVIEW:"
    print_info "   • Edit $CONFIG_FILE manually"
    print_info "   • Follow the new naming conventions"
    print_info "   • Re-run this validation"
    echo
    print_info "3. RESET TO DEFAULTS:"
    print_info "   • Restore from git: git checkout configs/versions.conf"
    print_info "   • Reconfigure your custom settings"
    echo
}

# Interactive confirmation dialog
confirm_corruption_action() {
    local corruption_details="$1"
    
    show_corruption_summary "$corruption_details"
    show_recovery_options
    
    print_critical "⚠️  CRITICAL: Continue with potentially corrupted configuration? ⚠️"
    echo
    
    local confirmation=""
    while [[ "$confirmation" != "yes" && "$confirmation" != "no" && "$confirmation" != "fix" ]]; do
        echo -n "Type 'fix' to auto-fix, 'yes' to continue anyway, or 'no' to abort: "
        read -r confirmation
        confirmation=$(echo "$confirmation" | tr '[:upper:]' '[:lower:]')
    done
    
    case "$confirmation" in
        "fix")
            print_info "Attempting automatic fix..."
            return 2  # Return code for auto-fix
            ;;
        "yes")
            print_warning "⚠️  Proceeding with corrupted configuration (not recommended)"
            return 0  # Continue despite corruption
            ;;
        "no")
            print_info "Operation aborted - fix configuration before proceeding"
            return 1  # Abort
            ;;
    esac
}

# Main validation function
validate_config_integrity() {
    local silent_mode="${1:-false}"
    
    if [[ "$silent_mode" != "true" ]]; then
        print_info "🔍 Validating configuration integrity..."
    fi
    
    # Check if config file exists
    if ! check_config_exists; then
        if [[ "$silent_mode" != "true" ]]; then
            confirm_corruption_action "Missing configuration file"
        fi
        return 1
    fi
    
    # Validate sections
    if ! validate_sections; then
        if [[ "$silent_mode" != "true" ]]; then
            confirm_corruption_action "Missing configuration sections"
            return $?
        fi
        return 1
    fi
    
    # Validate key naming
    if ! validate_key_naming; then
        if [[ "$silent_mode" != "true" ]]; then
            confirm_corruption_action "Ambiguous key naming detected"
            return $?
        fi
        return 1
    fi
    
    # Validate required keys
    if ! validate_required_keys; then
        if [[ "$silent_mode" != "true" ]]; then
            confirm_corruption_action "Missing required configuration keys"
            return $?
        fi
        return 1
    fi
    
    # Check for duplicates
    if ! validate_no_duplicates; then
        if [[ "$silent_mode" != "true" ]]; then
            confirm_corruption_action "Duplicate keys found"
            return $?
        fi
        return 1
    fi
    
    if [[ "$silent_mode" != "true" ]]; then
        print_success "✅ Configuration integrity validated successfully"
    fi
    
    return 0
}

# Auto-fix function (placeholder for future implementation)
auto_fix_config() {
    print_info "Auto-fix functionality not yet implemented"
    print_info "Please manually update the configuration file"
    return 1
}

# Command line interface
main() {
    case "${1:-validate}" in
        "validate")
            validate_config_integrity false
            ;;
        "check")
            validate_config_integrity true
            ;;
        "fix")
            if validate_config_integrity true; then
                print_success "Configuration is already valid"
            else
                auto_fix_config
            fi
            ;;
        "--help"|"-h")
            echo "Configuration Integrity Validator"
            echo
            echo "Usage: $0 [COMMAND]"
            echo
            echo "Commands:"
            echo "  validate    Interactive validation with corruption dialog (default)"
            echo "  check       Silent validation (exit code only)"
            echo "  fix         Attempt automatic fix of configuration issues"
            echo "  --help      Show this help"
            echo
            echo "Exit codes:"
            echo "  0  Configuration is valid"
            echo "  1  Corruption detected"
            echo "  2  Auto-fix requested"
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi