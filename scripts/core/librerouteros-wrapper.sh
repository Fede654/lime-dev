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
    source <(QUIET=true "$LIME_BUILD_DIR/scripts/utils/versions-parser.sh" environment "${LIME_BUILD_MODE:-development}")
    echo "[LIME-DEV] Using unified source of truth (mode: ${LIME_BUILD_MODE:-development})"
    echo "[LIME-DEV] LibreMesh feed: $LIBREMESH_FEED"
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