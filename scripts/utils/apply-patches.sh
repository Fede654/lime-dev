#!/bin/bash
#
# Apply lime-dev patches to repositories
# Applies git patches to source repositories in /repos
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PATCHES_DIR="$LIME_BUILD_DIR/patches"
REPOS_DIR="${LIME_BUILD_DIR}/repos"

# Error tracking
declare -g PATCH_ERRORS=0
declare -g PATCH_WARNINGS=0
declare -g PATCH_SUCCESS=0
declare -g APPLIED_PATCHES=()
declare -g FAILED_PATCHES=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[PATCHES]${NC} $1"; }
print_success() { echo -e "${GREEN}[PATCHES]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[PATCHES]${NC} $1"; PATCH_WARNINGS=$((PATCH_WARNINGS + 1)); }
print_error() { echo -e "${RED}[PATCHES]${NC} $1"; PATCH_ERRORS=$((PATCH_ERRORS + 1)); }

# Validation functions
validate_git_patch() {
    local patch_file="$1"
    local patch_name="$2"
    
    # Check if patch file exists and is readable
    if [[ ! -f "$patch_file" ]]; then
        print_error "Patch file not found: $patch_name"
        return 1
    fi
    
    if [[ ! -r "$patch_file" ]]; then
        print_error "Cannot read patch file: $patch_name"
        return 1
    fi
    
    # Check file size (avoid empty files)
    if [[ ! -s "$patch_file" ]]; then
        print_warning "Patch file is empty: $patch_name"
        return 2
    fi
    
    # Basic patch format validation
    if ! head -1 "$patch_file" | grep -q "^diff --git\|^---\|^From:" 2>/dev/null; then
        print_warning "Patch file may not be in standard format: $patch_name"
        return 2
    fi
    
    return 0
}

validate_git_repository() {
    local repo_dir="$1"
    local repo_name="$2"
    
    if [[ ! -d "$repo_dir" ]]; then
        print_error "Repository directory not found: $repo_name"
        return 1
    fi
    
    if [[ ! -d "$repo_dir/.git" ]]; then
        print_error "Not a git repository: $repo_name"
        return 1
    fi
    
    return 0
}

usage() {
    cat << EOF
Apply lime-dev Git Patches

Usage: $0 [OPTIONS]

Options:
    --dry-run      Show what patches would be applied without applying
    --validate     Validate patch files without applying them
    --list         List available patches
    --verbose      Show detailed patch application
    -h, --help     Show this help

Examples:
    $0                    # Apply all git patches with validation
    $0 --dry-run         # Preview patch application
    $0 --validate        # Validate patch files without applying
    $0 --list            # Show available patches
    $0 --verbose         # Apply patches with detailed output

This script applies git patches from the patches/ directory to the 
corresponding repositories in repos/. Patches are applied using 
'git apply' with fallback to 'patch' command.

Patch naming convention:
  - librerouteros-*.patch → repos/librerouteros/
  - lime-packages-*.patch → repos/lime-packages/
  - openwrt-*.patch → repos/openwrt/
  - remove-luci-*.patch → repos/librerouteros/

EOF
}

list_patches() {
    print_info "Available git patches in $PATCHES_DIR:"
    echo
    
    if [[ ! -d "$PATCHES_DIR" ]]; then
        print_warning "No patches directory found"
        return 0
    fi
    
    local patch_count=0
    
    # List git patch files
    while IFS= read -r -d '' patch_file; do
        local rel_path="${patch_file#$PATCHES_DIR/}"
        echo "  🔧 $rel_path"
        patch_count=$((patch_count + 1))
    done < <(find "$PATCHES_DIR" -maxdepth 1 -type f -name "*.patch" -print0 2>/dev/null)
    
    if [[ $patch_count -eq 0 ]]; then
        print_info "No patch files found"
    else
        echo
        print_success "Found $patch_count patch files"
    fi
}

apply_git_patches() {
    local dry_run="$1"
    local verbose="$2"
    
    if [[ ! -d "$REPOS_DIR" ]]; then
        print_error "Repositories directory not found: $REPOS_DIR"
        return 1
    fi
    
    print_info "Applying git patches..."
    
    local patches_applied=0
    local patches_failed=0
    
    while IFS= read -r -d '' patch_file; do
        local patch_name="$(basename "$patch_file")"
        
        [[ "$verbose" == "true" ]] && print_info "Processing git patch: $patch_name"
        
        # Pre-flight validation
        if ! validate_git_patch "$patch_file" "$patch_name"; then
            local validation_result=$?
            if [[ $validation_result -eq 1 ]]; then
                FAILED_PATCHES+=("git/$patch_name")
                ((patches_failed++))
                continue
            fi
            # validation_result 2 is warning, continue but track it
        fi
        
        # Determine target repository based on patch name
        local target_repo=""
        case "$patch_name" in
            librerouteros-*)
                target_repo="$REPOS_DIR/librerouteros"
                ;;
            lime-packages-*)
                target_repo="$REPOS_DIR/lime-packages"
                ;;
            openwrt-*)
                target_repo="$REPOS_DIR/openwrt"
                ;;
            remove-luci-*)
                target_repo="$REPOS_DIR/librerouteros"
                ;;
            *)
                print_warning "Cannot determine target repository for patch: $patch_name"
                PATCH_WARNINGS=$((PATCH_WARNINGS + 1))
                continue
                ;;
        esac
        
        # Validate target repository
        if ! validate_git_repository "$target_repo" "$(basename "$target_repo")"; then
            FAILED_PATCHES+=("git/$patch_name")
            ((patches_failed++))
            continue
        fi
        
        if [[ "$dry_run" == "true" ]]; then
            echo "  Would apply git patch: $patch_name → $(basename "$target_repo")"
            ((patches_applied++))
        else
            pushd "$target_repo" > /dev/null
            
            # Check if patch can be applied
            if git apply --check "$patch_file" 2>/dev/null; then
                if git apply "$patch_file" 2>/dev/null; then
                    APPLIED_PATCHES+=("git/$patch_name")
                    PATCH_SUCCESS=$((PATCH_SUCCESS + 1))
                    ((patches_applied++))
                    [[ "$verbose" == "true" ]] && print_success "Applied git patch: $patch_name"
                else
                    print_error "Failed to apply git patch: $patch_name"
                    FAILED_PATCHES+=("git/$patch_name")
                    ((patches_failed++))
                fi
            else
                # Try with patch command as fallback
                if patch -p1 --dry-run < "$patch_file" >/dev/null 2>&1; then
                    if patch -p1 < "$patch_file" >/dev/null 2>&1; then
                        APPLIED_PATCHES+=("git/$patch_name")
                        PATCH_SUCCESS=$((PATCH_SUCCESS + 1))
                        ((patches_applied++))
                        [[ "$verbose" == "true" ]] && print_success "Applied patch (fallback): $patch_name"
                    else
                        print_error "Failed to apply patch: $patch_name"
                        FAILED_PATCHES+=("git/$patch_name")
                        ((patches_failed++))
                    fi
                else
                    print_warning "Patch may already be applied: $patch_name"
                    PATCH_WARNINGS=$((PATCH_WARNINGS + 1))
                fi
            fi
            
            popd > /dev/null
        fi
        
    done < <(find "$PATCHES_DIR" -maxdepth 1 -type f -name "*.patch" -print0)
    
    # Report results
    if [[ $patches_applied -gt 0 ]]; then
        print_success "Successfully applied $patches_applied git patches"
    fi
    if [[ $patches_failed -gt 0 ]]; then
        print_error "Failed to apply $patches_failed git patches"
        return 1
    fi
    
    return 0
}

validate_all_patches() {
    print_info "Validating all git patch files..."
    local validation_errors=0
    local validation_warnings=0
    
    # Validate git patches
    while IFS= read -r -d '' patch_file; do
        local patch_name="$(basename "$patch_file")"
        echo -n "  Checking $patch_name..."
        if validate_git_patch "$patch_file" "$patch_name"; then
            echo " ✓"
        else
            local result=$?
            if [[ $result -eq 1 ]]; then
                echo " ✗"
                ((validation_errors++))
            else
                echo " ⚠"
                ((validation_warnings++))
            fi
        fi
    done < <(find "$PATCHES_DIR" -maxdepth 1 -type f -name "*.patch" -print0)
    
    # Reset counters since validate_git_patch increments global counters
    PATCH_ERRORS=0
    PATCH_WARNINGS=0
    
    echo
    if [[ $validation_errors -eq 0 ]]; then
        print_success "All patch files passed validation"
        if [[ $validation_warnings -gt 0 ]]; then
            print_warning "$validation_warnings patches had warnings"
        fi
        return 0
    else
        print_error "$validation_errors patches failed validation"
        return 1
    fi
}

main() {
    local dry_run="false"
    local verbose="false"
    local list_only="false"
    local validate_only="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --validate)
                validate_only="true"
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
    
    if [[ "$validate_only" == "true" ]]; then
        validate_all_patches
        exit $?
    fi
    
    print_info "lime-dev Git Patch Application System"
    print_info "Repositories directory: $REPOS_DIR"
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
    
    # Check if repositories directory exists
    if [[ ! -d "$REPOS_DIR" ]]; then
        print_error "Repositories directory not found: $REPOS_DIR"
        print_error "Run 'lime init' first to initialize repositories"
        exit 1
    fi
    
    # Apply git patches with error tracking
    local total_errors=0
    
    apply_git_patches "$dry_run" "$verbose" || ((total_errors++))
    
    echo
    
    # Comprehensive results summary
    if [[ "$dry_run" == "true" ]]; then
        print_info "Dry run completed - no repositories were modified"
        print_info "Patches that would be applied: ${#APPLIED_PATCHES[@]}"
    else
        echo "📊 Git Patch Application Summary:"
        echo "  ✅ Successfully applied: $PATCH_SUCCESS patches"
        
        if [[ $PATCH_WARNINGS -gt 0 ]]; then
            echo "  ⚠️  Warnings: $PATCH_WARNINGS"
        fi
        
        if [[ $PATCH_ERRORS -gt 0 ]]; then
            echo "  ❌ Errors: $PATCH_ERRORS"
        fi
        
        echo
        
        if [[ ${#APPLIED_PATCHES[@]} -gt 0 ]]; then
            print_success "Applied patches:"
            for patch in "${APPLIED_PATCHES[@]}"; do
                echo "  ✓ $patch"
            done
            echo
        fi
        
        if [[ ${#FAILED_PATCHES[@]} -gt 0 ]]; then
            print_error "Failed patches:"
            for patch in "${FAILED_PATCHES[@]}"; do
                echo "  ✗ $patch"
            done
            echo
        fi
        
        # Final status
        if [[ $total_errors -eq 0 && $PATCH_ERRORS -eq 0 ]]; then
            print_success "All git patches applied successfully"
        else
            print_error "Patch application completed with errors"
            print_error "Check the failed patches above and resolve issues"
            exit 1
        fi
    fi
}

main "$@"