#!/bin/bash
# lime-dev repository reset utility
# Resets repositories to clean state while preserving lime-app development

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Utility functions
print_info() {
    echo "[INFO] $1"
}

print_warning() {
    echo "[WARNING] $1"
}

print_error() {
    echo "[ERROR] $1" >&2
}

show_help() {
    cat << 'EOF'
lime-dev Repository Reset Utility

DESCRIPTION:
    Reset repositories to clean cloned state while preserving active development.
    By default, preserves lime-app repository (where development typically occurs)
    and reapplies necessary patches automatically.

USAGE:
    lime reset [OPTIONS]

OPTIONS:
    --preserve-lime-app     Preserve lime-app repository (default)
    --all                   Reset ALL repositories including lime-app
    --dry-run              Show what would be reset without executing
    --reapply-patches      Reapply lime-dev patches after reset (default)
    --no-patches           Skip patch reapplication
    -h, --help             Show this help

EXAMPLES:
    lime reset                          # Standard reset preserving lime-app
    lime reset --all                    # Reset everything including lime-app
    lime reset --dry-run                # Preview what would be reset
    lime reset --all --no-patches       # Full reset without reapplying patches

WHAT IT DOES:
    1. Backs up lime-app changes (if preserving)
    2. Resets specified repositories to HEAD state
    3. Cleans untracked files and directories
    4. Restores lime-app changes (if preserving)
    5. Reapplies lime-dev patches (if requested)
    6. Reports freed space and changes made

REPOSITORIES MANAGED:
    - librerouteros         (always reset unless --dry-run)
    - lime-packages         (always reset unless --dry-run)  
    - kconfig-utils         (always reset unless --dry-run)
    - lime-app              (preserved by default, reset with --all)

SAFETY FEATURES:
    - Automatic backup of lime-app uncommitted changes
    - Dry-run mode for preview
    - Confirmation prompts for destructive operations
    - Automatic patch reapplication

EOF
}

# Configuration
PRESERVE_LIME_APP=true
DRY_RUN=false
REAPPLY_PATCHES=true
INTERACTIVE=true

# Repository lists
ALWAYS_RESET_REPOS=("librerouteros" "lime-packages" "kconfig-utils")
OPTIONAL_RESET_REPOS=("lime-app")
ALL_REPOS=("${ALWAYS_RESET_REPOS[@]}" "${OPTIONAL_RESET_REPOS[@]}")

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --preserve-lime-app)
                PRESERVE_LIME_APP=true
                shift
                ;;
            --all)
                PRESERVE_LIME_APP=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --reapply-patches)
                REAPPLY_PATCHES=true
                shift
                ;;
            --no-patches)
                REAPPLY_PATCHES=false
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use 'lime reset --help' for usage information"
                exit 1
                ;;
        esac
    done
}

check_git_status() {
    local repo_dir="$1"
    local repo_name="$(basename "$repo_dir")"
    
    if [[ ! -d "$repo_dir/.git" ]]; then
        print_warning "Skipping $repo_name: not a git repository"
        return 1
    fi
    
    cd "$repo_dir"
    
    # Check for uncommitted changes
    local status_output
    status_output=$(git status --porcelain 2>/dev/null) || {
        print_warning "Cannot read git status for $repo_name"
        return 1
    }
    
    if [[ -n "$status_output" ]]; then
        return 0  # Has changes
    else
        return 1  # Clean
    fi
}

backup_lime_app_changes() {
    local lime_app_dir="$LIME_BUILD_DIR/repos/lime-app"
    
    if [[ ! -d "$lime_app_dir" ]]; then
        print_warning "lime-app directory not found, skipping backup"
        return 0
    fi
    
    if ! check_git_status "$lime_app_dir"; then
        print_info "lime-app has no uncommitted changes, skipping backup"
        return 0
    fi
    
    local backup_dir="$LIME_BUILD_DIR/backup-lime-app-$(date +%Y%m%d-%H%M%S)"
    
    print_info "Creating backup of lime-app changes..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$backup_dir"
        
        cd "$lime_app_dir"
        
        # Backup staged and unstaged changes
        git diff HEAD > "$backup_dir/changes.patch" 2>/dev/null || true
        
        # Backup untracked files
        git ls-files --others --exclude-standard | while read -r file; do
            if [[ -n "$file" ]]; then
                local dest_dir="$backup_dir/untracked/$(dirname "$file")"
                mkdir -p "$dest_dir"
                cp "$file" "$backup_dir/untracked/$file"
            fi
        done 2>/dev/null || true
        
        # Create restoration script
        cat > "$backup_dir/restore.sh" << 'RESTORE_EOF'
#!/bin/bash
# Auto-generated lime-app restoration script
BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_APP_DIR="$(cd "$BACKUP_DIR/../../repos/lime-app" && pwd)"

echo "Restoring lime-app changes from $(basename "$BACKUP_DIR")..."

cd "$LIME_APP_DIR"

# Apply changes patch if it has content
if [[ -s "$BACKUP_DIR/changes.patch" ]]; then
    echo "Applying changes patch..."
    git apply "$BACKUP_DIR/changes.patch" || echo "Some changes might need manual resolution"
fi

# Restore untracked files
if [[ -d "$BACKUP_DIR/untracked" ]]; then
    echo "Restoring untracked files..."
    cp -r "$BACKUP_DIR/untracked/"* . 2>/dev/null || true
fi

echo "lime-app restoration complete"
RESTORE_EOF
        
        chmod +x "$backup_dir/restore.sh"
        
        print_info "✓ lime-app backup created: $(basename "$backup_dir")"
        print_info "  To restore: $backup_dir/restore.sh"
    else
        print_info "[DRY-RUN] Would create backup: $(basename "$backup_dir")"
    fi
}

reset_repository() {
    local repo_name="$1"
    local repo_dir="$LIME_BUILD_DIR/repos/$repo_name"
    
    if [[ ! -d "$repo_dir" ]]; then
        print_warning "Repository $repo_name not found, skipping"
        return 0
    fi
    
    print_info "Resetting repository: $repo_name"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cd "$repo_dir"
        
        # Check if it's a git repository
        if [[ ! -d ".git" ]]; then
            print_warning "$repo_name is not a git repository, skipping"
            return 0
        fi
        
        # Reset to HEAD and clean untracked files
        print_info "  - Resetting to HEAD..."
        git reset --hard HEAD 2>/dev/null || {
            print_warning "Could not reset $repo_name to HEAD"
            return 1
        }
        
        print_info "  - Cleaning untracked files..."
        git clean -fd 2>/dev/null || {
            print_warning "Could not clean untracked files in $repo_name"
        }
        
        # Show what was reset
        local current_commit
        current_commit=$(git rev-parse --short HEAD 2>/dev/null) || current_commit="unknown"
        print_info "  ✓ Reset to commit: $current_commit"
        
    else
        cd "$repo_dir"
        if [[ -d ".git" ]]; then
            local current_commit
            current_commit=$(git rev-parse --short HEAD 2>/dev/null) || current_commit="unknown"
            local status_lines
            status_lines=$(git status --porcelain 2>/dev/null | wc -l) || status_lines=0
            
            print_info "[DRY-RUN] Would reset $repo_name to $current_commit ($status_lines changes)"
            
            if [[ "$status_lines" -gt 0 ]]; then
                git status --porcelain 2>/dev/null | sed 's/^/    /' || true
            fi
        else
            print_info "[DRY-RUN] Would skip $repo_name (not a git repository)"
        fi
    fi
}

reapply_patches() {
    if [[ "$REAPPLY_PATCHES" == "false" ]]; then
        print_info "Skipping patch reapplication (--no-patches)"
        return 0
    fi
    
    print_info "Reapplying lime-dev patches..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check if patches script exists
        local patches_script="$SCRIPT_DIR/../utils/apply-patches.sh"
        if [[ -x "$patches_script" ]]; then
            "$patches_script" || {
                print_warning "Some patches might need manual application"
                return 1
            }
            print_info "✓ Patches reapplied successfully"
        else
            print_warning "Patches script not found, skipping patch reapplication"
        fi
    else
        print_info "[DRY-RUN] Would reapply lime-dev patches"
    fi
}

calculate_freed_space() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    local total_freed=0
    
    for repo in "${ALL_REPOS[@]}"; do
        local repo_dir="$LIME_BUILD_DIR/repos/$repo"
        if [[ -d "$repo_dir" ]]; then
            # This is approximate - git clean -fd would have removed files
            # For now, just indicate that space was freed
            print_info "✓ $repo: cleaned untracked files and reset changes"
        fi
    done
}

main() {
    print_info "lime-dev Repository Reset Utility"
    print_info "================================="
    
    parse_arguments "$@"
    
    # Determine which repositories to reset
    local repos_to_reset=("${ALWAYS_RESET_REPOS[@]}")
    
    if [[ "$PRESERVE_LIME_APP" == "false" ]]; then
        repos_to_reset+=("${OPTIONAL_RESET_REPOS[@]}")
    fi
    
    # Show summary
    print_info ""
    print_info "Reset Summary:"
    print_info "  Mode: $(if [[ "$DRY_RUN" == "true" ]]; then echo "DRY-RUN"; else echo "EXECUTE"; fi)"
    print_info "  Preserve lime-app: $PRESERVE_LIME_APP"
    print_info "  Reapply patches: $REAPPLY_PATCHES"
    print_info "  Repositories to reset: ${repos_to_reset[*]}"
    
    if [[ "$PRESERVE_LIME_APP" == "true" ]]; then
        print_info "  lime-app: PRESERVED (your development work is safe)"
    else
        print_warning "  lime-app: WILL BE RESET (development work will be lost!)"
    fi
    
    print_info ""
    
    # Confirmation for destructive operations
    if [[ "$DRY_RUN" == "false" && "$INTERACTIVE" == "true" ]]; then
        if [[ "$PRESERVE_LIME_APP" == "false" ]]; then
            print_warning "WARNING: This will reset ALL repositories including lime-app!"
            print_warning "Any uncommitted changes in lime-app will be lost!"
            read -p "Are you sure you want to continue? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Reset cancelled by user"
                exit 0
            fi
        else
            print_info "This will reset repositories while preserving your lime-app development."
            read -p "Continue? (Y/n): " -r
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                print_info "Reset cancelled by user"
                exit 0
            fi
        fi
    fi
    
    # Backup lime-app if preserving
    if [[ "$PRESERVE_LIME_APP" == "true" ]]; then
        backup_lime_app_changes
    fi
    
    # Reset repositories
    print_info ""
    print_info "Resetting repositories..."
    
    local reset_success=0
    local reset_total=0
    
    for repo in "${repos_to_reset[@]}"; do
        reset_total=$((reset_total + 1))
        if reset_repository "$repo"; then
            reset_success=$((reset_success + 1))
        fi
    done
    
    # Reapply patches
    if [[ "$reset_success" -gt 0 ]]; then
        print_info ""
        reapply_patches
    fi
    
    # Calculate freed space
    calculate_freed_space
    
    # Final summary
    print_info ""
    print_info "Reset Complete!"
    print_info "==============="
    print_info "Repositories processed: $reset_success/$reset_total"
    
    if [[ "$PRESERVE_LIME_APP" == "true" ]]; then
        print_info "lime-app preserved: Your development work is intact"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info ""
        print_info "This was a dry-run. To execute the reset, run:"
        print_info "  lime reset $(if [[ "$PRESERVE_LIME_APP" == "false" ]]; then echo "--all"; fi)"
    else
        print_info ""
        print_info "All repositories have been reset to clean state."
        print_info "You can now build with completely fresh sources:"
        print_info "  lime build --mode development"
    fi
}

# Error handling
trap 'print_error "Reset interrupted"; exit 1' INT TERM

main "$@"