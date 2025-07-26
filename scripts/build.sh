#!/usr/bin/env bash
#
# LibreMesh Build Management - Unified Script
# Single entry point for all build operations
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(dirname "$SCRIPT_DIR")"

print_info() {
    echo "[INFO] $1"
}

print_error() {
    echo "[ERROR] $1" >&2
}

print_warning() {
    echo "[WARNING] $1" >&2
}

print_critical() {
    echo -e "\033[1;31m[CRITICAL]\033[0m $1" >&2
}

print_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

# Check for existing build and confirm destructive operations
confirm_build_override() {
    local target="$1"
    local source_mode="$2"
    
    # Check for existing firmware files
    local firmware_dir="$LIME_BUILD_DIR/build/bin/targets"
    local existing_files=()
    
    if [[ -d "$firmware_dir" ]]; then
        while IFS= read -r -d '' file; do
            existing_files+=("$file")
        done < <(find "$firmware_dir" -name "*.bin" -type f -print0 2>/dev/null)
    fi
    
    # Check for significant build directory
    local build_size=0
    if [[ -d "$LIME_BUILD_DIR/build" ]]; then
        build_size=$(du -sm "$LIME_BUILD_DIR/build" 2>/dev/null | cut -f1 || echo 0)
    fi
    
    # Only show confirmation if there's significant existing data
    if [[ ${#existing_files[@]} -gt 0 || $build_size -gt 100 ]]; then
        print_critical "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
        echo
        print_warning "This build will OVERWRITE existing build data:"
        
        if [[ $build_size -gt 0 ]]; then
            print_warning "• Build directory: ${build_size}MB of data will be replaced"
        fi
        
        if [[ ${#existing_files[@]} -gt 0 ]]; then
            print_warning "• Existing firmware files (${#existing_files[@]} files):"
            for file in "${existing_files[@]:0:5}"; do  # Show max 5 files
                local size_mb=$(( $(stat -c%s "$file" 2>/dev/null || echo 0) / 1024 / 1024 ))
                local age=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
                print_warning "  $(basename "$file") (${size_mb}MB, ${age})"
            done
            if [[ ${#existing_files[@]} -gt 5 ]]; then
                print_warning "  ... and $((${#existing_files[@]} - 5)) more files"
            fi
        fi
        
        echo
        print_info "Build details:"
        print_info "• Target: $target"
        print_info "• Source mode: $source_mode"
        print_info "• Build time: ~15-45 minutes"
        print_info "• Result: New firmware files in build/bin/targets/"
        echo
        
        print_critical "🚨 ALL EXISTING BUILD DATA WILL BE LOST 🚨"
        echo
        
        # Force explicit confirmation
        local confirmation=""
        while [[ "$confirmation" != "yes" && "$confirmation" != "no" ]]; do
            echo -n "Type 'yes' to continue with build or 'no' to cancel: "
            read -r confirmation
            confirmation=$(echo "$confirmation" | tr '[:upper:]' '[:lower:]')
        done
        
        if [[ "$confirmation" == "no" ]]; then
            print_info "Build cancelled by user"
            print_info ""
            print_info "Alternative options:"
            print_info "• Use 'lime clean' to selectively clean build artifacts"
            print_info "• Backup existing firmware: cp build/bin/targets/*/*.bin ~/firmware-backup/"
            print_info "• Use 3-stage development: 'lime rebuild' (Stage 2) or 'lime rebuild incremental --multi' (Stage 3)"
            exit 0
        fi
        
        print_success "✅ Build confirmed - proceeding with $target build"
        echo
    fi
}

usage() {
    cat << EOF
LibreMesh Build Management

Usage: $0 [METHOD] [TARGET] [OPTIONS]

Build Methods:
    native          Native build with environment setup (default, fastest)
    docker          Docker containerized build (requires network)
    
Targets:
    librerouter-v1           LibreRouter v1 hardware (default)
    hilink_hlk-7621a-evb     HiLink HLK-7621A evaluation board
    ath79_generic_multiradio Multiple ath79 devices
    youhua_wr1200js          Youhua WR1200JS router
    librerouter-r2           LibreRouter R2 (experimental)
    x86_64                   x86_64 virtual machine/QEMU target
    
Options:
    --download-only     Download dependencies only (no build)
    --shell            Open interactive shell (docker method only)
    --clean [TYPE]     Clean build environment
                       Types: all (default), build, downloads, outputs
    --local            Use local repository sources for development
    --skip-validation  Skip mandatory build mode validation (not recommended)
    -h, --help         Show this help

Examples:
    $0                              # Native build using configured sources
    $0 native librerouter-v1        # Explicit native build with configured sources
    $0 --local librerouter-v1       # Native build with local development sources
    $0 docker librerouter-v1        # Docker build with configured sources
    $0 docker --local x86_64        # Docker build with local sources
    $0 --skip-validation x86_64     # Build without validation (not recommended)
    $0 native --download-only       # Download dependencies only
    $0 docker --shell               # Open Docker shell
    $0 --clean                      # Clean all build artifacts
    $0 --clean build                # Clean only build directory (2.3GB)
    $0 --clean downloads            # Clean only downloads cache (854MB)
    $0 --clean outputs              # Clean only binary outputs (4MB)
    $0 --mode release x86_64        # Release build for x86_64 target

Direct Scripts:
    ./librerouteros-wrapper.sh      # Direct native build
    ./docker-build.sh               # Direct Docker build

EOF
}

check_setup() {
    if [[ ! -d "$LIME_BUILD_DIR/repos/librerouteros" ]]; then
        print_error "LibreRouterOS repository not found"
        print_error "Run setup first: ./scripts/setup.sh install"
        exit 1
    fi
    
    if [[ ! -f "$LIME_BUILD_DIR/repos/librerouteros/librerouteros_build.sh" ]]; then
        print_error "LibreRouterOS build script not found"
        print_error "Repository may be incomplete. Try: ./scripts/setup.sh update"
        exit 1
    fi
}

native_build() {
    local target="$1"
    local download_only="$2"
    local source_mode="$3"
    
    print_info "Native LibreRouterOS build for $target"
    
    # Skip confirmation for download-only mode
    if [[ "$download_only" != "true" ]]; then
        confirm_build_override "$target" "$source_mode"
    fi
    
    if [[ "$download_only" == "true" ]]; then
        BUILD_DOWNLOAD_ONLY=true exec "$SCRIPT_DIR/core/librerouteros-wrapper.sh" "$target"
    else
        exec "$SCRIPT_DIR/core/librerouteros-wrapper.sh" "$target"
    fi
}

docker_build() {
    local target="$1"
    local download_only="$2"
    local shell_mode="$3"
    local source_mode="$4"
    
    print_info "Docker LibreRouterOS build for $target"
    
    # Skip confirmation for shell or download-only mode
    if [[ "$shell_mode" != "true" && "$download_only" != "true" ]]; then
        confirm_build_override "$target" "$source_mode"
    fi
    
    if [[ "$shell_mode" == "true" ]]; then
        exec "$SCRIPT_DIR/core/docker-build.sh" --shell
    elif [[ "$download_only" == "true" ]]; then
        exec "$SCRIPT_DIR/core/docker-build.sh" --download-only "$target"
    else
        exec "$SCRIPT_DIR/core/docker-build.sh" "$target"
    fi
}

clean_build() {
    local clean_type="${1:-all}"
    
    print_info "Cleaning build environment (${clean_type})..."
    
    case "$clean_type" in
        all)
            print_info "Cleaning all build artifacts..."
            rm -rf "$LIME_BUILD_DIR/build/" 2>/dev/null || true
            rm -rf "$LIME_BUILD_DIR/dl/" 2>/dev/null || true
            rm -rf "$LIME_BUILD_DIR/repos/librerouteros/bin/" 2>/dev/null || true
            rm -rf "$LIME_BUILD_DIR/repos/librerouteros/.config" 2>/dev/null || true
            rm -rf "$LIME_BUILD_DIR/repos/librerouteros/.config.old" 2>/dev/null || true
            rm -rf "$LIME_BUILD_DIR/repos/librerouteros/build.log" 2>/dev/null || true
            print_info "✓ Build directory (2.3GB freed)"
            print_info "✓ Downloads cache (854MB freed)"
            print_info "✓ Binary outputs (4MB freed)"
            print_info "✓ Configuration files"
            ;;
        build)
            print_info "Cleaning build directory only..."
            rm -rf "$LIME_BUILD_DIR/build/" 2>/dev/null || true
            rm -rf "$LIME_BUILD_DIR/repos/librerouteros/.config" 2>/dev/null || true
            rm -rf "$LIME_BUILD_DIR/repos/librerouteros/.config.old" 2>/dev/null || true
            rm -rf "$LIME_BUILD_DIR/repos/librerouteros/build.log" 2>/dev/null || true
            print_info "✓ Build directory (2.3GB freed)"
            print_info "✓ Configuration files"
            ;;
        downloads)
            print_info "Cleaning downloads cache only..."
            rm -rf "$LIME_BUILD_DIR/dl/" 2>/dev/null || true
            print_info "✓ Downloads cache (854MB freed)"
            ;;
        outputs)
            print_info "Cleaning binary outputs only..."
            rm -rf "$LIME_BUILD_DIR/repos/librerouteros/bin/" 2>/dev/null || true
            print_info "✓ Binary outputs (4MB freed)"
            ;;
        *)
            print_error "Unknown clean type: $clean_type"
            print_error "Valid options: all, build, downloads, outputs"
            exit 1
            ;;
    esac
    
    # Clean Docker if available and doing full clean
    if [[ "$clean_type" == "all" ]] && command -v docker >/dev/null 2>&1; then
        "$SCRIPT_DIR/core/docker-build.sh" --clean 2>/dev/null || true
        print_info "✓ Docker build cache cleaned"
    fi
    
    print_info "Build environment cleaned"
}

main() {
    local method="native"
    local target="librerouter-v1"
    local download_only="false"
    local shell_mode="false"
    local clean_mode="false"
    local clean_type="all"
    local skip_validation="false"
    local local_mode="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            native)
                method="native"
                shift
                ;;
            docker)
                method="docker"
                shift
                ;;
            --download-only)
                download_only="true"
                shift
                ;;
            --shell)
                shell_mode="true"
                shift
                ;;
            --clean)
                clean_mode="true"
                # Check if next argument is a clean type
                if [[ $# -gt 1 && "$2" =~ ^(all|build|downloads|outputs)$ ]]; then
                    clean_type="$2"
                    shift 2
                else
                    clean_type="all"
                    shift
                fi
                ;;
            --mode)
                print_info "WARNING: --mode flag is deprecated and ignored"
                print_info "Use --local for local development, or default for configured sources"
                if [[ $# -gt 1 ]]; then
                    shift 2
                else
                    shift 1
                fi
                ;;
            --local)
                local_mode="true"
                export LIME_LOCAL_MODE="true"
                shift
                ;;
            --skip-validation)
                skip_validation="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                # Assume it's a target
                target="$1"
                shift
                ;;
        esac
    done
    
    print_info "LibreMesh Build Management"
    print_info "Method: $method"
    print_info "Target: $target"
    if [[ "$local_mode" == "true" ]]; then
        print_info "Source Mode: LOCAL (forcing local repository sources)"
    else
        print_info "Source Mode: CONFIGURED (using sources from versions.conf [sources] section)"
    fi
    print_info ""
    
    if [[ "$clean_mode" == "true" ]]; then
        clean_build "$clean_type"
        exit 0
    fi
    
    # MANDATORY configuration integrity check before expensive build operations
    if [[ "$skip_validation" == "false" ]]; then
        print_info "Running mandatory configuration integrity check..."
        
        # Check config file integrity first
        if ! "$SCRIPT_DIR/utils/validate-config-integrity.sh" validate; then
            case $? in
                1)
                    print_error "❌ Configuration integrity check failed"
                    print_error "Fix the configuration corruption above before proceeding"
                    exit 1
                    ;;
                2)
                    print_info "Auto-fix requested but not yet implemented"
                    print_error "Please manually fix the configuration and try again"
                    exit 1
                    ;;
            esac
        fi
        
        # Simple validation: local vs configured
        if [[ "$local_mode" == "true" ]]; then
            print_info "Running mandatory source validation (local mode)..."
            print_info "Validating local repository sources are available"
            validation_mode="local"
        else
            print_info "Running mandatory source validation (configured mode)..."
            print_info "Validating configured sources from [sources] section are accessible"
            validation_mode="default"
        fi
        
        print_info "Use --skip-validation to bypass this check (not recommended)"
        
        if ! "$SCRIPT_DIR/utils/validate-build-mode.sh" "$validation_mode" "$LIME_BUILD_DIR/build"; then
            print_error "❌ Source validation failed. This prevents expensive failed builds."
            print_error "Fix the configuration issues above before proceeding."
            print_error "Use --skip-validation to bypass this check (not recommended)."
            exit 1
        fi
        print_info "✅ Configuration integrity and source validation passed"
        print_info ""
    else
        print_info "⚠️  Skipping build mode validation (--skip-validation used)"
        print_info "⚠️  This may result in build failures or unexpected behavior"
        print_info ""
    fi
    
    check_setup
    
    # Determine source mode for confirmation dialog
    local source_mode="CONFIGURED"
    if [[ "$local_mode" == "true" ]]; then
        source_mode="LOCAL"
    fi
    
    case "$method" in
        native)
            native_build "$target" "$download_only" "$source_mode"
            ;;
        docker)
            docker_build "$target" "$download_only" "$shell_mode" "$source_mode"
            ;;
        *)
            print_error "Unknown build method: $method"
            usage
            exit 1
            ;;
    esac
}

main "$@"