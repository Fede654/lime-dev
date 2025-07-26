# LibreRouterOS Build Architecture

## Overview
The LibreRouterOS build system provides a unified architecture for LibreMesh development with both Docker-based builds and native compilation. It features a simplified source resolution system that eliminates legacy complexity while maintaining full functionality.

## Source Resolution Architecture

### Unified Configuration (`configs/versions.conf`)
Single source of truth for all repository and build configuration:

```ini
[repositories]
# Repository definitions - what gets cloned during setup
lime-app=https://github.com/libremesh/lime-app.git|master|origin
lime-packages=https://github.com/javierbrk/lime-packages.git|final-release|javierbrk

[sources]
# Build-time source resolution - what gets used during builds
lime-app=tarball:https://github.com/Fede654/lime-app/releases/download:v0.2.27
lime-packages=feed_default:src-git
# Local development overrides (commented by default)
# lime-app=local:/home/fede/REPOS/lime-dev/repos/lime-app
# lime-packages=local:/home/fede/REPOS/lime-dev/repos/lime-packages
```

### Build Modes

**Default Mode** (`./lime build`)
- Uses configured sources from `[sources]` section
- Production builds with tagged releases
- Feed-level and package-level source injection

**Local Mode** (`./lime build --local`)
- Forces local repository usage for development
- Overrides configured sources with local paths
- Automatic Makefile patching for packages like lime-app

### Setup Modes

**Development Setup** (`./lime setup`)
- Clones repositories for local development
- Sets up local source overrides in configuration
- Default for developers working on LibreMesh

**Build-Remote-Only Setup** (`./lime setup --build-remote-only`)
- Downloads tagged releases only
- No local repository cloning
- Optimized for CI/CD and release builders

## Components

### Core Build System
- **`scripts/build.sh`** - Main build interface with unified architecture
- **`scripts/core/librerouteros-wrapper.sh`** - LibreRouterOS integration
- **`scripts/utils/versions-parser.sh`** - Unified configuration parsing
- **`scripts/utils/package-source-injector.sh`** - Package-level source injection

### Docker Container (Ubuntu 18.04)
- Solves GLIBC version compatibility issues
- Provides Python 2.7 environment required by OpenWrt
- Isolates build environment from host system
- Supports both default and local build modes

### Source Management
- **Feed-level injection**: LIBREMESH_FEED environment variable
- **Package-level injection**: Direct Makefile patching for lime-app
- **Unified parsing**: Single configuration file for all sources
- **Automatic detection**: Smart handling of local vs remote sources

## Build Process

1. **Environment Setup**
   - Unified configuration parsing from `versions.conf`
   - Build mode determination (default vs local)
   - Environment variable generation
   - Docker container preparation (if using Docker)

2. **Source Resolution**
   - Feed-level source injection via LIBREMESH_FEED
   - Package-level source injection for lime-app
   - Automatic Makefile patching for local development
   - Repository validation and integrity checks

3. **Source Preparation**
   - Feed updates and installation
   - Configuration loading with injected sources
   - Package dependency resolution

4. **Compilation**
   - Toolchain build with proper source configuration
   - Package compilation with injected sources
   - Firmware image generation

## Target Support
- LibreRouter v1 (ath79/generic)
- x86_64 (QEMU testing)
- Multi-device (multiple ath79 configurations)

## lime-app Integration

### Production Build
- Uses tarball sources from GitHub releases
- Supports treeshaking optimization for router deployment
- Minimal bundle size for embedded devices

### Development Build
- Uses local repository with `--local` flag
- Automatic Makefile patching in `lime-packages/packages/lime-app/`
- Real-time development workflow with QEMU integration

### Source Injection Mechanism
```bash
# Package-level injection (lime-app)
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=file:///path/to/local/lime-app
PKG_VERSION:=dev-$(git-hash)

# Feed-level injection (lime-packages)
LIBREMESH_FEED="src-git libremesh file:///path/to/local/lime-packages;branch"
```

## Architecture Benefits

### Simplified Workflow
- **Single source of truth**: One configuration file for all sources
- **Clear disambiguation**: Default vs local modes
- **Eliminated complexity**: No legacy development/release mode confusion
- **Unified interface**: Same commands work for all scenarios

### Developer Experience
- **Fast iteration**: Local sources with `--local` flag
- **Production parity**: Same build system for development and release
- **QEMU integration**: Seamless testing environment
- **Automatic patching**: No manual intervention required

### CI/CD Optimization
- **Build-remote-only**: Optimized for automated builds
- **Tagged releases**: Consistent source resolution
- **Environment variables**: Easy configuration management
- **Docker support**: Containerized builds for consistency

## Legacy Mode Elimination

The architecture has been simplified to remove legacy development/release mode complexity:

**Before (Legacy)**:
- Complex LIME_BUILD_MODE switches
- Separate [package_sources] sections
- Development vs release mode confusion
- Multiple configuration entry points

**After (Unified)**:
- Simple default vs local modes
- Single [sources] section
- Clear command-line flags (`--local`)
- Unified configuration parsing

This simplification maintains all functionality while eliminating sources of confusion and reducing maintenance overhead.
