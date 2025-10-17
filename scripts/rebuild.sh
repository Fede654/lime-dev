#!/usr/bin/env bash
#
# LibreMesh Incremental Rebuild - Development Optimization
# ========================================================
# Fast rebuilds for development when you're primarily changing lime-packages
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$LIME_BUILD_DIR/build"

# Architecture detection (dynamically determined from build configuration)
# Supports ATH79 (mips_24kc), RAMIPS (mipsel_24kc), x86_64, and other targets
detect_architecture() {
    if [[ ! -f "$BUILD_DIR/.config" ]]; then
        return 1
    fi

    # Detect package architecture from .config
    local arch=$(grep "CONFIG_TARGET_ARCH_PACKAGES=" "$BUILD_DIR/.config" 2>/dev/null | cut -d'"' -f2)
    if [[ -z "$arch" ]]; then
        return 1
    fi
    echo "$arch"
}

detect_target_dir() {
    local target_dir=$(find "$BUILD_DIR/build_dir" -maxdepth 1 -name "target-*" -type d 2>/dev/null | head -1)
    if [[ -z "$target_dir" ]]; then
        return 1
    fi
    echo "$target_dir"
}

detect_subtarget() {
    # Find the subtarget from bin/targets directory structure
    local subtarget_path=$(find "$BUILD_DIR/bin/targets" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | head -1)
    if [[ -z "$subtarget_path" ]]; then
        return 1
    fi
    # Extract subtarget name from path (e.g., bin/targets/ramips/mt7621 -> mt7621)
    basename "$subtarget_path"
}

detect_target_name() {
    # Find the target name from bin/targets directory structure
    local target_path=$(find "$BUILD_DIR/bin/targets" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
    if [[ -z "$target_path" ]]; then
        return 1
    fi
    # Extract target name from path (e.g., bin/targets/ramips -> ramips)
    basename "$target_path"
}

print_info() {
    echo "[REBUILD] $1"
}

print_error() {
    echo "[REBUILD] ERROR: $1" >&2
}

print_success() {
    echo "[REBUILD] ✅ $1"
}

usage() {
    cat << EOF
LibreMesh Incremental Rebuild - Development Speed Optimization

Usage: $0 <rebuild_type> [options]

Rebuild Types (3-Stage Development):
    lime-app       Stage 2: lime-app development (3-8 minutes) 
    incremental    Stage 3: all lime-packages (5-10 minutes)
    selective      Custom: Rebuild specific packages
    
Options:
    --local        Force local sources (automatically applied)
    --multi        Use multi-threaded firmware generation (faster but risky)
    --package PKG  Specific package to rebuild (use with selective)
    --help         Show this help

Examples (3-Stage Development):
    $0 lime-app                    # Stage 2: lime-app development (default)
    $0 lime-app --multi           # Stage 2: + multi-threaded (2-5 min, risky)
    $0 incremental                 # Stage 3: all lime-packages
    $0 incremental --multi        # Stage 3: + multi-threaded (best performance)
    $0 selective --package shared-state  # Custom: specific package only

Development Workflow:
    Stage 1: lime build --local   # Initial full build (15-45 minutes)
    Stage 2: lime rebuild         # lime-app development (3-8 minutes)
    Stage 3: lime rebuild incremental --multi # All packages (3-8 minutes)

EOF
}

# Apply package source injection for local development
apply_local_sources() {
    print_info "Applying local source injection for development..."

    if [[ -x "$SCRIPT_DIR/utils/package-source-injector.sh" ]]; then
        "$SCRIPT_DIR/utils/package-source-injector.sh" apply local "$BUILD_DIR"
    else
        print_error "Package source injector not found"
        return 1
    fi
}

# Clean package files from staging rootfs before reinstall
# This ensures old files don't persist after rebuild
cleanup_package_staging() {
    local pkg_name="$1"
    local target_dir="$2"
    local target_name="$3"

    # Validar parámetros
    if [[ -z "$pkg_name" || -z "$target_dir" || -z "$target_name" ]]; then
        print_error "cleanup_package_staging: Missing required parameters"
        return 1
    fi

    local staging_root="$target_dir/root-${target_name}"

    # Para lime-app: cleanup específico de directorios conocidos
    if [[ "$pkg_name" == "lime-app" ]]; then
        print_info "Cleaning lime-app from staging rootfs..."
        rm -rf "$staging_root/www/app" \
               "$staging_root/www/lime_app_index.html" \
               "$staging_root/www/cgi-bin/lime-app-spa" \
               "$staging_root/etc/uci-defaults/"*lime-app* \
               "$staging_root/usr/share/rpcd/acl.d/iwinfo.json"
    fi

    # Cleanup genérico: borrar markers de instalación
    rm -f "$target_dir/.pkgdir/${pkg_name}.installed"
    rm -f "$staging_root/stamp/.${pkg_name}_installed"
}

# Check if initial build is required
check_initial_build_required() {
    local missing_requirements=()
    
    # Check if build directory exists
    if [[ ! -d "$BUILD_DIR" ]]; then
        missing_requirements+=("Build directory missing")
    fi
    
    # Check if .config exists (indicates build was initialized)
    if [[ ! -f "$BUILD_DIR/.config" ]]; then
        missing_requirements+=("Build configuration missing")
    fi
    
    # Check if feeds are installed
    if [[ ! -d "$BUILD_DIR/feeds" ]]; then
        missing_requirements+=("Feeds not installed")
    fi
    
    # Check if any packages were built
    if [[ ! -d "$BUILD_DIR/build_dir" ]]; then
        missing_requirements+=("Build artifacts missing")
    fi
    
    if [[ ${#missing_requirements[@]} -gt 0 ]]; then
        print_error "Cannot perform incremental rebuild. Initial build required:"
        for req in "${missing_requirements[@]}"; do
            print_error "  ❌ $req"
        done
        echo ""
        print_info "💡 Please run a full build first:"
        print_info "   ./lime build --local librerouter-v1"
        print_info "   ./lime build --local x86_64"
        echo ""
        print_info "After the initial build, you can use the 3-stage development workflow:"
        print_info "   ./lime rebuild         (3-8 minutes, lime-app development)"
        print_info "   ./lime rebuild incremental --multi (3-8 minutes, all packages)"
        exit 1
    fi
}

# Rebuild lime-app only (ultra-fast)
rebuild_lime_app_only() {
    local multi_threaded="${1:-false}"
    print_info "🚀 Ultra-fast lime-app rebuild"

    check_initial_build_required

    # Detect architecture dynamically
    local ARCH=$(detect_architecture)
    local TARGET_DIR=$(detect_target_dir)
    local SUBTARGET=$(detect_subtarget)
    local TARGET_NAME=$(detect_target_name)

    # Validación exhaustiva de variables críticas
    if [[ -z "$ARCH" ]]; then
        print_error "Failed to detect architecture from .config"
        print_error "Check: grep CONFIG_TARGET_ARCH_PACKAGES build/.config"
        return 1
    fi

    if [[ -z "$TARGET_DIR" ]]; then
        print_error "Failed to detect target directory"
        print_error "Check: ls build/build_dir/target-*"
        return 1
    fi

    if [[ -z "$TARGET_NAME" ]]; then
        print_error "Failed to detect target name"
        print_error "Check: ls build/bin/targets/*"
        return 1
    fi

    # Validar consistencia entre ARCH y TARGET_DIR
    if [[ "$(basename "$TARGET_DIR")" != *"$ARCH"* ]]; then
        print_error "Architecture mismatch detected!"
        print_error "  .config says: $ARCH"
        print_error "  target_dir is: $(basename "$TARGET_DIR")"
        return 1
    fi

    print_info "Detected architecture: $ARCH"
    print_info "Target directory: $(basename "$TARGET_DIR")"
    if [[ -n "$SUBTARGET" ]]; then
        print_info "Target: ${TARGET_NAME}/${SUBTARGET}"
    fi

    cd "$BUILD_DIR"

    print_info "Cleaning lime-app..."
    make package/feeds/libremesh/lime-app/clean

    # Apply local sources after clean (clean removes Makefile patches)
    apply_local_sources

    # Regenerar package dependencies (evita errores de .packagedeps corrupto)
    print_info "Regenerating package dependencies..."
    rm -f tmp/.packagedeps
    make package/symlinks 2>&1 | grep -E "(ERROR|error)" || true

    print_info "Rebuilding lime-app..."
    make package/feeds/libremesh/lime-app/compile

    print_info "Verifying lime-app package was created..."
    local package_pattern="$BUILD_DIR/bin/packages/$ARCH/libremesh/lime-app_*.ipk"
    if ls $package_pattern 1> /dev/null 2>&1; then
        print_info "✅ lime-app package created successfully"
        local package_file=$(ls -t $package_pattern | head -1)
        print_info "📦 Package: $(basename "$package_file")"
    else
        print_error "❌ lime-app package was not created"
        return 1
    fi
    
    # Generate firmware image
    print_info "🔧 Generating firmware image with updated lime-app..."

    # CRITICAL: Force reinstall of package to staging rootfs
    # Without this, target/linux/install uses old rootfs files
    print_info "🔄 Forcing lime-app reinstall to staging rootfs..."
    cleanup_package_staging "lime-app" "$TARGET_DIR" "$TARGET_NAME"
    make package/feeds/libremesh/lime-app/install

    if [[ "$multi_threaded" == "true" ]]; then
        print_info "⚡ Using multi-threaded build (fastest, may have race conditions)"
        local make_command="make -j$(nproc)"
        local time_estimate="2-5 minutes"
    else
        print_info "🚀 Using single-threaded target build (reliable)"
        local make_command="make target/linux/install"
        local time_estimate="3-8 minutes"
    fi

    print_info "⏱️  Estimated time: $time_estimate"

    if $make_command; then
        print_success "✅ Firmware image generation complete!"
    else
        # Fallback solo si era multi-threaded
        if [[ "$multi_threaded" == "true" ]]; then
            print_error "⚠️  Multi-threaded build failed, retrying single-threaded..."
            if make target/linux/install; then
                print_success "✅ Firmware complete (single-threaded fallback)"
            else
                print_error "❌ Build failed"
                print_info "📦 Package available: $(basename "$package_file")"
                return 1
            fi
        else
            print_error "❌ Build failed"
            print_info "📦 Package available: $(basename "$package_file")"
            return 1
        fi
    fi

    print_info "🎯 Updated firmware available in: $BUILD_DIR/bin/targets/"
    local latest_firmware=$(find "$BUILD_DIR/bin/targets" -name "*.bin" -newer "$package_file" | head -1)
    if [[ -n "$latest_firmware" ]]; then
        print_info "📁 Latest image: $(basename "$latest_firmware")"
    else
        # Find any firmware image
        local any_firmware=$(find "$BUILD_DIR/bin/targets" -name "*.bin" | head -1)
        if [[ -n "$any_firmware" ]]; then
            print_info "📁 Firmware image: $(basename "$any_firmware")"
        fi
    fi

    print_info ""
    print_info "⚡ Alternative: Install package directly on device for faster iteration:"
    print_info "   scp $package_file root@ROUTER_IP:/tmp/"
    print_info "   ssh root@ROUTER_IP 'opkg install /tmp/$(basename "$package_file")'"
}

# Rebuild all lime-packages (incremental)
rebuild_lime_packages() {
    local multi_threaded="${1:-false}"
    print_info "📦 Stage 3: All lime-packages rebuild"

    check_initial_build_required

    # Detect architecture dynamically
    local ARCH=$(detect_architecture)
    local TARGET_DIR=$(detect_target_dir)
    local SUBTARGET=$(detect_subtarget)
    local TARGET_NAME=$(detect_target_name)

    # Validación exhaustiva de variables críticas
    if [[ -z "$ARCH" ]]; then
        print_error "Failed to detect architecture from .config"
        print_error "Check: grep CONFIG_TARGET_ARCH_PACKAGES build/.config"
        return 1
    fi

    if [[ -z "$TARGET_DIR" ]]; then
        print_error "Failed to detect target directory"
        print_error "Check: ls build/build_dir/target-*"
        return 1
    fi

    if [[ -z "$TARGET_NAME" ]]; then
        print_error "Failed to detect target name"
        print_error "Check: ls build/bin/targets/*"
        return 1
    fi

    # Validar consistencia entre ARCH y TARGET_DIR
    if [[ "$(basename "$TARGET_DIR")" != *"$ARCH"* ]]; then
        print_error "Architecture mismatch detected!"
        print_error "  .config says: $ARCH"
        print_error "  target_dir is: $(basename "$TARGET_DIR")"
        return 1
    fi

    print_info "Detected architecture: $ARCH"
    print_info "Target directory: $(basename "$TARGET_DIR")"
    if [[ -n "$SUBTARGET" ]]; then
        print_info "Target: ${TARGET_NAME}/${SUBTARGET}"
    fi

    cd "$BUILD_DIR"

    # List of common lime packages that often change
    local lime_packages=(
        "lime-app"
        "lime-system"
        "shared-state"
        "lime-proto-babeld"
        "lime-proto-batadv"
        "lime-hwd-openwrt-wan"
        "ubus-lime-utils"
        "ubus-lime-metrics"
        "lime-debug"
    )

    print_info "Cleaning lime packages..."
    for pkg in "${lime_packages[@]}"; do
        if [[ -d "package/feeds/libremesh/$pkg" ]]; then
            print_info "  Cleaning $pkg..."
            make "package/feeds/libremesh/$pkg/clean" || true
            cleanup_package_staging "$pkg" "$TARGET_DIR" "$TARGET_NAME"
        fi
    done

    # Apply local sources after clean (clean removes Makefile patches)
    apply_local_sources

    # Regenerar package dependencies (evita errores de .packagedeps corrupto)
    print_info "Regenerating package dependencies..."
    rm -f tmp/.packagedeps
    make package/symlinks 2>&1 | grep -E "(ERROR|error)" || true

    print_info "Rebuilding lime packages..."
    for pkg in "${lime_packages[@]}"; do
        if [[ -d "package/feeds/libremesh/$pkg" ]]; then
            print_info "  Building $pkg..."
            make "package/feeds/libremesh/$pkg/compile"
            # Skip install step - packages are created during compile
            if ls "$BUILD_DIR/bin/packages/$ARCH/libremesh/$pkg"*.ipk 1> /dev/null 2>&1; then
                print_info "  ✅ $pkg package created"
            else
                print_info "  ⚠️  $pkg package not found (may be expected)"
            fi
        fi
    done

    print_info "✅ Package rebuild complete!"
    print_info "📁 Packages available in: $BUILD_DIR/bin/packages/$ARCH/libremesh/"
    
    # Generate firmware image  
    print_info "🔧 Generating firmware image with updated packages..."
    
    if [[ "$multi_threaded" == "true" ]]; then
        print_info "⚡ Using multi-threaded build (fastest, may have race conditions)"
        local make_command="make -j$(nproc)"
        local time_estimate="3-8 minutes"
    else
        print_info "🚀 Using single-threaded target build (reliable)"
        local make_command="make target/linux/install"
        local time_estimate="5-10 minutes"
    fi

    print_info "⏱️  Estimated time: $time_estimate"

    if $make_command; then
        print_success "✅ Incremental rebuild complete!"
    else
        # Fallback solo si era multi-threaded
        if [[ "$multi_threaded" == "true" ]]; then
            print_error "⚠️  Multi-threaded build failed, retrying single-threaded..."
            if make target/linux/install; then
                print_success "✅ Rebuild complete (single-threaded fallback)"
            else
                print_error "❌ Build failed"
                print_info "📦 Packages available but image not updated"
                return 1
            fi
        else
            print_error "❌ Build failed"
            print_info "📦 Packages available but image not updated"
            return 1
        fi
    fi

    print_info "🎯 Updated firmware available in: $BUILD_DIR/bin/targets/"
    local latest_firmware=$(find "$BUILD_DIR/bin/targets" -name "*.bin" | head -1)
    if [[ -n "$latest_firmware" ]]; then
        print_info "📁 Firmware image: $(basename "$latest_firmware")"
    fi
}

# Rebuild specific package
rebuild_specific_package() {
    local package="$1"
    local multi_threaded="${2:-false}"

    print_info "🎯 Rebuilding specific package: $package"

    check_initial_build_required

    # Detect architecture dynamically
    local ARCH=$(detect_architecture)
    local TARGET_DIR=$(detect_target_dir)
    local SUBTARGET=$(detect_subtarget)
    local TARGET_NAME=$(detect_target_name)

    # Validación exhaustiva de variables críticas
    if [[ -z "$ARCH" ]]; then
        print_error "Failed to detect architecture from .config"
        print_error "Check: grep CONFIG_TARGET_ARCH_PACKAGES build/.config"
        return 1
    fi

    if [[ -z "$TARGET_DIR" ]]; then
        print_error "Failed to detect target directory"
        print_error "Check: ls build/build_dir/target-*"
        return 1
    fi

    if [[ -z "$TARGET_NAME" ]]; then
        print_error "Failed to detect target name"
        print_error "Check: ls build/bin/targets/*"
        return 1
    fi

    # Validar consistencia entre ARCH y TARGET_DIR
    if [[ "$(basename "$TARGET_DIR")" != *"$ARCH"* ]]; then
        print_error "Architecture mismatch detected!"
        print_error "  .config says: $ARCH"
        print_error "  target_dir is: $(basename "$TARGET_DIR")"
        return 1
    fi

    print_info "Detected architecture: $ARCH"
    print_info "Target directory: $(basename "$TARGET_DIR")"
    if [[ -n "$SUBTARGET" ]]; then
        print_info "Target: ${TARGET_NAME}/${SUBTARGET}"
    fi

    cd "$BUILD_DIR"

    # Try to find the package in different feeds
    local package_path=""
    if [[ -d "package/feeds/libremesh/$package" ]]; then
        package_path="package/feeds/libremesh/$package"
    elif [[ -d "package/feeds/packages/$package" ]]; then
        package_path="package/feeds/packages/$package"
    elif [[ -d "package/$package" ]]; then
        package_path="package/$package"
    else
        print_error "Package not found: $package"
        return 1
    fi

    print_info "Found package at: $package_path"

    print_info "Cleaning $package..."
    make "$package_path/clean"
    cleanup_package_staging "$package" "$TARGET_DIR" "$TARGET_NAME"

    # Apply local sources after clean (clean removes Makefile patches)
    apply_local_sources

    # Regenerar package dependencies (evita errores de .packagedeps corrupto)
    print_info "Regenerating package dependencies..."
    rm -f tmp/.packagedeps
    make package/symlinks 2>&1 | grep -E "(ERROR|error)" || true

    print_info "Rebuilding $package..."
    make "$package_path/compile"

    # Verify package was created
    if ls "$BUILD_DIR/bin/packages/$ARCH"/*/"$package"*.ipk 1> /dev/null 2>&1; then
        print_info "✅ $package package created successfully"
        local package_file=$(ls -t "$BUILD_DIR/bin/packages/$ARCH"/*/"$package"*.ipk | head -1)

        # Generate firmware image
        print_info "🔧 Generating firmware image with updated $package..."

        if [[ "$multi_threaded" == "true" ]]; then
            print_info "⚡ Using multi-threaded build (fastest, may have race conditions)"
            local make_command="make -j$(nproc)"
        else
            print_info "🚀 Using single-threaded target build (reliable)"
            local make_command="make target/linux/install"
        fi

        if $make_command; then
            print_success "✅ Package $package rebuild complete!"
        else
            # Fallback solo si era multi-threaded
            if [[ "$multi_threaded" == "true" ]]; then
                print_error "⚠️  Multi-threaded build failed, retrying single-threaded..."
                if make target/linux/install; then
                    print_success "✅ Package $package rebuild complete (single-threaded fallback)"
                else
                    print_error "❌ Build failed"
                    print_info "📦 Package available: $(basename "$package_file")"
                    return 1
                fi
            else
                print_error "❌ Build failed"
                print_info "📦 Package available: $(basename "$package_file")"
                return 1
            fi
        fi

        print_info "🎯 Updated firmware available in: $BUILD_DIR/bin/targets/"
    else
        print_error "❌ $package package was not created"
        return 1
    fi
}

# Show build time estimates
show_time_estimates() {
    cat << EOF

⏱️  3-Stage Development Workflow:
   Stage 1: lime build --local      15-45 minutes (initial full build)
   Stage 2: lime rebuild            3-8 minutes   (lime-app development)  
   Stage 3: lime rebuild incremental --multi  3-8 minutes (all packages, best performance)

💡 Development Tips:
   - Stage 2 for lime-app UI/frontend changes (most common)
   - Stage 3 for lime-packages backend changes
   - Add '--multi' for best performance (incremental builds)
   - Keep downloads cache with: 'lime clean build' (not 'lime clean all')
   - Use QEMU for testing: 'lime qemu start'

EOF
}

# Main execution
main() {
    local rebuild_type="${1:-help}"
    local package=""
    local multi_threaded="false"
    
    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case $1 in
            --package)
                package="$2"
                shift 2
                ;;
            --local)
                # Local mode is automatically applied
                shift
                ;;
            --multi)
                multi_threaded="true"
                shift
                ;;
            --help|-h|help)
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
    
    case "$rebuild_type" in
        "lime-app")
            rebuild_lime_app_only "$multi_threaded"
            ;;
        "incremental") 
            rebuild_lime_packages "$multi_threaded"
            ;;
        "selective")
            if [[ -z "$package" ]]; then
                print_error "Selective rebuild requires --package option"
                usage
                exit 1
            fi
            rebuild_specific_package "$package" "$multi_threaded"
            ;;
        "help"|"--help"|"-h")
            usage
            show_time_estimates
            ;;
        *)
            print_error "Unknown rebuild type: $rebuild_type"
            usage
            exit 1
            ;;
    esac
}

main "$@"