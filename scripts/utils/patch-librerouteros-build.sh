#!/bin/bash
#
# Lime-Dev LibreRouterOS Build Script Patcher
# Patches librerouteros_build.sh to respect umbrella repo configuration
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
LIBREROUTEROS_BUILD_SCRIPT="$LIME_BUILD_DIR/repos/librerouteros/librerouteros_build.sh"

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

# Check if librerouteros_build.sh exists
check_build_script() {
    if [[ ! -f "$LIBREROUTEROS_BUILD_SCRIPT" ]]; then
        print_error "LibreRouterOS build script not found: $LIBREROUTEROS_BUILD_SCRIPT"
        print_error "Run 'lime setup install' first"
        return 1
    fi
    return 0
}

# Create backup of original script
create_backup() {
    local backup_file="${LIBREROUTEROS_BUILD_SCRIPT}.lime-backup"
    
    if [[ ! -f "$backup_file" ]]; then
        print_info "Creating backup of original build script"
        cp "$LIBREROUTEROS_BUILD_SCRIPT" "$backup_file"
        print_info "✓ Backup created: $backup_file"
    else
        print_info "Backup already exists: $backup_file"
    fi
}

# Restore original script from backup
restore_backup() {
    local backup_file="${LIBREROUTEROS_BUILD_SCRIPT}.lime-backup"
    
    if [[ ! -f "$backup_file" ]]; then
        print_error "No backup found: $backup_file"
        return 1
    fi
    
    print_info "Restoring original build script from backup"
    cp "$backup_file" "$LIBREROUTEROS_BUILD_SCRIPT"
    print_info "✓ Original script restored"
}

# Check if script is already patched
is_patched() {
    grep -q "# LIME-DEV PATCH APPLIED" "$LIBREROUTEROS_BUILD_SCRIPT" 2>/dev/null
}

# Apply patches to make script respect umbrella repo configuration
apply_patches() {
    if is_patched; then
        print_info "Script is already patched"
        return 0
    fi
    
    print_info "Applying patches to librerouteros_build.sh"
    
    # Create temporary script for modifications
    local temp_script="/tmp/librerouteros_build_patched.sh"
    cp "$LIBREROUTEROS_BUILD_SCRIPT" "$temp_script"
    
    # Apply patches using sed
    print_info "Patching feed configurations..."
    
    # Replace hardcoded LIBREMESH_FEED with environment variable
    sed -i 's|^lo:define_default_value LIBREMESH_FEED.*|lo:define_default_value LIBREMESH_FEED "${LIBREMESH_FEED:-src-git libremesh https://github.com/libremesh/lime-packages.git}"|' "$temp_script"
    
    # Replace hardcoded LIBREROUTER_FEED with environment variable
    sed -i 's|^lo:define_default_value LIBREROUTER_FEED.*|lo:define_default_value LIBREROUTER_FEED "${LIBREROUTER_FEED:-src-link librerouter \\$(dirname \\$(realpath \\${BASH_SOURCE}))/packages}"|' "$temp_script"
    
    # Replace hardcoded AMPR_FEED with environment variable
    sed -i 's|^lo:define_default_value AMPR_FEED.*|lo:define_default_value AMPR_FEED "${AMPR_FEED:-src-git ampr https://github.com/javierbrk/ampr-openwrt.git;patch-1}"|' "$temp_script"
    
    # Replace hardcoded TMATE_FEED with environment variable
    sed -i 's|^lo:define_default_value TMATE_FEED.*|lo:define_default_value TMATE_FEED "${TMATE_FEED:-src-git tmate https://github.com/project-openwrt/openwrt-tmate.git}"|' "$temp_script"
    
    # Add patch marker and environment info
    cat > "/tmp/lime_patch_header.txt" << 'EOF'
# LIME-DEV PATCH APPLIED
# This script has been patched to respect umbrella repository configuration
# Generated on: $(date)
# Patch version: 1.0
#
# The following environment variables are now respected:
# - LIBREMESH_FEED: LibreMesh packages feed configuration
# - LIBREROUTER_FEED: LibreRouter packages feed configuration
# - AMPR_FEED: AMPR packages feed configuration
# - TMATE_FEED: TMATE packages feed configuration
#
# To restore original behavior, run:
# lime-dev/scripts/utils/patch-librerouteros-build.sh restore
#

EOF
    
    # Insert patch header after the existing header
    sed -i '/^# COPYLEFT$/r /tmp/lime_patch_header.txt' "$temp_script"
    
    # Add environment variable initialization section
    cat > "/tmp/lime_env_init.txt" << 'EOF'

## Lime-Dev Environment Integration
## Load environment variables from umbrella repository if available
if [[ -n "$LIME_BUILD_DIR" && -f "$LIME_BUILD_DIR/scripts/utils/inject-build-environment.sh" ]]; then
    # Source environment from umbrella repository
    source <("$LIME_BUILD_DIR/scripts/utils/versions-parser.sh" environment "${LIME_BUILD_MODE:-development}")
    echo "[LIME-DEV] Using umbrella repository configuration (mode: ${LIME_BUILD_MODE:-development})"
    echo "[LIME-DEV] LibreMesh feed: $LIBREMESH_FEED"
fi

EOF
    
    # Insert environment initialization after the function definitions
    sed -i '/^lo:define_default_value BUILD_TARGET/i\
'"$(cat /tmp/lime_env_init.txt)" "$temp_script"
    
    # Clean up temporary files
    rm -f "/tmp/lime_patch_header.txt" "/tmp/lime_env_init.txt"
    
    # Replace original script with patched version
    mv "$temp_script" "$LIBREROUTEROS_BUILD_SCRIPT"
    chmod +x "$LIBREROUTEROS_BUILD_SCRIPT"
    
    print_info "✓ Patches applied successfully"
    print_info "  - Feed configurations now respect environment variables"
    print_info "  - Environment integration added"
    print_info "  - Backup preserved for restoration"
    
    return 0
}

# Remove patches and restore original behavior
remove_patches() {
    if ! is_patched; then
        print_info "Script is not patched"
        return 0
    fi
    
    print_info "Removing patches from librerouteros_build.sh"
    restore_backup
    print_info "✓ Patches removed successfully"
    
    return 0
}

# Show current patch status
show_status() {
    echo "LibreRouterOS Build Script Patch Status"
    echo "======================================="
    echo "Script: $LIBREROUTEROS_BUILD_SCRIPT"
    
    if [[ -f "$LIBREROUTEROS_BUILD_SCRIPT" ]]; then
        if is_patched; then
            echo "Status: PATCHED"
            echo "Feeds are configured from environment variables"
        else
            echo "Status: ORIGINAL"
            echo "Feeds are hardcoded in script"
        fi
    else
        echo "Status: NOT FOUND"
        echo "Run 'lime setup install' first"
    fi
    
    local backup_file="${LIBREROUTEROS_BUILD_SCRIPT}.lime-backup"
    if [[ -f "$backup_file" ]]; then
        echo "Backup: Available"
    else
        echo "Backup: Not available"
    fi
    
    echo ""
    echo "Current Feed Configuration:"
    if is_patched && [[ -n "$LIBREMESH_FEED" ]]; then
        echo "  LibreMesh: $LIBREMESH_FEED"
        echo "  LibreRouter: ${LIBREROUTER_FEED:-not set}"
        echo "  AMPR: ${AMPR_FEED:-not set}"
        echo "  TMATE: ${TMATE_FEED:-not set}"
    else
        echo "  Using hardcoded values (see script for details)"
    fi
}

# Show differences between original and patched versions
show_diff() {
    local backup_file="${LIBREROUTEROS_BUILD_SCRIPT}.lime-backup"
    
    if [[ ! -f "$backup_file" ]]; then
        print_error "No backup found for comparison"
        return 1
    fi
    
    if [[ ! -f "$LIBREROUTEROS_BUILD_SCRIPT" ]]; then
        print_error "Current script not found"
        return 1
    fi
    
    print_info "Differences between original and current script:"
    diff -u "$backup_file" "$LIBREROUTEROS_BUILD_SCRIPT" || true
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        apply)
            check_build_script || exit 1
            create_backup
            apply_patches
            ;;
        remove|restore)
            check_build_script || exit 1
            remove_patches
            ;;
        status)
            show_status
            ;;
        diff)
            show_diff
            ;;
        backup)
            check_build_script || exit 1
            create_backup
            ;;
        help|--help|-h)
            cat << EOF
LibreRouterOS Build Script Patcher

Usage: $0 <command> [options]

Commands:
    apply       Apply patches to make script respect umbrella repo config
    remove      Remove patches and restore original behavior
    restore     Alias for remove
    status      Show current patch status
    diff        Show differences between original and patched versions
    backup      Create backup of original script
    help        Show this help message

The patcher modifies librerouteros_build.sh to:
- Read feed configurations from environment variables
- Integrate with umbrella repository versions.conf
- Preserve original behavior as fallback

Environment Variables Used:
    LIBREMESH_FEED      LibreMesh packages feed configuration
    LIBREROUTER_FEED    LibreRouter packages feed configuration  
    AMPR_FEED           AMPR packages feed configuration
    TMATE_FEED          TMATE packages feed configuration
    LIME_BUILD_MODE     Build mode (development/release)

Examples:
    $0 apply                    # Apply patches
    $0 status                   # Check patch status
    $0 remove                   # Remove patches
    $0 diff                     # Show changes made

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