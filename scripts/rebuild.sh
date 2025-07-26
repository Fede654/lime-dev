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

Rebuild Types:
    lime-app       Ultra-fast: Only rebuild lime-app (3-8 minutes)
    incremental    Smart: Rebuild lime-packages only (5-10 minutes)
    selective      Custom: Rebuild specific packages
    
Options:
    --local        Force local sources (automatically applied)
    --multi        Use multi-threaded firmware generation (faster but risky)
    --package PKG  Specific package to rebuild (use with selective)
    --help         Show this help

Examples:
    $0 lime-app                    # Fastest: Just lime-app (optimized target build)
    $0 lime-app --multi           # Fastest + multi-threaded firmware generation
    $0 incremental                 # All lime-packages
    $0 selective --package shared-state  # Specific package only

Speed Comparison:
    Full build:        15-45 minutes (complete rebuild)
    lime rebuild:      5-10 minutes  (packages + optimized target build)
    lime rebuild-fast: 3-8 minutes   (lime-app + optimized target build)

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
        print_info "After the initial build, you can use fast rebuilds:"
        print_info "   ./lime rebuild-fast    (10-30 seconds)"
        print_info "   ./lime rebuild         (1-3 minutes)"
        exit 1
    fi
}

# Rebuild lime-app only (ultra-fast)
rebuild_lime_app_only() {
    local multi_threaded="${1:-false}"
    print_info "🚀 Ultra-fast lime-app rebuild"
    
    check_initial_build_required
    
    cd "$BUILD_DIR"
    
    # Apply local sources first
    apply_local_sources
    
    print_info "Cleaning lime-app..."
    make package/feeds/libremesh/lime-app/clean
    
    print_info "Rebuilding lime-app..."
    make package/feeds/libremesh/lime-app/compile
    
    print_info "Verifying lime-app package was created..."
    local package_pattern="$BUILD_DIR/bin/packages/mips_24kc/libremesh/lime-app_*.ipk"
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
    
    if [[ "$multi_threaded" == "true" ]]; then
        print_info "⚡ Using multi-threaded full build (fastest but risky)"
        local make_command="make -j$(nproc)"
        local time_estimate="2-5 minutes"
    else
        print_info "🚀 Using optimized target build (fast and reliable)"
        local make_command="make target/linux/install"
        local time_estimate="3-8 minutes"
    fi
    
    print_info "⏱️  Estimated time: $time_estimate"
    
    if $make_command; then
        print_success "✅ Firmware image generation complete!"
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
        print_info "   scp $package_file root@10.13.0.1:/tmp/"
        print_info "   ssh root@10.13.0.1 'opkg install /tmp/$(basename "$package_file")'"
    else
        print_error "❌ Firmware image generation failed"
        print_info "📦 Package available for manual installation: $(basename "$package_file")"
        print_info "🔧 Try manual firmware generation: cd $BUILD_DIR && make -j1"
        return 1
    fi
}

# Rebuild all lime-packages (incremental)
rebuild_lime_packages() {
    local multi_threaded="${1:-false}"
    print_info "📦 Smart incremental rebuild (lime-packages)"
    
    check_initial_build_required
    
    cd "$BUILD_DIR"
    
    # Apply local sources first
    apply_local_sources
    
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
        fi
    done
    
    print_info "Rebuilding lime packages..."
    for pkg in "${lime_packages[@]}"; do
        if [[ -d "package/feeds/libremesh/$pkg" ]]; then
            print_info "  Building $pkg..."
            make "package/feeds/libremesh/$pkg/compile"
            # Skip install step - packages are created during compile
            if ls "$BUILD_DIR/bin/packages/mips_24kc/libremesh/$pkg"*.ipk 1> /dev/null 2>&1; then
                print_info "  ✅ $pkg package created"
            else
                print_info "  ⚠️  $pkg package not found (may be expected)"
            fi
        fi
    done
    
    print_info "✅ Package rebuild complete!"
    print_info "📁 Packages available in: $BUILD_DIR/bin/packages/mips_24kc/libremesh/"
    
    # Generate firmware image  
    print_info "🔧 Generating firmware image with updated packages..."
    
    if [[ "$multi_threaded" == "true" ]]; then
        print_info "⚡ Using multi-threaded full build (fastest but risky)"
        local make_command="make -j$(nproc)"
        local time_estimate="3-8 minutes"
    else
        print_info "🚀 Using optimized target build (fast and reliable)"
        local make_command="make target/linux/install"
        local time_estimate="5-10 minutes" 
    fi
    
    print_info "⏱️  Estimated time: $time_estimate"
    
    if $make_command; then
        print_success "✅ Incremental rebuild complete!"
        print_info "🎯 Updated firmware available in: $BUILD_DIR/bin/targets/"
        local latest_firmware=$(find "$BUILD_DIR/bin/targets" -name "*.bin" | head -1)
        if [[ -n "$latest_firmware" ]]; then
            print_info "📁 Firmware image: $(basename "$latest_firmware")"
        fi
    else
        print_error "❌ Firmware image generation failed"
        print_info "📦 Packages available but image not updated"
        print_info "🔧 Try manual firmware generation: cd $BUILD_DIR && make -j1"
        return 1
    fi
}

# Rebuild specific package
rebuild_specific_package() {
    local package="$1"
    local multi_threaded="${2:-false}"
    
    print_info "🎯 Rebuilding specific package: $package"
    
    check_initial_build_required
    
    cd "$BUILD_DIR"
    
    # Apply local sources first  
    apply_local_sources
    
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
    
    print_info "Rebuilding $package..."
    make "$package_path/compile"
    
    # Verify package was created
    if ls "$BUILD_DIR/bin/packages/mips_24kc"/*/"$package"*.ipk 1> /dev/null 2>&1; then
        print_info "✅ $package package created successfully"
        local package_file=$(ls -t "$BUILD_DIR/bin/packages/mips_24kc"/*/"$package"*.ipk | head -1)
        
        # Generate firmware image
        print_info "🔧 Generating firmware image with updated $package..."
        
        if [[ "$multi_threaded" == "true" ]]; then
            print_info "⚡ Using multi-threaded full build (fastest but risky)"
            local make_command="make -j$(nproc)"
        else
            print_info "🚀 Using optimized target build (fast and reliable)"
            local make_command="make target/linux/install"
        fi
        
        if $make_command; then
            print_success "✅ Package $package rebuild complete!"
            print_info "🎯 Updated firmware available in: $BUILD_DIR/bin/targets/"
        else
            print_error "❌ Firmware image generation failed"
            print_info "📦 Package available: $(basename "$package_file")"
            return 1
        fi
    else
        print_error "❌ $package package was not created"
        return 1
    fi
}

# Show build time estimates
show_time_estimates() {
    cat << EOF

⏱️  Build Time Estimates:
   Full build:        15-45 minutes (everything from scratch)
   lime rebuild:      5-10 minutes  (all lime-packages + optimized target build)  
   lime rebuild-fast: 3-8 minutes   (lime-app + optimized target build)

💡 Development Tips:
   - Use 'lime rebuild-fast' for lime-app UI changes
   - Use 'lime rebuild' for lime-packages changes
   - Add '--multi' for faster but riskier multi-threaded builds
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