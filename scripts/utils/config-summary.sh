#!/bin/bash

# Configuration Summary Script for LibreRouterOS builds
# Shows what packages will actually be included before building

set -e

BUILD_TARGET="${1:-librerouter-v1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_DEV_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the build script functions without running them
source "$LIME_DEV_ROOT/repos/librerouteros/librerouteros_build.sh" || {
    echo "Error: Cannot source librerouteros_build.sh"
    exit 1
}

function show_config_summary() {
    local config_file="$1"
    local temp_build_dir="$2"
    
    echo "=== CONFIGURATION SUMMARY FOR TARGET: $BUILD_TARGET ==="
    echo "Build directory: $temp_build_dir"
    echo "Config file: $config_file"
    echo
    
    if [ ! -f "$config_file" ]; then
        echo "❌ Config file not found: $config_file"
        return 1
    fi
    
    echo "🔍 LUCI PACKAGES:"
    grep -E "CONFIG_PACKAGE_luci" "$config_file" | head -20 || echo "  No LuCI packages found"
    echo
    
    echo "🔍 LIME PACKAGES:"
    grep -E "CONFIG_PACKAGE_lime" "$config_file" | head -20 || echo "  No Lime packages found"
    echo
    
    echo "🔍 WEB INTERFACE PACKAGES:"
    grep -E "CONFIG_PACKAGE_(luci|lime-app|uhttpd)" "$config_file" | head -20 || echo "  No web interface packages found"
    echo
    
    echo "📊 PACKAGE SUMMARY:"
    local total_packages=$(grep -c "CONFIG_PACKAGE_.*=y" "$config_file" 2>/dev/null || echo "0")
    local luci_packages=$(grep -c "CONFIG_PACKAGE_luci.*=y" "$config_file" 2>/dev/null || echo "0")
    local lime_packages=$(grep -c "CONFIG_PACKAGE_lime.*=y" "$config_file" 2>/dev/null || echo "0")
    
    echo "  Total packages enabled: $total_packages"
    echo "  LuCI packages enabled: $luci_packages"
    echo "  Lime packages enabled: $lime_packages"
    echo
    
    if [ "$luci_packages" -gt 0 ]; then
        echo "⚠️  WARNING: LuCI packages are enabled even though lime-app should replace the web interface"
        echo "   This suggests dependency issues or legacy configuration"
        echo
        echo "   LuCI packages found:"
        grep "CONFIG_PACKAGE_luci.*=y" "$config_file" | sed 's/^/     /'
        echo
    fi
    
    echo "🎯 KEY COMPONENTS STATUS:"
    check_package_status "$config_file" "CONFIG_PACKAGE_lime-app" "Lime App (new UI)"
    check_package_status "$config_file" "CONFIG_PACKAGE_luci" "LuCI Web Interface"
    check_package_status "$config_file" "CONFIG_PACKAGE_uhttpd" "HTTP Server"
    check_package_status "$config_file" "CONFIG_PACKAGE_rpcd" "RPC Daemon (ubus)"
    echo
}

function check_package_status() {
    local config_file="$1"
    local package_config="$2" 
    local package_name="$3"
    
    if grep -q "^${package_config}=y" "$config_file" 2>/dev/null; then
        echo "  ✅ $package_name: ENABLED"
    elif grep -q "^# ${package_config} is not set" "$config_file" 2>/dev/null; then
        echo "  ❌ $package_name: EXPLICITLY DISABLED"
    else
        echo "  ❓ $package_name: NOT CONFIGURED (may be auto-selected by dependencies)"
    fi
}

function create_test_config() {
    echo "🚀 Creating test configuration for target: $BUILD_TARGET"
    
    # Create temporary build directory
    local temp_build_dir="/tmp/librerouteros-config-test-$BUILD_TARGET"
    export LIBREROUTEROS_BUILD_DIR="$temp_build_dir"
    export KCONFIG_CONFIG_PATH="$temp_build_dir/.config"
    
    echo "  Preparing build environment..."
    prepare_target_buildroot "$BUILD_TARGET" > /dev/null 2>&1
    
    echo "  Configuring target..."
    case "$BUILD_TARGET" in
        librerouter-v1)
            target_librerouter_v1 > /dev/null 2>&1
            ;;
        ath79_generic_multiradio)
            target_ath79_generic_multiradio > /dev/null 2>&1
            ;;
        x86_64)
            target_x86_64 > /dev/null 2>&1
            ;;
        *)
            echo "❌ Unsupported target: $BUILD_TARGET"
            exit 1
            ;;
    esac
    
    show_config_summary "$KCONFIG_CONFIG_PATH" "$temp_build_dir"
    
    echo "💾 Configuration files saved at:"
    echo "  Main config: $KCONFIG_CONFIG_PATH"
    echo "  Build dir: $temp_build_dir"
    echo
    echo "🗑️  To clean up: rm -rf $temp_build_dir"
}

function show_usage() {
    echo "Usage: $0 [TARGET]"
    echo
    echo "Available targets:"
    echo "  librerouter-v1           LibreRouter v1 hardware"
    echo "  ath79_generic_multiradio Multi-radio ATH79 devices"
    echo "  x86_64                   x86_64 PC/VM builds"
    echo
    echo "This script shows what packages will be included in the build"
    echo "without actually performing the build process."
}

case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
    "")
        echo "No target specified, using default: librerouter-v1"
        create_test_config
        ;;
    *)
        create_test_config
        ;;
esac