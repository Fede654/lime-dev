#!/bin/bash
#
# Lime-Dev Versions Configuration Parser
# Provides unified source of truth for repository versions and build parameters
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
VERSIONS_CONFIG="$LIME_BUILD_DIR/configs/versions.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse a specific configuration value from versions.conf
parse_config() {
    local section="$1"
    local key="$2"
    local config_file="${3:-$VERSIONS_CONFIG}"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Extract value from INI-style configuration
    awk -F'=' -v section="[$section]" -v key="$key" '
        $0 == section { in_section = 1; next }
        /^\[/ { in_section = 0; next }
        in_section && $1 == key { print $2; exit }
    ' "$config_file"
}

# Parse repository information (URL|branch|remote)
parse_repository() {
    local repo_key="$1"
    local mode="${2:-development}"
    local config_file="${3:-$VERSIONS_CONFIG}"
    
    # Check for mode-specific overrides first
    if [[ "$mode" == "development" ]]; then
        local dev_override="${repo_key}_development"
        local dev_config=$(parse_config "development_overrides" "$dev_override" "$config_file")
        if [[ -n "$dev_config" ]]; then
            echo "$dev_config"
            return 0
        fi
    elif [[ "$mode" == "release" ]]; then
        local release_override="${repo_key}_release"
        local release_config=$(parse_config "release_overrides" "$release_override" "$config_file")
        if [[ -n "$release_config" ]]; then
            echo "$release_config"
            return 0
        fi
    fi
    
    # Fall back to regular repository definition
    parse_config "repositories" "$repo_key" "$config_file"
}

# Convert repository string to OpenWrt feed format
repository_to_feed() {
    local repo_info="$1"
    local feed_name="$2"
    
    if [[ -z "$repo_info" ]]; then
        print_error "Empty repository information"
        return 1
    fi
    
    # Split repo_info: url|branch|remote
    IFS='|' read -r url branch remote <<< "$repo_info"
    
    # Convert to OpenWrt feed format
    echo "src-git $feed_name $url${branch:+;$branch}"
}

# Generate environment variables for build system
generate_build_environment() {
    local mode="${1:-development}"
    local config_file="${2:-$VERSIONS_CONFIG}"
    
    # Only print info if not in quiet mode
    if [[ "${QUIET:-false}" != "true" ]]; then
        print_info "Generating build environment for $mode mode"
    fi
    
    # Parse repository configurations
    local lime_packages_repo=$(parse_repository "lime_packages" "$mode" "$config_file")
    local librerouteros_repo=$(parse_repository "librerouteros" "$mode" "$config_file")
    local openwrt_repo=$(parse_repository "openwrt" "$mode" "$config_file")
    local kconfig_utils_repo=$(parse_repository "kconfig_utils" "$mode" "$config_file")
    
    # Parse build configurations
    local openwrt_version=$(parse_config "firmware_versions" "openwrt_version" "$config_file")
    local libremesh_version=$(parse_config "firmware_versions" "libremesh_version" "$config_file")
    local default_target=$(parse_config "build_targets" "default_target" "$config_file")
    
    # Validate essential configurations
    if [[ -z "$lime_packages_repo" ]]; then
        print_error "lime_packages repository configuration missing"
        return 1
    fi
    
    if [[ -z "$openwrt_version" ]]; then
        print_error "OpenWrt version configuration missing"
        return 1
    fi
    
    # Generate feed configurations
    local libremesh_feed=$(repository_to_feed "$lime_packages_repo" "libremesh")
    
    # Output environment variables
    cat << EOF
# Lime-Dev Build Environment Configuration
# Generated on $(date)
# Mode: $mode

# Repository Feed Configurations
export LIBREMESH_FEED="$libremesh_feed"
export LIBREROUTER_FEED="src-link librerouter \$(dirname \$(realpath \${BASH_SOURCE}))/packages"
export AMPR_FEED="src-git ampr https://github.com/javierbrk/ampr-openwrt.git;patch-1"
export TMATE_FEED="src-git tmate https://github.com/project-openwrt/openwrt-tmate.git"

# Version Specifications
export OPENWRT_VERSION="$openwrt_version"
export LIBREMESH_VERSION="$libremesh_version"
export BUILD_TARGET_DEFAULT="$default_target"

# Build Mode
export LIME_BUILD_MODE="$mode"

# Repository Information (for verification)
export LIME_PACKAGES_REPO="$lime_packages_repo"
export LIBREROUTEROS_REPO="$librerouteros_repo"
export OPENWRT_REPO="$openwrt_repo"
export KCONFIG_UTILS_REPO="$kconfig_utils_repo"

# Build Paths (from umbrella repo)
export LIME_BUILD_DIR="$LIME_BUILD_DIR"
export LIBREROUTEROS_DIR="$LIME_BUILD_DIR/repos/librerouteros"
export OPENWRT_SRC_DIR="$LIME_BUILD_DIR/repos/librerouteros/openwrt"
export KCONFIG_UTILS_DIR="$LIME_BUILD_DIR/repos/kconfig-utils"
export OPENWRT_DL_DIR="$LIME_BUILD_DIR/dl"
export LIBREROUTEROS_BUILD_DIR="$LIME_BUILD_DIR/build"

# Configuration Metadata
export LIME_CONFIG_SOURCE="$config_file"
export LIME_CONFIG_GENERATED="$(date -Iseconds)"
EOF
}

# Verify repository versions match configuration
verify_repository_versions() {
    local mode="${1:-development}"
    local config_file="${2:-$VERSIONS_CONFIG}"
    
    print_info "Verifying repository versions..."
    
    local errors=0
    
    # Check OpenWrt version
    local expected_openwrt=$(parse_config "firmware_versions" "openwrt_version" "$config_file")
    if [[ -d "$LIME_BUILD_DIR/repos/librerouteros/openwrt/.git" ]]; then
        cd "$LIME_BUILD_DIR/repos/librerouteros/openwrt"
        local actual_openwrt=$(git describe --tags 2>/dev/null | sed 's/^v//')
        if [[ "$actual_openwrt" != "$expected_openwrt" ]]; then
            print_warn "OpenWrt version mismatch:"
            print_warn "  Expected: $expected_openwrt"
            print_warn "  Actual: $actual_openwrt"
            ((errors++))
        else
            print_info "✓ OpenWrt version matches: $expected_openwrt"
        fi
    else
        print_warn "OpenWrt repository not found - run setup first"
        ((errors++))
    fi
    
    # Check LibreMesh packages repository
    local expected_lime_packages=$(parse_repository "lime_packages" "$mode" "$config_file")
    if [[ -d "$LIME_BUILD_DIR/repos/librerouteros/feeds/libremesh/.git" ]]; then
        cd "$LIME_BUILD_DIR/repos/librerouteros/feeds/libremesh"
        local actual_remote=$(git remote get-url origin 2>/dev/null)
        local actual_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        
        IFS='|' read -r expected_url expected_branch expected_remote <<< "$expected_lime_packages"
        
        if [[ "$actual_remote" != "$expected_url" ]]; then
            print_warn "LibreMesh packages repository mismatch:"
            print_warn "  Expected: $expected_url"
            print_warn "  Actual: $actual_remote"
            ((errors++))
        elif [[ "$actual_branch" != "$expected_branch" ]]; then
            print_warn "LibreMesh packages branch mismatch:"
            print_warn "  Expected: $expected_branch"
            print_warn "  Actual: $actual_branch"
            ((errors++))
        else
            print_info "✓ LibreMesh packages repository matches: $expected_url ($expected_branch)"
        fi
    else
        print_warn "LibreMesh packages repository not found - run build first"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        print_info "✓ All repository versions verified successfully"
        return 0
    else
        print_error "Found $errors version mismatches"
        return 1
    fi
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        parse)
            local section="${1:-repositories}"
            local key="${2:-lime_packages}"
            parse_config "$section" "$key"
            ;;
        repository)
            local repo_key="${1:-lime_packages}"
            local mode="${2:-development}"
            parse_repository "$repo_key" "$mode"
            ;;
        feed)
            local repo_key="${1:-lime_packages}"
            local mode="${2:-development}"
            local feed_name="${3:-libremesh}"
            local repo_info=$(parse_repository "$repo_key" "$mode")
            repository_to_feed "$repo_info" "$feed_name"
            ;;
        environment)
            local mode="${1:-development}"
            generate_build_environment "$mode"
            ;;
        verify)
            local mode="${1:-development}"
            verify_repository_versions "$mode"
            ;;
        help|--help|-h)
            cat << EOF
Lime-Dev Versions Configuration Parser

Usage: $0 <command> [options]

Commands:
    parse <section> <key>           Parse specific configuration value
    repository <repo_key> [mode]    Get repository information (URL|branch|remote)
    feed <repo_key> [mode] [name]   Convert repository to OpenWrt feed format
    environment [mode]              Generate complete build environment
    verify [mode]                   Verify repository versions match configuration
    help                           Show this help message

Modes:
    development    Use standard repositories (default)
    release        Use release override repositories

Examples:
    $0 parse repositories lime_packages
    $0 repository lime_packages release
    $0 feed lime_packages development libremesh
    $0 environment development
    $0 verify release

EOF
            ;;
        *)
            print_error "Unknown command: $command"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi