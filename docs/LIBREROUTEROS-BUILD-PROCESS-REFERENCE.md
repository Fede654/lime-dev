# LibreRouterOS Build Process - Technical Reference

> **Note**: This document provides deep technical reference for the LibreRouterOS build system architecture. For practical build instructions, see [DEVELOPMENT.md](DEVELOPMENT.md). For business logic documentation, see [BUSINESS-LOGIC-SOURCE-OF-TRUTH.md](BUSINESS-LOGIC-SOURCE-OF-TRUTH.md).

## Overview

This document maps the complete build chain orchestration from entry point to final firmware generation, analyzing the hierarchical layers where code modifications occur during the LibreRouterOS build process.

## Build Chain Hierarchy

### Layer 0: Entry Points
```
scripts/lime                    # Main CLI dispatcher
scripts/build.sh               # Unified build manager  
build-with-qemu-drivers.sh     # QEMU-specific builds
```

### Layer 1: Build Orchestration
```
scripts/core/librerouteros-wrapper.sh
├── Environment variable processing
├── Target validation and routing
└── Execution delegation to Layer 2
```

### Layer 2: Core Build Logic
```
repos/librerouteros/librerouteros_build.sh (1,558 lines)
├── Target-specific configuration functions
├── Package selection orchestration  
├── Feed management and integration
└── OpenWrt build system invocation
```

### Layer 3: OpenWrt Build System
```
repos/librerouteros/openwrt/
├── Makefile system orchestration
├── Package compilation coordination
└── Kernel configuration integration
```

### Layer 4: Package Feeds
```
feeds/libremesh/     # LibreMesh packages
feeds/packages/      # OpenWrt packages
feeds/luci/          # Web interface
feeds/routing/       # Mesh routing protocols
feeds/telephony/     # Communication packages
```

## Build Process Call Chain

### 1. Entry Point Resolution
```bash
# User invocation
./scripts/lime build x86_64 --mode development

# Call resolution path
scripts/lime → scripts/build.sh → scripts/core/librerouteros-wrapper.sh
```

### 2. Environment Configuration
```bash
# librerouteros-wrapper.sh processes:
BUILD_TARGET="$1"                    # x86_64
LIME_BUILD_MODE="development"        # From --mode flag
BUILD_DEBUG=false                    # Default values
BUILD_DOWNLOAD_ONLY=false            # Default values

# Environment variable definitions (lo:define_default_value function)
OPENWRT_SRC_DIR="$HOME/Development/openwrt/"
LIBREROUTEROS_BUILD_DIR="$HOME/Builds/librerouterOS-$BUILD_TARGET/"
LIBREMESH_FEED="${LIBREMESH_FEED:-src-git libremesh https://github.com/javierbrk/lime-packages.git;final-release}"
```

### 3. Core Build Logic Invocation
```bash
# Execution delegation to target-specific function
case "$BUILD_TARGET" in
    x86_64)
        repos/librerouteros/librerouteros_build.sh
        ;;
esac
```

## Feed Integration Architecture

### Feed Configuration Sequence
```bash
# 1. Base feed initialization (librerouteros_build.sh:300-324)
cp ./feeds.conf.default ./feeds.conf

# 2. LibreMesh feed injection
echo "$LIBREMESH_FEED" >> ./feeds.conf
# Result: src-git libremesh https://github.com/javierbrk/lime-packages.git;final-release

# 3. Additional feeds
echo "$LIBREROUTER_FEED" >> ./feeds.conf    # Local packages
echo "$TMATE_FEED" >> ./feeds.conf           # Remote support
echo "$AMPR_FEED" >> ./feeds.conf            # AMPR protocol

# 4. Feed update and installation
./scripts/feeds update -a
./scripts/feeds install -a
```

### Package Selection Orchestration
```bash
# Configuration functions hierarchy (librerouteros_build.sh:75-192)
configure_librerouteros()
├── configure_libremesh()
│   ├── kconfig_set CONFIG_PACKAGE_lime-system
│   ├── kconfig_set CONFIG_PACKAGE_lime-proto-babeld  
│   ├── kconfig_set CONFIG_PACKAGE_lime-proto-batadv
│   └── [50+ mesh packages]
├── configure_remove_unused_packages()
│   ├── kconfig_unset CONFIG_PACKAGE_ppp
│   └── [remove conflicting packages]
└── configure_firstboot_wizard()
    └── kconfig_set CONFIG_PACKAGE_first-boot-wizard
```

## Target-Specific Build Paths

### x86_64 Target Configuration
```bash
# Function: target preparation (librerouteros_build.sh:483-549)
prepare_target_buildroot "$BUILD_TARGET"
├── mkdir -p "$LIBREROUTEROS_BUILD_DIR"
├── rm -rf "$LIBREROUTEROS_BUILD_DIR"          # Clean build
├── cp --recursive "$OPENWRT_SRC_DIR" "$LIBREROUTEROS_BUILD_DIR"
└── Feed configuration and package installation

# Target-specific kernel configuration
kconfig_set CONFIG_TARGET_x86                  # Architecture
kconfig_set CONFIG_TARGET_x86_64               # Sub-architecture  
kconfig_set CONFIG_TARGET_x86_64_DEVICE_generic # Device profile

# QEMU optimization
kconfig_set CONFIG_TARGET_KERNEL_PARTSIZE 32   # Kernel partition size
kconfig_set CONFIG_TARGET_ROOTFS_PARTSIZE 512  # Root filesystem size
kconfig_set CONFIG_TARGET_ROOTFS_EXT4FS         # Filesystem type
kconfig_set CONFIG_PACKAGE_kmod-e1000           # Network drivers
```

### LibreRouter v1 Target Configuration  
```bash
# Function: target_librerouter_v1() (librerouteros_build.sh:194-240)
kconfig_set CONFIG_TARGET_ath79                 # MIPS architecture
kconfig_set CONFIG_TARGET_ath79_generic         # Platform
kconfig_set CONFIG_TARGET_ath79_generic_DEVICE_librerouter_librerouter-v1

# Hardware-specific packages
kconfig_set CONFIG_PACKAGE_librerouter-1-hw-quircks    # Hardware quirks
kconfig_set CONFIG_PACKAGE_kmod-usb-ledtrig-usbport    # USB LED trigger
kconfig_set CONFIG_PACKAGE_safe-upgrade                # Dual-boot support

# Kernel optimization for embedded hardware
kconfig_set CONFIG_KERNEL_PROC_STRIPPED
kconfig_unset CONFIG_KERNEL_KALLSYMS
kconfig_unset CONFIG_KERNEL_DEBUG_INFO
```

## Code Modification Layers

### Layer 1: Build Script Modifications
```
Purpose: Build process customization, target addition, feed management
Location: scripts/, repos/librerouteros/librerouteros_build.sh
Impact: Build orchestration, package selection, target definitions
```

### Layer 2: Feed-Level Modifications
```
Purpose: Package-level customization, new packages, package patches
Location: feeds/libremesh/, feeds/packages/, patches/
Impact: Package availability, package configuration, feature addition
```

### Layer 3: Package-Level Modifications
```
Purpose: Individual package customization, configuration changes
Location: feeds/libremesh/packages/*/
Impact: Specific package behavior, feature enabling/disabling
```

### Layer 4: Kernel Configuration
```
Purpose: Kernel feature enabling, hardware support, driver inclusion
Location: Kconfig system integration within build functions
Impact: Hardware compatibility, kernel feature set, driver availability
```

## Configuration System Deep Dive

### Kconfig Integration
```bash
# Kconfig utility functions (via kconfig-utils)
source "$KCONFIG_UTILS_DIR/kconfig-utils.sh"

# Configuration manipulation
kconfig_set CONFIG_PACKAGE_lime-system         # Enable package
kconfig_unset CONFIG_PACKAGE_ppp               # Disable package
kconfig_init_register                          # Initialize tracking
kconfig_check                                  # Validate configuration
```

### Environment Variable Cascade
```bash
# Priority order (highest to lowest):
1. Command-line environment variables
2. LIME_BUILD_MODE overrides (development/release)  
3. lo:define_default_value definitions
4. Hardcoded defaults

# Example cascade for LIBREMESH_FEED:
LIBREMESH_FEED="${LIBREMESH_FEED:-src-git libremesh https://github.com/javierbrk/lime-packages.git;final-release}"
# ↑ Uses environment variable if set, otherwise default
```

### Development Mode Overrides
```bash
# Development mode conditional logic (librerouteros_build.sh:98-101)
if [[ "${LIME_BUILD_MODE:-development}" == "development" ]]; then
    kconfig_set CONFIG_PACKAGE_shared-state-mesh_config
    kconfig_set CONFIG_PACKAGE_shared-state-mesh_wide_upgrade
fi
```

## Package Selection Matrix

### Core LibreMesh Packages (Always Enabled)
```
lime-system                    # Core mesh system
lime-proto-anygw              # Any gateway protocol
lime-proto-babeld             # Babel routing protocol  
lime-proto-batadv             # Batman-adv mesh protocol
lime-proto-wan                # WAN interface management
lime-hwd-openwrt-wan          # Hardware WAN detection
```

### Shared State System
```
shared-state                   # Core shared state framework
shared-state-async            # Asynchronous replication
shared-state-babeld_hosts     # Babel host discovery
shared-state-bat_hosts        # Batman host discovery
shared-state-dnsmasq_hosts    # DNS host management
shared-state-nodes_and_links  # Network topology
```

### Development-Only Packages
```
shared-state-mesh_config      # Mesh-wide configuration (LIME_BUILD_MODE=development)
shared-state-mesh_wide_upgrade # Mesh-wide upgrade system
```

### Application Layer
```
lime-app                      # Web interface application
lime-docs-minimal            # Documentation
check-date-http              # Time synchronization
safe-reboot                  # Safe reboot mechanism
```

## Build Output Analysis

### Target-Specific Outputs
```bash
# x86_64 target outputs
bin/targets/x86/64/
├── librerouteros-*-x86-64-generic-squashfs-combined.img.gz    # QEMU/VM image
├── librerouteros-*-x86-64-generic-ext4-combined.img.gz        # Alternative filesystem
├── librerouteros-*-x86-64-generic-rootfs.tar.gz               # QEMU development
└── librerouteros-*-x86-64-generic-kernel.bin                  # Kernel binary

# LibreRouter v1 outputs  
bin/targets/ath79/generic/
├── librerouteros-*-ath79-generic-librerouter_librerouter-v1-squashfs-sysupgrade.bin
└── librerouteros-*-ath79-generic-librerouter_librerouter-v1-squashfs-factory.bin
```

### Build Artifacts Structure
```
$LIBREROUTEROS_BUILD_DIR/
├── .config                    # Final kernel configuration
├── build.log                  # Build process log
├── bin/                       # Final firmware images
├── build_dir/                 # Intermediate build files
├── dl/                        # Downloaded sources (shared)
├── feeds/                     # Integrated feed packages
├── staging_dir/               # Build tools and libraries
└── tmp/                       # Temporary build artifacts
```

## Modification Impact Analysis

### High-Impact Modification Points
```
1. Target Definition (librerouteros_build.sh:330-549)
   - New hardware support
   - Architecture-specific optimizations
   - Package set customization

2. Package Selection Logic (librerouteros_build.sh:75-160)  
   - Feature enabling/disabling
   - Package dependency management
   - Configuration conflicts resolution

3. Feed Integration (librerouteros_build.sh:314-322)
   - External package sources
   - Version pinning and branch selection
   - Custom package repositories
```

### Low-Impact Modification Points
```
1. Environment Variable Defaults (librerouteros_build.sh:40-56)
   - Build directory locations
   - Default repository URLs
   - Build behavior flags

2. Package Version Overrides (configs/versions.conf)
   - Repository version pinning
   - Development/release mode switching
   - Dependency version management
```

## Build Process State Tracking

### Configuration Validation
```bash
# Configuration consistency checking (librerouteros_build.sh:180-192)
make defconfig                 # Apply defaults and resolve dependencies
kconfig_check                  # Validate final configuration  
kconfig_wipe_register         # Clean up tracking state
```

### Error Handling and Recovery
```bash
# Build failure detection
set -o errexit                # Fail on command errors
set -o errtrace               # Trace error sources
set -o nounset                # Fail on undefined variables

# Build debugging support
if $BUILD_DEBUG; then
    MAKE_FLAGS="-j1 V=sc"      # Verbose single-threaded build
else  
    MAKE_FLAGS="-j$(nproc)"    # Parallel optimized build
fi
```

This technical reference maps the complete build orchestration, providing the foundation for understanding where and how code modifications propagate through the LibreRouterOS build system.

## Lime-App Package Integration Deep Dive

### Overview
The lime-app integration demonstrates the **complete Source of Truth → Package Resolution** flow implemented in the lime-dev system. This section documents both the traditional mechanism and the new configuration-driven approach.

### Insertion Flow Hierarchy

#### 1. Package Selection Trigger
```bash
# librerouteros_build.sh:135 - Core package enablement
kconfig_set CONFIG_PACKAGE_lime-app
```

#### 2. Feed Resolution (Dual-Path Mechanism)

**Path A: librerouteros Feed (External Stable)**
```makefile
# repos/librerouteros/feeds/libremesh/packages/lime-app/Makefile
PKG_VERSION:=v0.2.25
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz  
PKG_SOURCE_URL:=https://github.com/libremesh/lime-app/releases/download/$(PKG_VERSION)
PKG_HASH:=7804eb39686d94c50347170cf01b2d4d810e8cae33b7c1ed2787c19f4a4c2046
```

**Path B: lime-packages Feed (Development)**
```makefile
# repos/lime-packages/packages/lime-app/Makefile
PKG_VERSION:=v0.2.27
PKG_SOURCE_URL:=https://github.com/Fede654/lime-app/releases/download/$(PKG_VERSION)
PKG_HASH:=c2b19242166d8cdce487d68622fcf1d2857053059a3f47b51417754161f8b57c
```

#### 3. Build Phase Integration Strategy

**External Source Processing:**
```makefile
# Both Makefiles follow identical pattern
define Build/Compile
endef  # No compilation - pre-built JavaScript bundle

define Package/lime-app/install
    $(INSTALL_DIR) $(1)/
    $(CP) ./files/* $(1)/                    # Local configuration overlay
    $(INSTALL_DIR) $(1)/www/app/
    $(CP) $(BUILD_DIR)/build/* $(1)/www/app/ # Downloaded build artifacts
endef
```

**Local File Overlay Resolution:**
```
./files/ directory structure:
├── etc/uci-defaults/
│   ├── 90_lime-app                    # Authentication setup
│   ├── 95-lime-app-rpc-acl            # RPC access control
│   ├── 96-lime-app-index_page         # Web server redirect 
│   └── 99-lime-app-update-title       # UI customization
├── usr/share/rpcd/acl.d/
│   └── iwinfo.json                    # API permissions
└── www/
    └── lime_app_index.html            # Entry point redirect
```

#### 4. Build-Time File Merge Hierarchy

**Source Integration Priority:**
```
1. External GitHub Release ($(BUILD_DIR)/build/*)
   ├── index.html                 # React application entry point
   ├── bundle.*.js                # Application JavaScript chunks
   ├── vendors.chunk.*.js          # Third-party dependencies  
   ├── *.css                      # Stylesheets
   ├── assets/icons/              # UI icons and images
   └── manifest.json              # PWA configuration

2. Local Configuration Overlay (./files/*)
   ├── lime_app_index.html        # Router root redirect override
   ├── uci-defaults scripts       # System integration hooks
   └── ACL permission files       # API access definitions
```

### Critical System Integration Points

#### A. Web Server Integration
```bash
# 96-lime-app-index_page
uci set uhttpd.main.index_page=lime_app_index.html

# lime_app_index.html content:
<meta http-equiv="refresh" content="0; URL=/app" />
```
**Result:** Router root (/) automatically redirects to /app

#### B. Authentication System Injection
```bash
# 90_lime-app authentication setup
uci add rpcd login
uci set rpcd.@login[1].username='lime-app'
uci set rpcd.@login[1].password='$1$$ta3C2yX4TvVObdaJyQ9Md1'  # Empty password hash
uci add_list rpcd.@login[1].read='lime-app'
uci add_list rpcd.@login[1].write='lime-app'
uci add_list rpcd.@login[1].read='unauthenticated'
uci add_list rpcd.@login[1].write='unauthenticated'
uci set uhttpd.main.ubus_cors='1'  # Enable CORS for API access
```

#### C. API Permission Framework
```json
# Representative ACL file (iwinfo.json)
{
    "lime-app": {
        "read": { 
            "ubus": { 
                "iwinfo": [ "assoclist" ] 
            }
        },
        "write": { 
            "ubus": { 
                "iwinfo": [ "assoclist" ] 
            }
        }
    }
}
```

#### D. Service Dependency Chain
```makefile
DEPENDS:=+rpcd +uhttpd +uhttpd-mod-ubus +uhttpd-mod-lua \
    +ubus-lime-location +ubus-lime-metrics +ubus-lime-utils \
    +rpcd-mod-iwinfo +ubus-lime-groundrouting
```

**Dependency Resolution Order:**
1. **Web Infrastructure:** rpcd (RPC daemon), uhttpd (web server), ubus modules
2. **LibreMesh APIs:** location, metrics, utils, groundrouting services
3. **Network Information:** iwinfo for wireless interface data

### Modern Source Resolution (Configuration-Driven)

**New Architecture Overview:**
With the configuration-driven build mode validation system, lime-app source resolution is now controlled by `configs/versions.conf`:

```ini
[package_sources]
# Production: Stable GitHub releases
lime_app_production=tarball:https://github.com/Fede654/lime-app/releases/download:v0.2.27

# Development: Local repository for rapid iteration  
lime_app_development=local:/home/fede/REPOS/lime-dev/repos/lime-app:HEAD

[makefile_patches]
# Development mode patches Makefile to use local sources
lime_app=source_replacement:PKG_SOURCE:PKG_SOURCE_URL:PKG_VERSION
```

**Build Mode Resolution:**
```bash
# Development mode: Uses local repository
./scripts/build.sh --mode development librerouter-v1
# → PKG_SOURCE_URL:=file:///home/fede/REPOS/lime-dev/repos/lime-app
# → PKG_VERSION:=dev-$(shell cd /path && git rev-parse --short HEAD)

# Release mode: Uses production tarball  
./scripts/build.sh --mode release librerouter-v1
# → PKG_SOURCE_URL:=https://github.com/Fede654/lime-app/releases/download/v0.2.27
# → PKG_VERSION:=v0.2.27
```

**Legacy Behavior (Pre-Configuration System):**
- **librerouteros feed:** v0.2.25 (stable release)
- **lime-packages feed:** v0.2.27 (active development)
- **Source repositories:** Different GitHub sources (libremesh vs Fede654)
- **Resolution:** Feed installation order determined priority (lime-packages won)

### Runtime Integration Sequence

#### 1. Package Build Integration
```bash
$(eval $(call BuildPackage,lime-app))
# Triggers OpenWrt package build system integration
```

#### 2. File System Layout
```
Target filesystem integration:
/www/
├── app/                           # React application deployment
│   ├── index.html                # Main application entry
│   ├── bundle.*.js               # Application code chunks
│   ├── vendors.chunk.*.js        # Dependency bundles
│   ├── *.css                     # Stylesheet files
│   └── assets/                   # Static resources
└── lime_app_index.html           # Root redirect page

/etc/uci-defaults/                 # First-boot configuration
├── 90_lime-app                   # Authentication setup
├── 96-lime-app-index_page        # Web server redirect
└── 99-lime-app-update-title      # UI customization

/usr/share/rpcd/acl.d/            # API access control
└── *.json                        # Service-specific permissions
```

#### 3. Service Configuration (Post-Install Hook)
```bash
# Makefile postinst execution
define Package/lime-app/postinst
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || ( /etc/init.d/rpcd restart && /etc/init.d/uhttpd restart ) || true
endef
```

### Development vs Production Paths

**Development Override Mechanism:**
The lime-packages version (v0.2.27) indicates active development fork, while librerouteros maintains stable v0.2.25.

**Local Development Integration:**
```bash
# Manual development deployment
mkdir -p repos/lime-packages/packages/lime-app/files/www/app/
npm run build:production && cp -r build/* repos/lime-packages/packages/lime-app/files/www/app/
```

**Override Priority Points:**
1. **Direct file replacement** in `lime-packages/packages/lime-app/files/www/app/`
2. **Build-time injection** via `$(BUILD_DIR)/build/*` path resolution
3. **Feed prioritization** through installation sequence
4. **Version selection** via PKG_VERSION and PKG_HASH validation

### Security Architecture

**Authentication Bypass Implementation:**
```bash
# Creates passwordless lime-app user
uci set rpcd.@login[1].password='$1$$ta3C2yX4TvVObdaJyQ9Md1'  # Empty password hash
```

**API Surface Control:**
Each LibreMesh service (location, metrics, utils, etc.) provides ACL files granting `lime-app` user specific ubus permissions without additional authentication requirements.

**Permission Distribution:**
```
/usr/share/rpcd/acl.d/
├── batman-adv.json        # Batman mesh protocol access
├── groundrouting.json     # Ground routing configuration  
├── iwinfo.json           # Wireless interface information
├── lime-utils.json       # Core LibreMesh utilities
├── location.json         # Node location services
├── metrics.json          # Network metrics collection
├── network_nodes.json    # Network topology access
└── pirania.json          # Captive portal management
```

### Package Integration Complexity

This lime-app sub-mechanism demonstrates **multi-layer integration complexity**:

1. **Source Layer:** Dual-repository external fetching with version conflict resolution
2. **Build Layer:** Pre-compiled asset integration with local configuration overlay
3. **System Layer:** Authentication, web server, and API framework integration
4. **Runtime Layer:** Service restart coordination and permission activation

The mechanism showcases how LibreMesh achieves **modular web application deployment** while maintaining system-level integration through OpenWrt's package management framework.

## Configuration-Driven Build System Integration

### Build Mode Validation
The modern lime-dev system includes comprehensive validation to prevent expensive build failures:

```bash
# Automatic validation before builds
./scripts/build.sh --mode development librerouter-v1
# → Validates configuration consistency before expensive compilation

# Manual validation for CI/CD
./scripts/utils/validate-build-mode.sh development
# → Tests conditional resolution without building
```

### Key Integration Points

**Source of Truth Flow:**

1. **Configuration**: `configs/versions.conf` defines all repository sources and package resolutions
2. **Environment Generation**: `scripts/utils/versions-parser.sh` processes configuration into environment variables
3. **Package Injection**: `scripts/utils/package-source-injector.sh` patches Makefiles for development mode
4. **Build Execution**: Standard LibreRouterOS build with dynamically configured sources

**Validation Benefits:**

- **Cost Savings**: Detects configuration issues before 30+ minute builds
- **Configuration Consistency**: Ensures resolved sources match expected configuration
- **Business Logic Testing**: Validates conditional resolution logic, not just file patching
- **CI/CD Integration**: Can be used in automated pipelines for pre-build validation

This integration represents the evolution from hardcoded build paths to a fully configuration-driven system where business logic controls all source resolution decisions.
