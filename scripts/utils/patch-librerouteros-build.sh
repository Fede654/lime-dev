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
    if [[ -f "$LIBREROUTEROS_BUILD_SCRIPT" ]]; then
        grep -q "LIME-DEV PATCHES APPLIED\|LIME-DEV PATCH APPLIED" "$LIBREROUTEROS_BUILD_SCRIPT" 2>/dev/null
    else
        return 1
    fi
}

# Apply LuCI removal patch - disables LuCI when lime-app is enabled
apply_luci_removal_patch() {
    local script_file="$1"
    local patch_file="$LIME_BUILD_DIR/patches/remove-luci-with-lime-app.patch"
    
    print_info "Applying LuCI removal patch..."
    
    if [[ ! -f "$patch_file" ]]; then
        print_warn "LuCI removal patch not found: $patch_file"
        return 0
    fi
    
    # Apply the patch file to the build script
    if patch --dry-run -p1 -d "$(dirname "$script_file")" < "$patch_file" >/dev/null 2>&1; then
        patch -p1 -d "$(dirname "$script_file")" < "$patch_file"
        print_info "✓ LuCI removal patch applied successfully"
    else
        print_warn "LuCI removal patch could not be applied (already applied or conflicts)"
        # Fall back to manual application
        apply_luci_removal_manual "$script_file"
    fi
}

# Manual LuCI removal application for cases where patch fails
apply_luci_removal_manual() {
    local script_file="$1"
    
    # Check if already applied
    if grep -q "configure_remove_luci" "$script_file" 2>/dev/null; then
        print_info "LuCI removal already applied manually"
        return 0
    fi
    
    print_info "Applying LuCI removal manually..."
    
    # Add configure_remove_luci function after configure_remove_unused_packages
    local luci_function='
function configure_remove_luci()
{
	kconfig_unset CONFIG_PACKAGE_luci-base
	kconfig_unset CONFIG_PACKAGE_luci-compat
	kconfig_unset CONFIG_PACKAGE_luci-lua-runtime
	kconfig_unset CONFIG_PACKAGE_luci-lib-base
	kconfig_unset CONFIG_PACKAGE_luci-lib-httpclient
	kconfig_unset CONFIG_PACKAGE_luci-lib-httpprotoutils
	kconfig_unset CONFIG_PACKAGE_luci-lib-ip
	kconfig_unset CONFIG_PACKAGE_luci-lib-jsonc
	kconfig_unset CONFIG_PACKAGE_luci-lib-nixio
}'
    
    # Insert the function after configure_remove_unused_packages
    sed -i '/^function configure_remove_unused_packages()/,/^}$/a\
\
'"$luci_function" "$script_file"
    
    # Add call to configure_remove_luci in configure_librerouteros function
    local luci_call_with_comment='
	# Remove LuCI packages - lime-app replaces web interface completely
	# This prevents OpenWrt defconfig from auto-enabling conflicting LuCI components
	configure_remove_luci
'
    
    # Insert the call after lime-app and lime-docs-minimal are set
    sed -i '/kconfig_set CONFIG_PACKAGE_lime-docs-minimal/a\
'"$luci_call_with_comment" "$script_file"
    
    print_info "✓ LuCI removal applied manually"
}

# Apply single patch file to script
apply_patch_file() {
    local script_file="$1"
    local patch_name="$2"
    local patch_file="$LIME_BUILD_DIR/patches/$patch_name"
    
    if [[ ! -f "$patch_file" ]]; then
        print_warn "Patch not found: $patch_file"
        return 1
    fi
    
    if [[ ! -f "$script_file" ]]; then
        print_warn "Script file not found: $script_file"
        return 1
    fi
    
    if patch --dry-run -p1 -d "$(dirname "$script_file")" < "$patch_file" >/dev/null 2>&1; then
        patch -p1 -d "$(dirname "$script_file")" < "$patch_file"
        print_info "✓ Applied: $patch_name"
    else
        print_warn "Could not apply: $patch_name (already applied or conflicts)"
        return 1
    fi
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
    
    # Remove the entire LIME_BUILD_MODE switch and replace with simple environment variable
    print_info "Removing LIME_BUILD_MODE switch..."
    
    # Create replacement content in a temporary file to avoid escaping issues
    cat > "/tmp/lime_simplified_feed.txt" << 'EOF'
# LIME-DEV SIMPLIFIED FEED CONFIGURATION: Direct environment variable usage
lo:define_default_value LIBREMESH_FEED "${LIBREMESH_FEED:-src-git libremesh https://github.com/libremesh/lime-packages.git;master}"
EOF
    
    # Use .patch files instead of complex sed operations
    print_info "Applying feed configuration patch..."
    if ! apply_patch_file "$temp_script" "librerouteros-feed-config.patch"; then
        print_warn "Feed config patch failed, using fallback"
        # Fallback: Replace the entire switch block with simplified version
        if sed -i '/# LIME-DEV UNIFIED BUILD MODE: Respect LIME_BUILD_MODE for feed selection/,/^esac$/{
r /tmp/lime_simplified_feed.txt
d
}' "$temp_script" 2>/dev/null; then
            rm -f "/tmp/lime_simplified_feed.txt"
            print_info "✓ Feed config applied via fallback"
        else
            rm -f "/tmp/lime_simplified_feed.txt"
            print_warn "Feed config fallback also failed"
        fi
    fi
    
    # Apply AMPR enable patch
    apply_patch_file "$temp_script" "librerouteros-ampr-enable.patch" || print_warn "AMPR patch failed"
    
    # Apply LuCI removal patch
    apply_luci_removal_patch "$temp_script"
    
    # Add simple patch marker (only if not already present)
    if ! grep -q "LIME-DEV PATCHES APPLIED" "$temp_script"; then
        sed -i '/^# COPYLEFT$/a\
# LIME-DEV PATCHES APPLIED\
# This script has been patched using .patch files\
# Generated on: '"$(date)"'\
# Patch version: 2.0 (using standard .patch files)\
#' "$temp_script"
    fi
    
    # Replace original script with patched version
    mv "$temp_script" "$LIBREROUTEROS_BUILD_SCRIPT"
    chmod +x "$LIBREROUTEROS_BUILD_SCRIPT"
    
    # Apply LuCI removal patch
    apply_luci_removal_patch "$temp_script"
    
    print_info "✓ Patches applied successfully"
    print_info "  - Feed configurations now respect environment variables"
    print_info "  - Environment integration added"
    print_info "  - LuCI packages disabled when lime-app is enabled"
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