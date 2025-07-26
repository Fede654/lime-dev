#!/usr/bin/env bash
#
# Update all repositories in repos/ directory
# Fetches latest changes and pulls from appropriate branches
#

set -e

WORK_DIR="$(pwd)"
REPOS_DIR="$WORK_DIR/repos"

print_info() {
    echo "[INFO] $1"
}

print_error() {
    echo "[ERROR] $1" >&2
}

print_success() {
    echo "[SUCCESS] $1"
}

# Check if running from lime-build directory
check_directory() {
    local dir_name="$(basename "$PWD")"
    if [[ ! "$dir_name" =~ ^(lime-build|lime-dev)$ ]]; then
        print_error "This script should be run from the lime-dev (or lime-build) directory"
        exit 1
    fi
    
    if [[ ! -d "repos" ]]; then
        print_error "repos/ directory not found. Run setup-lime-dev.sh first."
        exit 1
    fi
}

# Update a specific repository with smart remote tracking
update_repo() {
    local repo_name="$1"
    local default_branch="$2"
    local repo_path="$REPOS_DIR/$repo_name"
    
    if [[ ! -d "$repo_path" ]]; then
        print_error "$repo_name not found in repos/"
        return 1
    fi
    
    print_info "Updating $repo_name..."
    cd "$repo_path"
    
    # Get current branch and tracking info
    current_branch=$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD)
    
    # Fetch all remotes
    print_info "  Fetching from all remotes..."
    git fetch --all --prune
    
    # Check if we're on a detached HEAD (like OpenWrt tag)
    if [[ "$current_branch" == "HEAD" ]] || git rev-parse --verify HEAD >/dev/null 2>&1 && ! git symbolic-ref HEAD >/dev/null 2>&1; then
        print_info "  Repository is on detached HEAD (likely a tag), skipping pull"
    else
        # Get the current tracking branch info
        local tracking_info=$(git status -b --porcelain=v1 2>/dev/null | head -1)
        local upstream_remote=""
        local upstream_branch=""
        
        # Parse tracking info to get remote and branch
        if [[ "$tracking_info" =~ \[([^/]+)/([^\]]+) ]]; then
            upstream_remote="${BASH_REMATCH[1]}"
            upstream_branch="${BASH_REMATCH[2]}"
        fi
        
        # Determine what to pull from
        if [[ -n "$upstream_remote" && -n "$upstream_branch" ]]; then
            # Current branch has upstream tracking - use it
            print_info "  Pulling from tracked upstream: $upstream_remote/$upstream_branch..."
            if git show-ref --verify --quiet "refs/remotes/$upstream_remote/$upstream_branch"; then
                git pull "$upstream_remote" "$upstream_branch"
                print_success "  $repo_name updated from $upstream_remote/$upstream_branch"
            else
                print_error "  Tracked upstream $upstream_remote/$upstream_branch not found"
            fi
        else
            # No upstream tracking, try origin with current or default branch
            local branch_to_pull="${current_branch:-$default_branch}"
            print_info "  No upstream tracking found, trying origin/$branch_to_pull..."
            
            if git show-ref --verify --quiet "refs/remotes/origin/$branch_to_pull"; then
                git pull origin "$branch_to_pull"
                print_success "  $repo_name updated from origin/$branch_to_pull"
            else
                print_error "  Branch origin/$branch_to_pull not found, skipping pull"
            fi
        fi
    fi
    
    # Show current status with tracking info
    local current_commit=$(git rev-parse --short HEAD)
    local current_ref=$(git describe --tags --exact-match 2>/dev/null || git branch --show-current 2>/dev/null || echo "detached")
    local tracking_status=$(git status -b --porcelain=v1 2>/dev/null | head -1 | grep -o '\[.*\]' || echo "")
    print_info "  Current: $current_ref ($current_commit) $tracking_status"
    
    cd "$WORK_DIR"
}

# Update all repositories
update_all_repos() {
    print_info "Updating all repositories in repos/ directory..."
    
    # Update each repository - now respects current branch tracking
    # Default branches provided as fallback only
    update_repo "lime-app" "master"
    update_repo "lime-packages" "master" 
    update_repo "librerouteros" "main"
    update_repo "kconfig-utils" "main"
    
    # Special handling for OpenWrt (tagged version)
    if [[ -d "$REPOS_DIR/openwrt" ]]; then
        print_info "Checking OpenWrt status..."
        cd "$REPOS_DIR/openwrt"
        local current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "none")
        print_info "  OpenWrt is at: $current_tag"
        cd "$WORK_DIR"
    fi
    
    print_success "All repositories updated!"
    
    # Apply lime-dev patches to librerouteros build script
    print_info "Applying lime-dev integration patches..."
    if [[ -f "$WORK_DIR/scripts/utils/patch-librerouteros-build.sh" ]]; then
        "$WORK_DIR/scripts/utils/patch-librerouteros-build.sh" apply
    else
        print_error "Patch script not found, manual intervention may be required"
    fi
}

# Show repository status
show_status() {
    print_info "Repository status:"
    
    for repo in lime-app lime-packages librerouteros kconfig-utils openwrt; do
        if [[ -d "$REPOS_DIR/$repo" ]]; then
            cd "$REPOS_DIR/$repo"
            local current_commit=$(git rev-parse --short HEAD)
            local current_ref=$(git describe --tags --exact-match 2>/dev/null || git branch --show-current 2>/dev/null || echo "detached")
            local status=$(git status --porcelain | wc -l)
            local status_msg=""
            
            if [[ $status -gt 0 ]]; then
                status_msg=" (${status} changes)"
            fi
            
            echo "  $repo: $current_ref ($current_commit)$status_msg"
            cd "$WORK_DIR"
        else
            echo "  $repo: NOT FOUND"
        fi
    done
}

# Main function
main() {
    check_directory
    
    case "${1:-update}" in
        "update"|"pull")
            update_all_repos
            ;;
        "status"|"info")
            show_status
            ;;
        "graph"|"deps"|"dependencies")
            "$WORK_DIR/scripts/utils/dependency-graph.sh" ascii
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  update, pull       Update all repositories (default)"
            echo "  status, info       Show repository status"
            echo "  graph, deps        Show dependency graph"
            echo "  help              Show this help"
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"