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
    --clean            Clean build environment
    -h, --help         Show this help

Examples:
    $0                              # Native build for librerouter-v1
    $0 native librerouter-v1        # Explicit native build
    $0 docker librerouter-v1        # Docker build
    $0 native --download-only       # Download dependencies only
    $0 docker --shell               # Open Docker shell
    $0 --clean                      # Clean all build artifacts

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
    
    print_info "Native LibreRouterOS build for $target"
    
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
    
    print_info "Docker LibreRouterOS build for $target"
    
    if [[ "$shell_mode" == "true" ]]; then
        exec "$SCRIPT_DIR/core/docker-build.sh" --shell
    elif [[ "$download_only" == "true" ]]; then
        exec "$SCRIPT_DIR/core/docker-build.sh" --download-only "$target"
    else
        exec "$SCRIPT_DIR/core/docker-build.sh" "$target"
    fi
}

clean_build() {
    print_info "Cleaning build environment..."
    
    # Clean librerouteros build artifacts
    if [[ -d "$LIME_BUILD_DIR/repos/librerouteros" ]]; then
        cd "$LIME_BUILD_DIR/repos/librerouteros"
        rm -rf build/ dl/ bin/ .config .config.old build.log 2>/dev/null || true
        print_info "LibreRouterOS build artifacts cleaned"
    fi
    
    # Clean Docker if available
    if command -v docker >/dev/null 2>&1; then
        "$SCRIPT_DIR/core/docker-build.sh" --clean 2>/dev/null || true
        print_info "Docker build cache cleaned"
    fi
    
    print_info "Build environment cleaned"
}

main() {
    local method="native"
    local target="librerouter-v1"
    local download_only="false"
    local shell_mode="false"
    local clean_mode="false"
    
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
    print_info ""
    
    if [[ "$clean_mode" == "true" ]]; then
        clean_build
        exit 0
    fi
    
    check_setup
    
    case "$method" in
        native)
            native_build "$target" "$download_only"
            ;;
        docker)
            docker_build "$target" "$download_only" "$shell_mode"
            ;;
        *)
            print_error "Unknown build method: $method"
            usage
            exit 1
            ;;
    esac
}

main "$@"