#!/bin/bash
#
# Lime-Dev Build Environment Injection System
# Injects unified source of truth from versions.conf into build environment
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
VERSIONS_PARSER="$SCRIPT_DIR/versions-parser.sh"

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

# Generate and source build environment
inject_build_environment() {
    local mode="${1:-development}"
    local temp_env_file="/tmp/lime_build_env_$$.sh"
    
    print_info "Injecting build environment for $mode mode"
    
    # Generate environment configuration
    if ! "$VERSIONS_PARSER" environment "$mode" > "$temp_env_file"; then
        print_error "Failed to generate build environment"
        rm -f "$temp_env_file"
        return 1
    fi
    
    # Source the generated environment
    source "$temp_env_file"
    
    # Clean up temporary file
    rm -f "$temp_env_file"
    
    print_info "✓ Build environment injected successfully"
    print_info "  Mode: $LIME_BUILD_MODE"
    print_info "  LibreMesh Feed: $LIBREMESH_FEED"
    print_info "  OpenWrt Version: $OPENWRT_VERSION"
    print_info "  Build Target: $BUILD_TARGET_DEFAULT"
    
    # Apply package-level source injection for all modes (unified system)
    if [[ -x "$SCRIPT_DIR/package-source-injector.sh" ]]; then
        print_info "Applying package-level source injection for $mode mode"
        if ! "$SCRIPT_DIR/package-source-injector.sh" apply "$mode" "$BUILD_DIR"; then
            print_warn "Package source injection failed, continuing with feed defaults"
        fi
    fi
    
    return 0
}

# Verify that environment injection is working
verify_environment() {
    local required_vars=(
        "LIBREMESH_FEED"
        "OPENWRT_VERSION"
        "LIME_BUILD_MODE"
        "LIBREROUTEROS_DIR"
        "OPENWRT_SRC_DIR"
        "KCONFIG_UTILS_DIR"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -eq 0 ]]; then
        print_info "✓ All required environment variables are set"
        return 0
    else
        print_error "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
}

# Show current environment status
show_environment() {
    echo "Current Lime-Dev Build Environment:"
    echo "====================================="
    echo "Mode: ${LIME_BUILD_MODE:-not set}"
    echo "LibreMesh Feed: ${LIBREMESH_FEED:-not set}"
    echo "OpenWrt Version: ${OPENWRT_VERSION:-not set}"
    echo "Build Target: ${BUILD_TARGET_DEFAULT:-not set}"
    echo ""
    echo "Build Paths:"
    echo "  Lime Build Dir: ${LIME_BUILD_DIR:-not set}"
    echo "  LibreRouterOS Dir: ${LIBREROUTEROS_DIR:-not set}"
    echo "  OpenWrt Source: ${OPENWRT_SRC_DIR:-not set}"
    echo "  Kconfig Utils: ${KCONFIG_UTILS_DIR:-not set}"
    echo "  Downloads: ${OPENWRT_DL_DIR:-not set}"
    echo "  Build Dir: ${LIBREROUTEROS_BUILD_DIR:-not set}"
    echo ""
    echo "Repository Information:"
    echo "  LibreMesh Packages: ${LIME_PACKAGES_REPO:-not set}"
    echo "  LibreRouterOS: ${LIBREROUTEROS_REPO:-not set}"
    echo "  OpenWrt: ${OPENWRT_REPO:-not set}"
    echo "  Kconfig Utils: ${KCONFIG_UTILS_REPO:-not set}"
    echo ""
    echo "Configuration Metadata:"
    echo "  Config Source: ${LIME_CONFIG_SOURCE:-not set}"
    echo "  Generated: ${LIME_CONFIG_GENERATED:-not set}"
}

# Export environment to a file for sourcing
export_environment() {
    local mode="${1:-development}"
    local output_file="${2:-/tmp/lime_build_env.sh}"
    
    print_info "Exporting build environment to $output_file"
    
    if ! "$VERSIONS_PARSER" environment "$mode" > "$output_file"; then
        print_error "Failed to export build environment"
        return 1
    fi
    
    chmod +x "$output_file"
    print_info "✓ Build environment exported successfully"
    print_info "  Use: source $output_file"
    
    return 0
}

# Execute command with injected environment
execute_with_environment() {
    local mode="$1"
    shift
    
    if [[ $# -eq 0 ]]; then
        print_error "No command provided"
        return 1
    fi
    
    print_info "Executing command with $mode environment: $*"
    
    # Inject environment
    if ! inject_build_environment "$mode"; then
        print_error "Failed to inject build environment"
        return 1
    fi
    
    # Execute the command
    exec "$@"
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        inject)
            local mode="${1:-development}"
            inject_build_environment "$mode"
            ;;
        verify)
            verify_environment
            ;;
        show)
            show_environment
            ;;
        export)
            local mode="${1:-development}"
            local output_file="${2:-/tmp/lime_build_env.sh}"
            export_environment "$mode" "$output_file"
            ;;
        exec)
            local mode="${1:-development}"
            shift
            execute_with_environment "$mode" "$@"
            ;;
        help|--help|-h)
            cat << EOF
Lime-Dev Build Environment Injection System

Usage: $0 <command> [options]

Commands:
    inject [mode]                 Inject build environment variables
    verify                        Verify environment variables are set
    show                         Show current environment status
    export [mode] [file]         Export environment to file for sourcing
    exec [mode] <command>        Execute command with injected environment
    help                         Show this help message

Modes:
    development    Use standard repositories (default)
    release        Use release override repositories

Examples:
    $0 inject development
    $0 verify
    $0 show
    $0 export release /tmp/release_env.sh
    $0 exec development ./scripts/build.sh x86_64

Environment Usage:
    # Source environment directly
    source <($0 export development -)
    
    # Use in scripts
    $0 inject development
    if $0 verify; then
        echo "Environment ready for build"
    fi

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