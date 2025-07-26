#!/usr/bin/env bash
#
# Package Source Injector - lime-dev Build System
# ===============================================
# Implements package-level source injection to complete the Source of Truth flow:
# Source of Truth → Feed Config → Package Makefile Patching → Build
#
# This script patches individual package Makefiles within feeds to use sources
# defined in versions.conf instead of hardcoded URLs/versions.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_DEV_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERSIONS_CONFIG="$LIME_DEV_ROOT/configs/versions.conf"
BUILD_DIR="$LIME_DEV_ROOT/build"

# Load source of truth parsing utilities
source "$SCRIPT_DIR/versions-parser.sh"

print_info() {
    echo "[PACKAGE-INJECTOR] $1"
}

print_warning() {
    echo "[PACKAGE-INJECTOR] WARNING: $1" >&2
}

print_error() {
    echo "[PACKAGE-INJECTOR] ERROR: $1" >&2
}

# Parse package source configuration from versions.conf
get_package_source() {
    local package_name="$1"
    local mode="${2:-development}"
    local config_file="${3:-$VERSIONS_CONFIG}"
    
    # Check for mode-specific package source
    local package_key="${package_name}_${mode}"
    local package_source=$(parse_config "package_sources" "$package_key" "$config_file")
    
    if [[ -n "$package_source" ]]; then
        echo "$package_source"
        return 0
    fi
    
    # Fall back to production source
    local production_key="${package_name}_production"
    local production_source=$(parse_config "package_sources" "$production_key" "$config_file")
    
    if [[ -n "$production_source" ]]; then
        echo "$production_source"
        return 0
    fi
    
    # No package source defined
    return 1
}

# Parse makefile patch configuration
get_makefile_patch_config() {
    local package_name="$1"
    local config_file="${2:-$VERSIONS_CONFIG}"
    
    parse_config "makefile_patches" "$package_name" "$config_file"
}

# Generate source-specific Makefile variables
generate_makefile_variables() {
    local source_spec="$1"
    local package_name="$2"
    
    # Parse source_spec: source_type:source_location:version
    IFS=':' read -r source_type source_location version <<< "$source_spec"
    
    case "$source_type" in
        "local")
            # Local repository source - use git protocol for local development
            echo "PKG_SOURCE_PROTO=git"
            echo "PKG_SOURCE_URL=file://$source_location"
            echo "PKG_SOURCE_VERSION=$version"
            echo "PKG_SOURCE=\$(PKG_NAME)-\$(PKG_VERSION).tar.gz"
            echo "PKG_VERSION=dev-\$(shell cd $source_location && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
            ;;
        "git")
            # Git repository source
            echo "PKG_SOURCE_PROTO=git"
            echo "PKG_SOURCE_URL=$source_location"
            echo "PKG_SOURCE_VERSION=$version"
            echo "PKG_SOURCE=\$(PKG_NAME)-\$(PKG_VERSION).tar.gz"
            echo "PKG_VERSION=$version"
            ;;
        "tarball")
            # Tarball source (existing behavior)
            echo "PKG_SOURCE=\$(PKG_NAME)-\$(PKG_VERSION).tar.gz"
            echo "PKG_SOURCE_URL=$source_location/\$(PKG_VERSION)"
            echo "PKG_VERSION=$version"
            ;;
        "feed_default")
            # Use feed's default configuration (no changes)
            return 0
            ;;
        *)
            print_error "Unknown source type: $source_type"
            return 1
            ;;
    esac
}

# Patch a package Makefile with new source configuration
patch_package_makefile() {
    local package_name="$1"
    local makefile_path="$2"
    local source_spec="$3"
    local patch_config="$4"
    local mode="${5:-development}"
    
    if [[ ! -f "$makefile_path" ]]; then
        print_error "Makefile not found: $makefile_path"
        return 1
    fi
    
    print_info "Patching $package_name Makefile for $mode mode"
    
    # Create backup of original Makefile
    local backup_path="${makefile_path}.lime-dev-backup"
    if [[ ! -f "$backup_path" ]]; then
        cp "$makefile_path" "$backup_path"
        print_info "Created backup: $backup_path"
    fi
    
    # Parse patch configuration: patch_type:source_var:url_var:version_var
    IFS=':' read -r patch_type source_var url_var version_var <<< "$patch_config"
    
    # Generate new Makefile variables
    local temp_vars=$(mktemp)
    generate_makefile_variables "$source_spec" "$package_name" > "$temp_vars"
    
    # Apply patches based on patch type
    case "$patch_type" in
        "source_replacement")
            # Replace source, URL, and version variables
            local temp_makefile=$(mktemp)
            
            # Copy original Makefile
            cp "$makefile_path" "$temp_makefile"
            
            # Create a proper replacement file with additions
            {
                echo "# Development mode source injection - added by lime-dev"
                while IFS='=' read -r var value; do
                    if [[ -n "$var" && -n "$value" ]]; then
                        echo "${var}:=${value}"
                    fi
                done < "$temp_vars"
            } > "$temp_vars.additions"
            
            # Remove existing variables and add new ones after PKG_NAME
            awk '
                /^PKG_NAME:=/ { print; getline; while (getline < "'$temp_vars.additions'") print; next }
                /^PKG_VERSION:=|^PKG_SOURCE:=|^PKG_SOURCE_URL:=|^PKG_SOURCE_PROTO:=|^PKG_SOURCE_VERSION:=/ { next }
                { print }
            ' "$makefile_path" > "$temp_makefile"
            
            # Apply the patched Makefile
            mv "$temp_makefile" "$makefile_path"
            rm -f "$temp_vars.additions"
            ;;
        
        "version_override")
            # Only override version-related variables
            while IFS='=' read -r var value; do
                if [[ "$var" =~ PKG_VERSION|PKG_RELEASE ]]; then
                    local escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^$()+?{|]/\\&/g')
                    sed -i "s|^${var}:=.*|${var}:=${escaped_value}|" "$makefile_path"
                fi
            done < "$temp_vars"
            ;;
        
        *)
            print_error "Unknown patch type: $patch_type"
            rm -f "$temp_vars"
            return 1
            ;;
    esac
    
    rm -f "$temp_vars"
    print_info "Successfully patched $makefile_path"
}

# Find package Makefile in feeds
find_package_makefile() {
    local package_name="$1"
    local build_dir="$2"
    
    # Common locations for package Makefiles (note: use underscore instead of dash)
    local package_name_dash=${package_name/_/-}
    local possible_paths=(
        "$build_dir/feeds/libremesh/packages/$package_name/Makefile"
        "$build_dir/feeds/libremesh/packages/$package_name_dash/Makefile"
        "$build_dir/feeds/packages/packages/$package_name/Makefile"
        "$build_dir/feeds/packages/packages/$package_name_dash/Makefile"
        "$build_dir/feeds/luci/applications/$package_name/Makefile"
        "$build_dir/feeds/luci/applications/$package_name_dash/Makefile"
        "$build_dir/feeds/routing/$package_name/Makefile"
        "$build_dir/feeds/routing/$package_name_dash/Makefile"
        "$build_dir/package/feeds/libremesh/$package_name/Makefile"
        "$build_dir/package/feeds/libremesh/$package_name_dash/Makefile"
        "$build_dir/package/feeds/packages/$package_name/Makefile"
        "$build_dir/package/feeds/packages/$package_name_dash/Makefile"
    )
    
    for path in "${possible_paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    # Search more broadly
    find "$build_dir" -name "Makefile" -path "*/$package_name/*" 2>/dev/null | head -1
}

# Restore original Makefiles
restore_original_makefiles() {
    local build_dir="$1"
    
    print_info "Restoring original Makefiles..."
    
    find "$build_dir" -name "*.lime-dev-backup" -type f | while read -r backup_file; do
        local original_file="${backup_file%.lime-dev-backup}"
        if [[ -f "$backup_file" ]]; then
            mv "$backup_file" "$original_file"
            print_info "Restored: $original_file"
        fi
    done
}

# Apply package source injection for a specific mode
apply_package_injection() {
    local mode="${1:-development}"
    local build_dir="${2:-$BUILD_DIR}"
    
    if [[ ! -f "$VERSIONS_CONFIG" ]]; then
        print_error "Versions config not found: $VERSIONS_CONFIG"
        return 1
    fi
    
    if [[ ! -d "$build_dir" ]]; then
        print_error "Build directory not found: $build_dir"
        return 1
    fi
    
    print_info "Applying package source injection for $mode mode"
    
    # Get list of packages that need patching
    local packages_to_patch=$(awk '/^\[makefile_patches\]/{flag=1;next}/^\[/{flag=0}flag && /^[^#]/ && /=/{print $1}' FS='=' "$VERSIONS_CONFIG")
    
    if [[ -z "$packages_to_patch" ]]; then
        print_info "No packages configured for Makefile patching"
        return 0
    fi
    
    local patched_count=0
    local failed_count=0
    
    for package_name in $packages_to_patch; do
        print_info "Processing package: $package_name"
        
        # Get package source configuration
        local source_spec
        if ! source_spec=$(get_package_source "$package_name" "$mode"); then
            print_warning "No source configuration found for $package_name in $mode mode, skipping"
            continue
        fi
        
        # Get makefile patch configuration
        local patch_config
        if ! patch_config=$(get_makefile_patch_config "$package_name"); then
            print_warning "No patch configuration found for $package_name, skipping"
            continue
        fi
        
        # Find the package Makefile
        local makefile_path
        makefile_path=$(find_package_makefile "$package_name" "$build_dir")
        if [[ -z "$makefile_path" || ! -f "$makefile_path" ]]; then
            print_warning "Makefile not found for package $package_name, skipping"
            continue
        fi
        
        # Apply the patch
        if patch_package_makefile "$package_name" "$makefile_path" "$source_spec" "$patch_config" "$mode"; then
            ((patched_count++))
        else
            ((failed_count++))
        fi
    done
    
    print_info "Package source injection complete: $patched_count patched, $failed_count failed"
    
    if [[ $failed_count -gt 0 ]]; then
        return 1
    fi
}

# Main execution
main() {
    local command="${1:-apply}"
    local mode="${2:-${LIME_BUILD_MODE:-development}}"
    local build_dir="${3:-$BUILD_DIR}"
    
    case "$command" in
        "apply")
            apply_package_injection "$mode" "$build_dir"
            ;;
        "restore")
            restore_original_makefiles "$build_dir"
            ;;
        "test")
            print_info "Testing package source injection configuration"
            # Test configuration parsing
            local packages=$(awk '/^\[makefile_patches\]/{flag=1;next}/^\[/{flag=0}flag && /^[^#]/ && /=/{print $1}' FS='=' "$VERSIONS_CONFIG")
            for package in $packages; do
                print_info "Package: $package"
                local source_spec
                if source_spec=$(get_package_source "$package" "$mode"); then
                    print_info "  Source: $source_spec"
                else
                    print_warning "  No source configuration found"
                fi
                local patch_config
                if patch_config=$(get_makefile_patch_config "$package"); then
                    print_info "  Patch config: $patch_config"
                else
                    print_warning "  No patch configuration found"
                fi
            done
            ;;
        "help"|"-h"|"--help")
            cat << 'EOF'
Package Source Injector - lime-dev Build System

Usage: package-source-injector.sh <command> [mode] [build_dir]

Commands:
    apply               Apply package source injection (default)
    restore             Restore original Makefiles from backups
    test                Test configuration parsing
    help                Show this help

Parameters:
    mode                Build mode (development|release) [default: development]
    build_dir           Build directory path [default: ./build]

Environment Variables:
    LIME_BUILD_MODE     Default build mode

Examples:
    package-source-injector.sh apply development
    package-source-injector.sh restore
    package-source-injector.sh test development
EOF
            ;;
        *)
            print_error "Unknown command: $command"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi