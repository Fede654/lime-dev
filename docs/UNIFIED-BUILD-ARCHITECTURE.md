# Unified Build Architecture - lime-dev Simplified System

## Overview

The lime-dev build system has been completely redesigned to eliminate legacy complexity while maintaining full functionality. The new unified architecture provides a simple, clear distinction between default (configured sources) and local (development sources) builds.

## Architecture Benefits

### Before (Legacy)
- Complex LIME_BUILD_MODE switches (development/release)
- Separate [package_sources] sections in configuration
- Multiple configuration entry points
- Confusion between development vs release modes
- Legacy technical debt and maintenance overhead

### After (Unified)
- Simple default vs local modes
- Single [sources] section in configuration
- Unified configuration parsing
- Clear command-line flags (`--local`)
- Eliminated sources of confusion

## Source Resolution System

### Single Source of Truth

**File**: `configs/versions.conf`

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

#### Default Mode (`./lime build`)
- Uses configured sources from `[sources]` section
- Production builds with tagged releases and specified feeds
- Optimized for CI/CD and release builds
- Feed-level and package-level source injection from configuration

**Example**:
```bash
./lime build configs/example_config_librerouter
./lime build x86_64
```

#### Local Mode (`./lime build --local`)
- Forces local repository usage for development
- Overrides configured sources with local paths
- Automatic Makefile patching for packages like lime-app
- Optimized for rapid development iteration

**Example**:
```bash
./lime build --local configs/example_config_librerouter
./lime build --local x86_64
```

### Setup Modes

#### Development Setup (`./lime setup`)
- Clones repositories for local development
- Sets up environment for both modes
- Default for developers working on LibreMesh
- Creates local repository structure

#### Build-Remote-Only Setup (`./lime setup --build-remote-only`)
- Downloads tagged releases only
- No local repository cloning
- Optimized for CI/CD and release builders
- Minimal disk space usage

## Implementation Architecture

### Core Components

1. **`scripts/build.sh`** - Main build interface with unified architecture
2. **`scripts/core/librerouteros-wrapper.sh`** - LibreRouterOS integration
3. **`scripts/utils/versions-parser.sh`** - Unified configuration parsing
4. **`scripts/utils/package-source-injector.sh`** - Package-level source injection

### Source Injection Mechanisms

#### Feed-level Injection
**Environment Variable**: `LIBREMESH_FEED`
```bash
# Default mode
LIBREMESH_FEED="src-git libremesh https://github.com/javierbrk/lime-packages.git;final-release"

# Local mode
LIBREMESH_FEED="src-git libremesh file:///home/fede/REPOS/lime-dev/repos/lime-packages;final-release"
```

#### Package-level Injection (lime-app)
**Direct Makefile Patching**: `lime-packages/packages/lime-app/Makefile`
```bash
# Default mode (original configuration preserved)
PKG_SOURCE_URL=https://github.com/Fede654/lime-app/releases/download/v0.2.27/lime-app-v0.2.27.tar.gz

# Local mode (automatically patched)
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=file:///home/fede/REPOS/lime-dev/repos/lime-app
PKG_VERSION:=dev-$(git-hash)
```

### Build Process Flow

```
User Command: ./lime build [--local] [target]
    ↓
scripts/build.sh (determines build mode)
    ↓
scripts/utils/versions-parser.sh (parses unified configuration)
    ↓
scripts/core/librerouteros-wrapper.sh (applies source injection)
    ↓
scripts/utils/package-source-injector.sh (patches package Makefiles)
    ↓
repos/librerouteros/librerouteros_build.sh (executes build)
    ↓
OpenWrt build system (uses injected sources)
```

## Development Workflows

### Rapid Development Iteration

```bash
# Setup development environment
./lime setup

# Edit lime-app code
cd repos/lime-app/src/
# Make changes...

# Build and test with local sources
./lime build --local x86_64
./lime qemu start

# Test changes at http://10.13.0.1/app/
```

### Production Build

```bash
# Setup for production builds
./lime setup --build-remote-only

# Build with configured sources
./lime build configs/example_config_librerouter

# Result uses tagged releases and configured feeds
```

### CI/CD Integration

```bash
# Automated build setup
./lime setup --build-remote-only

# Verify configuration
./lime verify all

# Build with validation
./lime build configs/example_config_x86_64
```

## lime-app Integration

### Development Build Process

When using `--local` mode:

1. **Detection**: System detects lime-app package needs local sources
2. **Patching**: Automatically patches `lime-packages/packages/lime-app/Makefile`
3. **Source Setup**: Configures git protocol with local repository path
4. **Build Integration**: OpenWrt build system uses local lime-app sources
5. **Treeshaking**: Production build optimizations still apply

### Production Build Process

When using default mode:

1. **Configuration**: Uses tarball source from GitHub releases
2. **Download**: Fetches specified version (e.g., v0.2.27)
3. **Optimization**: Applies treeshaking for minimal bundle size
4. **Integration**: Standard OpenWrt package build process

## Validation System

### Pre-Build Validation

```bash
# Automatic validation during builds
./lime build --local x86_64  # Validates local sources
./lime build x86_64           # Validates configured sources

# Manual validation
./lime verify all
```

### Configuration Verification

The system validates:
- Source resolution correctness
- Repository availability
- Makefile patching success
- Environment variable consistency
- Package dependencies

## Migration from Legacy System

### Eliminated Components

- ❌ `LIME_BUILD_MODE` environment variable
- ❌ Complex mode switching logic
- ❌ Separate [package_sources] sections
- ❌ Development vs release mode confusion
- ❌ Multiple configuration entry points

### Preserved Functionality

- ✅ All development capabilities
- ✅ All production build features
- ✅ Automatic source resolution
- ✅ Package-level customization
- ✅ QEMU integration
- ✅ CI/CD compatibility

## Commands Reference

### Setup Commands
```bash
./lime setup                    # Development setup (clones repos)
./lime setup --build-remote-only # CI/CD setup (no local repos)
```

### Build Commands
```bash
./lime build                    # Default mode (configured sources)
./lime build --local            # Local mode (development sources)
./lime build --local x86_64     # Local mode with specific target
```

### Verification Commands
```bash
./lime verify all               # Complete validation
./lime verify setup             # Setup validation
./lime verify repos             # Repository validation
```

## Benefits of Unified Architecture

### Developer Experience
- **Simpler commands**: Clear distinction between modes
- **Faster iteration**: Direct local source usage
- **Reduced confusion**: Eliminated legacy complexity
- **Better debugging**: Clear error messages and validation

### CI/CD Optimization
- **Consistent builds**: Single configuration source
- **Faster setup**: Build-remote-only mode
- **Reliable validation**: Comprehensive checks
- **Easy maintenance**: Reduced configuration overhead

### System Maintenance
- **Single source of truth**: One configuration file
- **Reduced complexity**: Eliminated legacy code paths
- **Better testing**: Unified validation system
- **Future-proof**: Clear architecture for extensions

## Troubleshooting

### Common Issues

**Problem**: Build uses wrong sources
```bash
# Solution: Check current mode and configuration
./lime verify all
grep -A 10 "\[sources\]" configs/versions.conf
```

**Problem**: Local sources not detected
```bash
# Solution: Verify repository setup and use --local flag
./lime build --local x86_64
./scripts/utils/package-source-injector.sh apply local ./build
```

**Problem**: Configuration validation fails
```bash
# Solution: Check repository availability
./lime verify repos
./lime setup  # Re-run setup if needed
```

### Debug Commands

```bash
# Check source resolution
QUIET=false scripts/utils/versions-parser.sh environment default
QUIET=false scripts/utils/versions-parser.sh environment local

# Test package source injection
./scripts/utils/package-source-injector.sh test local

# Verify environment setup
./lime verify all
```

## Future Enhancements

The unified architecture provides a foundation for future enhancements:

- **Additional packages**: Easy extension of package-level injection
- **New source types**: Simple addition of new source protocols
- **Enhanced validation**: More comprehensive pre-build checks
- **Performance optimization**: Caching and parallel processing
- **IDE integration**: Better development environment support

This unified system maintains all functionality while dramatically simplifying configuration, reducing maintenance overhead, and improving developer experience.