#!/bin/bash
#
# LibreRouterOS Build Wrapper
# Sets up proper environment for lime-build repository structure
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
LIBREROUTEROS_DIR="$LIME_BUILD_DIR/repos/librerouteros"

# Check if we're in the right place
if [[ ! -f "$LIBREROUTEROS_DIR/librerouteros_build.sh" ]]; then
    echo "Error: LibreRouterOS build script not found"
    echo "Expected: $LIBREROUTEROS_DIR/librerouteros_build.sh"
    exit 1
fi

cd "$LIBREROUTEROS_DIR"

# Load unified source of truth from versions.conf
if [[ -f "$LIME_BUILD_DIR/scripts/utils/versions-parser.sh" ]]; then
    # Determine source mode from environment
    source_mode="default"
    if [[ -n "$LIME_LOCAL_MODE" && "$LIME_LOCAL_MODE" == "true" ]]; then
        source_mode="local"
    fi
    
    source <(QUIET=true "$LIME_BUILD_DIR/scripts/utils/versions-parser.sh" environment "$source_mode")
    echo "[LIME-DEV] Using unified source of truth (mode: $source_mode)"
    echo "[LIME-DEV] LibreMesh feed: $LIBREMESH_FEED"
    
    # Apply package-level source injection
    if [[ -x "$LIME_BUILD_DIR/scripts/utils/package-source-injector.sh" ]]; then
        echo "[LIME-DEV] Applying package-level source injection for $source_mode mode"
        if ! "$LIME_BUILD_DIR/scripts/utils/package-source-injector.sh" apply "$source_mode" "$LIME_BUILD_DIR/build"; then
            echo "[LIME-DEV] WARNING: Package source injection failed, continuing with defaults"
        fi
    fi
else
    # Fallback to direct environment setup
    export OPENWRT_SRC_DIR="$LIBREROUTEROS_DIR/openwrt/"
    export KCONFIG_UTILS_DIR="$LIME_BUILD_DIR/repos/kconfig-utils/"
    export LIBREROUTEROS_DIR="$LIBREROUTEROS_DIR"
    export OPENWRT_DL_DIR="$LIME_BUILD_DIR/dl/"
    export LIBREROUTEROS_BUILD_DIR="$LIME_BUILD_DIR/build/"
fi

# Ensure necessary directories exist
mkdir -p "$OPENWRT_DL_DIR"
mkdir -p "$LIBREROUTEROS_BUILD_DIR"

echo "LibreRouterOS Build Wrapper"
echo "  OpenWrt source: $OPENWRT_SRC_DIR"
echo "  Kconfig utils: $KCONFIG_UTILS_DIR"
echo "  Download dir: $OPENWRT_DL_DIR"
echo "  Build dir: $LIBREROUTEROS_BUILD_DIR"
echo "  Target: ${1:-librerouter-v1}"
echo ""

# Check if kconfig-utils is available
if [[ ! -f "$KCONFIG_UTILS_DIR/kconfig-utils.sh" ]]; then
    echo "Error: kconfig-utils.sh not found at $KCONFIG_UTILS_DIR"
    echo "Make sure repos are properly cloned with setup-lime-dev.sh"
    exit 1
fi

# Check if OpenWrt source is available
if [[ ! -d "$OPENWRT_SRC_DIR" ]]; then
    echo "Error: OpenWrt source not found at $OPENWRT_SRC_DIR"
    echo "Make sure repos are properly cloned with setup-lime-dev.sh"
    exit 1
fi

# Run the original LibreRouterOS build script
exec ./librerouteros_build.sh "$@"