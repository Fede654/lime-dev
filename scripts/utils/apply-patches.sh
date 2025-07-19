#!/bin/bash
#
# Apply lime-dev patches to build environment
# Copies custom patches over upstream package files
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PATCHES_DIR="$LIME_BUILD_DIR/patches"
BUILD_DIR="${LIME_BUILD_DIR}/build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[PATCHES]${NC} $1"; }
print_success() { echo -e "${GREEN}[PATCHES]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[PATCHES]${NC} $1"; }
print_error() { echo -e "${RED}[PATCHES]${NC} $1"; }

usage() {
    cat << EOF
Apply lime-dev Patches

Usage: $0 [OPTIONS]

Options:
    --dry-run      Show what would be patched without applying
    --list         List available patches
    --verbose      Show detailed patch application
    -h, --help     Show this help

Examples:
    $0                    # Apply all patches
    $0 --dry-run         # Preview patch application
    $0 --list            # Show available patches

This script applies custom lime-dev patches to the build environment,
overriding upstream package files with local fixes and enhancements.

EOF
}

list_patches() {
    print_info "Available patches in $PATCHES_DIR:"
    echo
    
    if [[ ! -d "$PATCHES_DIR" ]]; then
        print_warning "No patches directory found"
        return 0
    fi
    
    local patch_count=0
    
    while IFS= read -r -d '' patch_file; do
        local rel_path="${patch_file#$PATCHES_DIR/}"
        echo "  📄 $rel_path"
        patch_count=$((patch_count + 1))
    done < <(find "$PATCHES_DIR" -type f \( -name "*.json" -o -name "*.sh" -o -name "*.lua" -o -name "*.conf" -o -name "*.cfg" \) -print0 2>/dev/null)
    
    if [[ $patch_count -eq 0 ]]; then
        print_info "No patch files found"
    else
        echo
        print_success "Found $patch_count patch files"
    fi
}

apply_lime_packages_patches() {
    local dry_run="$1"
    local verbose="$2"
    
    local source_dir="$PATCHES_DIR/lime-packages"
    local target_base="$BUILD_DIR/feeds/libremesh/packages"
    
    if [[ ! -d "$source_dir" ]]; then
        [[ "$verbose" == "true" ]] && print_info "No lime-packages patches found"
        return 0
    fi
    
    print_info "Applying lime-packages patches..."
    
    while IFS= read -r -d '' patch_file; do
        # Calculate relative path from patches/lime-packages/
        local rel_path="${patch_file#$source_dir/}"
        local target_file="$target_base/$rel_path"
        local target_dir="$(dirname "$target_file")"
        
        [[ "$verbose" == "true" ]] && print_info "Processing: $rel_path"
        
        if [[ "$dry_run" == "true" ]]; then
            echo "  Would copy: $rel_path → feeds/libremesh/packages/$rel_path"
        else
            # Create target directory if it doesn't exist
            mkdir -p "$target_dir"
            
            # Copy patch file
            cp "$patch_file" "$target_file"
            [[ "$verbose" == "true" ]] && print_success "Applied: $rel_path"
        fi
        
    done < <(find "$source_dir" -type f -print0)
}

apply_librerouteros_patches() {
    local dry_run="$1"
    local verbose="$2"
    
    local source_dir="$PATCHES_DIR/librerouteros"
    local target_base="$BUILD_DIR/feeds/librerouteros"
    
    if [[ ! -d "$source_dir" ]]; then
        [[ "$verbose" == "true" ]] && print_info "No librerouteros patches found"
        return 0
    fi
    
    print_info "Applying librerouteros patches..."
    
    while IFS= read -r -d '' patch_file; do
        local rel_path="${patch_file#$source_dir/}"
        local target_file="$target_base/$rel_path"
        local target_dir="$(dirname "$target_file")"
        
        [[ "$verbose" == "true" ]] && print_info "Processing: $rel_path"
        
        if [[ "$dry_run" == "true" ]]; then
            echo "  Would copy: $rel_path → feeds/librerouteros/$rel_path"
        else
            mkdir -p "$target_dir"
            cp "$patch_file" "$target_file"
            [[ "$verbose" == "true" ]] && print_success "Applied: $rel_path"
        fi
        
    done < <(find "$source_dir" -type f -print0)
}

apply_openwrt_patches() {
    local dry_run="$1"
    local verbose="$2"
    
    local source_dir="$PATCHES_DIR/openwrt"
    local target_base="$BUILD_DIR/feeds/packages"
    
    if [[ ! -d "$source_dir" ]]; then
        [[ "$verbose" == "true" ]] && print_info "No openwrt patches found"
        return 0
    fi
    
    print_info "Applying openwrt patches..."
    
    while IFS= read -r -d '' patch_file; do
        local rel_path="${patch_file#$source_dir/}"
        local target_file="$target_base/$rel_path"
        local target_dir="$(dirname "$target_file")"
        
        [[ "$verbose" == "true" ]] && print_info "Processing: $rel_path"
        
        if [[ "$dry_run" == "true" ]]; then
            echo "  Would copy: $rel_path → feeds/packages/$rel_path"
        else
            mkdir -p "$target_dir"
            cp "$patch_file" "$target_file"
            [[ "$verbose" == "true" ]] && print_success "Applied: $rel_path"
        fi
        
    done < <(find "$source_dir" -type f -print0)
}

main() {
    local dry_run="false"
    local verbose="false"
    local list_only="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --list)
                list_only="true"
                shift
                ;;
            --verbose)
                verbose="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    if [[ "$list_only" == "true" ]]; then
        list_patches
        exit 0
    fi
    
    print_info "lime-dev Patch Application System"
    print_info "Build directory: $BUILD_DIR"
    print_info "Patches directory: $PATCHES_DIR"
    
    if [[ "$dry_run" == "true" ]]; then
        print_warning "DRY RUN MODE - No files will be modified"
    fi
    
    echo
    
    # Check if patches directory exists
    if [[ ! -d "$PATCHES_DIR" ]]; then
        print_error "Patches directory not found: $PATCHES_DIR"
        exit 1
    fi
    
    # Check if build directory exists
    if [[ ! -d "$BUILD_DIR" ]]; then
        print_error "Build directory not found: $BUILD_DIR"
        print_error "Run a build first to create the build environment"
        exit 1
    fi
    
    # Apply patches by category
    apply_lime_packages_patches "$dry_run" "$verbose"
    apply_librerouteros_patches "$dry_run" "$verbose"
    apply_openwrt_patches "$dry_run" "$verbose"
    
    echo
    if [[ "$dry_run" == "true" ]]; then
        print_info "Dry run completed - no files were modified"
    else
        print_success "All patches applied successfully"
    fi
}

main "$@"