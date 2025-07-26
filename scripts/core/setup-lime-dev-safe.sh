#!/usr/bin/env bash
#
# LibreMesh Development Environment Setup - Safe Version
# Non-disruptive setup with user confirmation for changes
#

set -e

WORK_DIR="$(pwd)"
LIME_BUILD_DIR="$WORK_DIR"
CONFIG_FILE="$LIME_BUILD_DIR/configs/versions.conf"
RELEASE_MODE="${LIME_RELEASE_MODE:-false}"
BUILD_REMOTE_ONLY="${LIME_BUILD_REMOTE_ONLY:-false}"

print_info() {
    echo "[INFO] $1"
}

print_error() {
    echo "[ERROR] $1" >&2
}

print_success() {
    echo "[SUCCESS] $1"
}

print_warning() {
    echo "[WARNING] $1" >&2
}

print_question() {
    echo -n "[QUESTION] $1 (y/N): "
}

ask_user() {
    local question="$1"
    local default="${2:-n}"
    
    print_question "$question"
    read -r response
    response="${response:-$default}"
    
    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if running from lime-build directory
check_directory() {
    local dir_name="$(basename "$PWD")"
    if [[ ! "$dir_name" =~ ^(lime-build|lime-dev)$ ]]; then
        print_error "This script should be run from the lime-dev (or lime-build) directory"
        exit 1
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
}

# Parse configuration file
parse_config() {
    print_info "Using configuration: $CONFIG_FILE"
    print_info "Release mode: $RELEASE_MODE"
    
    # Validate configuration integrity before using it
    print_info "Validating configuration integrity..."
    if ! "$SCRIPT_DIR/../utils/validate-config-integrity.sh" validate; then
        case $? in
            1)
                print_error "❌ Configuration integrity check failed"
                print_error "Fix the configuration corruption before proceeding with setup"
                exit 1
                ;;
            2)
                print_info "Auto-fix requested but not yet implemented"
                print_error "Please manually fix the configuration and try again"
                exit 1
                ;;
        esac
    fi
    print_info "✅ Configuration integrity validated"
}

# Get repository configuration
get_repo_config() {
    local repo_name="$1"
    local section="repositories"
    
    # Use new naming convention: append -repo suffix
    local config_key="${repo_name}-repo"
    
    # Check if we should use release overrides
    if [[ "$RELEASE_MODE" == "true" ]]; then
        local release_key="${repo_name}_release"
        if grep -q "^${release_key}=" "$CONFIG_FILE"; then
            section="release_overrides"
            config_key="$release_key"
        fi
    fi
    
    # Extract configuration
    local config=$(grep "^${config_key}=" "$CONFIG_FILE" 2>/dev/null || echo "")
    if [[ -n "$config" ]]; then
        echo "${config#*=}"
    else
        print_error "No configuration found for repository: $1 (looked for key: $config_key)"
        return 1
    fi
}

# Check system dependencies (non-disruptive)
check_dependencies() {
    print_info "Checking system dependencies..."
    
    local missing_deps=()
    local deps=(qemu-system-x86 qemu-utils bridge-utils dnsmasq screen curl wget git build-essential nodejs npm cpio tar gzip)
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1 && ! dpkg -l | grep -q "^ii.*$dep"; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_warning "Missing dependencies: ${missing_deps[*]}"
        print_info "To install: sudo apt-get install ${missing_deps[*]}"
        
        if ask_user "Install missing dependencies now?"; then
            sudo apt-get update
            sudo apt-get install -y "${missing_deps[@]}"
        else
            print_warning "Some features may not work without these dependencies"
        fi
    else
        print_success "All dependencies satisfied"
    fi
}

# Safe repository cloning/updating
safe_clone_repository() {
    local repo_name="$1"
    local config=$(get_repo_config "$repo_name")
    
    if [[ -z "$config" ]]; then
        print_warning "Skipping $repo_name: no configuration found"
        return 0
    fi
    
    IFS='|' read -r repo_url branch remote_name <<< "$config"
    local dir_name="$repo_name"
    
    print_info "Processing $repo_name -> $dir_name"
    print_info "  URL: $repo_url"
    print_info "  Branch: $branch"
    print_info "  Remote: $remote_name"
    
    if [[ ! -d "$dir_name" ]]; then
        print_info "Repository $dir_name not found"
        if ask_user "Clone $dir_name?"; then
            if [[ "$repo_name" == "openwrt" ]]; then
                print_info "  Using developer-specified command"
                git clone -b v24.10.1 --single-branch https://git.openwrt.org/openwrt/openwrt.git "$dir_name"
            elif [[ "$branch" =~ ^v[0-9] ]]; then
                git clone -b "$branch" --single-branch "$repo_url" "$dir_name"
            else
                git clone -b "$branch" "$repo_url" "$dir_name"
            fi
            
            if [[ "$remote_name" != "origin" ]]; then
                cd "$dir_name"
                git remote rename origin "$remote_name"
                cd ..
            fi
        else
            print_warning "Skipping $dir_name - some functionality may not work"
        fi
    else
        print_info "Repository $dir_name already exists"
        cd "$dir_name"
        
        # Check for uncommitted changes
        if ! git diff --quiet || ! git diff --cached --quiet; then
            print_warning "Repository $dir_name has uncommitted changes"
            if ask_user "Stash changes and update?"; then
                git stash push -m "Auto-stash before update"
            else
                print_info "  Skipping update to preserve local changes"
                cd ..
                return 0
            fi
        fi
        
        # Safe remote handling
        if ! git remote | grep -q "$remote_name"; then
            if ask_user "Add remote '$remote_name' to $dir_name?"; then
                git remote add "$remote_name" "$repo_url"
            fi
        else
            # Check if remote URL matches
            local current_url=$(git remote get-url "$remote_name" 2>/dev/null || echo "")
            if [[ "$current_url" != "$repo_url" ]]; then
                print_warning "Remote '$remote_name' URL mismatch:"
                print_warning "  Current: $current_url"
                print_warning "  Expected: $repo_url"
                if ask_user "Update remote URL?"; then
                    git remote set-url "$remote_name" "$repo_url"
                fi
            fi
        fi
        
        # Safe fetch and update
        if git remote | grep -q "$remote_name"; then
            git fetch "$remote_name"
            if [[ ! "$branch" =~ ^v[0-9] ]]; then
                local current_branch=$(git branch --show-current 2>/dev/null || echo "")
                if [[ "$current_branch" == "$branch" ]]; then
                    if ask_user "Pull latest changes for $branch branch?"; then
                        git pull "$remote_name" "$branch"
                    fi
                else
                    print_info "  Currently on different branch: $current_branch"
                    if ask_user "Switch to $branch branch?"; then
                        git checkout "$branch"
                        git pull "$remote_name" "$branch"
                    fi
                fi
            fi
        fi
        cd ..
    fi
}

# Safe repository setup
safe_clone_repositories() {
    if [[ "$BUILD_REMOTE_ONLY" == "true" ]]; then
        print_info "Build-remote-only mode: Skipping local repository setup"
        print_info "This setup is optimized for building with official remote sources"
        return 0
    fi
    
    print_info "Setting up repositories for local development..."
    
    mkdir -p repos
    cd repos
    
    local repos=(lime-app lime-packages librerouteros kconfig-utils openwrt)
    
    for repo in "${repos[@]}"; do
        safe_clone_repository "$repo"
    done
    
    cd "$LIME_BUILD_DIR"
}

# Safe system setup
safe_setup_system() {
    print_info "Checking system configuration..."
    
    # Check KVM support
    if grep -q "vmx\|svm" /proc/cpuinfo; then
        print_info "Hardware virtualization supported"
        
        # Check if user is in kvm group
        if ! groups | grep -q kvm; then
            print_warning "User not in 'kvm' group"
            if ask_user "Add user to kvm group? (requires logout to take effect)"; then
                sudo usermod -a -G kvm "$USER"
                print_warning "Please log out and back in for group changes to take effect"
            fi
        else
            print_success "User already in kvm group"
        fi
        
        # Check kernel modules
        if ! lsmod | grep -q "^kvm"; then
            print_warning "KVM modules not loaded"
            if ask_user "Load KVM kernel modules?"; then
                sudo modprobe kvm-intel 2>/dev/null || sudo modprobe kvm-amd 2>/dev/null || print_warning "Could not load KVM modules"
            fi
        fi
    else
        print_warning "Hardware virtualization not supported - QEMU will be slower"
    fi
    
    # Check bridge and tun modules
    for module in bridge tun; do
        if ! lsmod | grep -q "^$module"; then
            if ask_user "Load $module kernel module?"; then
                sudo modprobe "$module" 2>/dev/null || print_warning "Could not load $module module"
            fi
        fi
    done
}

# Safe system-wide installation
safe_install_system_wide() {
    print_info "Checking system-wide installation..."
    
    local lime_script="$LIME_BUILD_DIR/scripts/lime"
    local system_lime="/usr/local/bin/lime"
    
    if [[ ! -f "$lime_script" ]]; then
        print_warning "Local lime script not found: $lime_script"
        return 0
    fi
    
    # Check if system lime exists and what it points to
    if [[ -L "$system_lime" ]]; then
        local current_target=$(readlink -f "$system_lime")
        local expected_target=$(readlink -f "$lime_script")
        
        if [[ "$current_target" == "$expected_target" ]]; then
            print_success "System-wide lime already correctly linked"
            return 0
        else
            print_warning "System lime points to different location:"
            print_warning "  Current: $current_target"
            print_warning "  Expected: $expected_target"
            
            if ask_user "Update system-wide lime symlink?"; then
                sudo rm "$system_lime"
                sudo ln -s "$lime_script" "$system_lime"
                print_success "Updated system-wide lime symlink"
            fi
        fi
    elif [[ -f "$system_lime" ]]; then
        print_warning "System lime exists as regular file (not symlink)"
        if ask_user "Replace with symlink to local development version?"; then
            sudo rm "$system_lime"
            sudo ln -s "$lime_script" "$system_lime"
            print_success "Replaced system lime with symlink"
        fi
    else
        print_info "No system-wide lime installation found"
        if ask_user "Install lime system-wide via symlink?"; then
            sudo ln -s "$lime_script" "$system_lime"
            print_success "Installed lime system-wide via symlink"
            print_info "You can now run 'lime' from anywhere"
        fi
    fi
}

# Show environment information
show_environment_info() {
    print_info "Environment Information:"
    echo "  Release mode: $RELEASE_MODE"
    echo "  Build remote only: $BUILD_REMOTE_ONLY"
    echo "  Configuration: $CONFIG_FILE"
    echo "  Working directory: $LIME_BUILD_DIR"
    
    if [[ "$RELEASE_MODE" == "true" ]]; then
        print_warning "Running in RELEASE MODE - using release repository overrides"
    fi
    
    if [[ "$BUILD_REMOTE_ONLY" == "true" ]]; then
        print_warning "Running in BUILD-REMOTE-ONLY MODE - optimized for official builds"
    fi
    
    print_info ""
    print_info "This script will:"
    echo "  - Check system dependencies (install with permission)"
    
    if [[ "$BUILD_REMOTE_ONLY" == "true" ]]; then
        echo "  - Skip local repository cloning (build-remote-only mode)"
        echo "  - Configure system for official remote builds"
    else
        echo "  - Clone/update repositories for local development (with confirmation)"
        echo "  - Set up local development environment"
    fi
    
    echo "  - Set up system configuration (with permission)"
    echo "  - Install lime command system-wide via symlink (with permission)"
    echo "  - Preserve existing work and local changes"
    print_info ""
    
    if ! ask_user "Continue with safe setup?"; then
        print_info "Setup cancelled by user"
        exit 0
    fi
}

# Main execution
main() {
    print_info "LibreMesh Development Environment Setup - Safe Version"
    
    check_directory
    parse_config
    show_environment_info
    check_dependencies
    safe_clone_repositories
    safe_setup_system
    safe_install_system_wide
    
    # Apply lime-dev patches to librerouteros build script if repos were cloned
    if [[ "$BUILD_REMOTE_ONLY" != "true" && -f "$LIME_BUILD_DIR/repos/librerouteros/librerouteros_build.sh" ]]; then
        print_info "Applying lime-dev integration patches..."
        if [[ -f "$LIME_BUILD_DIR/scripts/utils/patch-librerouteros-build.sh" ]]; then
            "$LIME_BUILD_DIR/scripts/utils/patch-librerouteros-build.sh" apply
        fi
    fi
    
    print_success "Safe setup completed!"
    echo ""
    print_info "Repository Dependency Status After Setup:"
    "$LIME_BUILD_DIR/scripts/utils/dependency-graph.sh" ascii
    echo ""
    echo "Next steps:"
    echo "  lime setup check                                     # Verify complete setup"
    echo "  lime setup graph                                     # Detailed dependency analysis"
    echo "  ./scripts/librerouteros-wrapper.sh librerouter-v1    # Build firmware"
    echo "  ./scripts/docker-build.sh librerouter-v1            # Build with Docker"
    echo ""
    if [[ "$RELEASE_MODE" == "true" ]]; then
        print_info "Release repositories configured for pre-release testing"
    fi
}

main "$@"