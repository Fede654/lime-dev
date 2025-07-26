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

# Parse package source configuration using unified [sources] system
get_package_source() {
    local package_name="$1"
    local mode="${2:-default}"
    local config_file="${3:-$VERSIONS_CONFIG}"
    
    # Use unified parse_source function from versions-parser.sh
    parse_source "$package_name" "$mode" "$config_file"
}

# Parse makefile patch configuration
get_makefile_patch_config() {
    local package_name="$1"
    local config_file="${2:-$VERSIONS_CONFIG}"
    
    parse_config "makefile_patches" "$package_name" "$config_file"
}

# Build lime-app if needed for local development
build_lime_app_if_needed() {
    local source_location="$1"
    
    if [[ ! -d "$source_location" ]]; then
        print_error "lime-app source directory not found: $source_location"
        return 1
    fi
    
    print_info "Building lime-app for local development..."
    
    # Check if build directory exists and is recent
    local build_dir="$source_location/build"
    local src_dir="$source_location/src"
    
    if [[ -d "$build_dir" && -d "$src_dir" ]]; then
        # Check if build is newer than source changes
        local build_time=$(stat -c %Y "$build_dir" 2>/dev/null || echo 0)
        local src_time=$(find "$src_dir" -type f -newer "$build_dir" -print -quit 2>/dev/null)
        
        if [[ -n "$src_time" ]] || [[ ! -f "$build_dir/index.html" ]]; then
            print_info "Source changes detected, rebuilding lime-app..."
        else
            print_info "lime-app build is up to date"
            return 0
        fi
    fi
    
    # Build lime-app
    cd "$source_location"
    if [[ -f "package.json" ]] && command -v npm >/dev/null 2>&1; then
        print_info "Running npm run build:production..."
        if npm run build:production; then
            print_info "lime-app build completed successfully"
        else
            print_error "lime-app build failed"
            return 1
        fi
    else
        print_warning "npm or package.json not found, skipping build"
    fi
    
    cd - >/dev/null
    return 0
}

# Generate source-specific Makefile variables
generate_makefile_variables() {
    local source_spec="$1"
    local package_name="$2"
    
    # Parse source_spec: source_type:source_location:version
    IFS=':' read -r source_type source_location version <<< "$source_spec"
    
    case "$source_type" in
        "local")
            # Pre-evaluate git hash to avoid make shell evaluation issues
            local git_hash=$(cd "$source_location" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')
            if [[ "$package_name" == "lime-app" ]]; then
                # lime-app specific: skip source download, copy pre-built files in Build/Prepare
                echo "PKG_VERSION=dev-${git_hash}"
                # IMPORTANT: Do NOT set PKG_BUILD_DIR to source location - it corrupts our working directory
                # No PKG_SOURCE, PKG_SOURCE_URL, or PKG_HASH for local builds
            else
                # Other packages: use git protocol for local development
                echo "PKG_SOURCE_PROTO=git"
                echo "PKG_SOURCE_URL=file://$source_location"
                echo "PKG_SOURCE_VERSION=$version"
                echo "PKG_SOURCE=\$(PKG_NAME)-\$(PKG_VERSION).tar.gz"
                echo "PKG_VERSION=dev-${git_hash}"
            fi
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
    
    # Create backup of original Makefile and restore it for clean patching
    local backup_path="${makefile_path}.lime-dev-backup"
    if [[ ! -f "$backup_path" ]]; then
        cp "$makefile_path" "$backup_path"
        print_info "Created backup: $backup_path"
    else
        # Restore from backup to ensure clean patching (idempotent)
        cp "$backup_path" "$makefile_path"
        print_info "Restored from backup for clean patching: $backup_path"
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
            
            # lime-app specific patching
            if [[ "$package_name" == "lime-app" ]]; then
                # For lime-app, we need to replace both variables and Build sections
                local source_location=$(echo "$source_spec" | cut -d':' -f2)
                
                # For lime-app, add variables before include, Build/Prepare after include
                # Pre-evaluate git hash to avoid make shell evaluation issues
                local git_hash=$(cd "$source_location" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')
                {
                    echo "# Development mode source injection - added by lime-dev"
                    echo "PKG_VERSION:=dev-${git_hash}"
                    echo ""
                } > "$temp_vars.additions"
                
                {
                    echo ""
                    echo "# lime-app local development Build/Prepare override"
                    echo "define Build/Prepare"
                    echo "	\$(INSTALL_DIR) \$(PKG_BUILD_DIR)"
                    echo "	\$(CP) $source_location/build \$(PKG_BUILD_DIR)/"
                    echo "endef"
                    echo ""
                } > "$temp_vars.build_prepare"
                
                # Remove existing variables and Build sections, add vars after PKG_NAME, Build/Prepare after package.mk include
                awk '
                    /^PKG_NAME:=/ { print; getline; while (getline < "'$temp_vars.additions'") print; next }
                    /^PKG_VERSION:=|^PKG_SOURCE:=|^PKG_SOURCE_URL:=|^PKG_SOURCE_PROTO:=|^PKG_SOURCE_VERSION:=|^PKG_HASH:=/ { next }
                    /^define Build\/Prepare/,/^endef/ { next }
                    /^include.*package\.mk/ { print; while (getline < "'$temp_vars.build_prepare'") print; next }
                    /\$\(BUILD_DIR\)\/build/ { gsub(/\$\(BUILD_DIR\)/, "$(PKG_BUILD_DIR)"); print; next }
                    { print }
                ' "$makefile_path" > "$temp_makefile"
                
                rm -f "$temp_vars.build_prepare"
            else
                # Standard patching for other packages
                awk '
                    /^PKG_NAME:=/ { print; getline; while (getline < "'$temp_vars.additions'") print; next }
                    /^PKG_VERSION:=|^PKG_SOURCE:=|^PKG_SOURCE_URL:=|^PKG_SOURCE_PROTO:=|^PKG_SOURCE_VERSION:=/ { next }
                    { print }
                ' "$makefile_path" > "$temp_makefile"
            fi
            
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
    return 0
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
        
        # lime-app specific: Build npm project for local mode
        if [[ "$package_name" == "lime-app" && "$mode" == "local" ]]; then
            local source_type=$(echo "$source_spec" | cut -d':' -f1)
            if [[ "$source_type" == "local" ]]; then
                local source_location=$(echo "$source_spec" | cut -d':' -f2)
                if ! build_lime_app_if_needed "$source_location"; then
                    print_error "Failed to build lime-app, skipping Makefile patching"
                    ((failed_count++))
                    continue
                fi
            fi
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
            print_info "Successfully patched $makefile_path"
            patched_count=$((patched_count + 1))
        else
            failed_count=$((failed_count + 1))
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
    mode                Source mode (default|local) [default: default]
    build_dir           Build directory path [default: ./build]

Environment Variables:
    LIME_BUILD_MODE     Default build mode

Examples:
    package-source-injector.sh apply default
    package-source-injector.sh apply local  
    package-source-injector.sh restore
    package-source-injector.sh test local
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