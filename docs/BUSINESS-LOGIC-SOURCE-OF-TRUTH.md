# Business Logic Source of Truth - lime-dev Unified System

## Core Business Logic

The `/scripts/lime` command system implements a **unified source resolution architecture** that ensures consistent source-of-truth across all development workflows through a simplified default vs local approach.

### **Single-Stage Resolution Architecture**
- **When**: During any build or setup operation
- **What**: Direct source resolution from unified configuration
- **Where**: Single configuration file (`configs/versions.conf`)
- **Purpose**: Eliminate complexity while maintaining full functionality

## Business Logic Principles

### **1. Single Source of Truth**
All source decisions flow from `configs/versions.conf`:
```ini
[repositories]
# What gets cloned during setup
lime-app=https://github.com/libremesh/lime-app.git|master|origin
lime-packages=https://github.com/javierbrk/lime-packages.git|final-release|javierbrk

[sources]
# What gets used during builds
lime-app=tarball:https://github.com/Fede654/lime-app/releases/download:v0.2.27
lime-packages=feed_default:src-git
```

### **2. Mode-Driven Resolution**
Two clear modes replace complex legacy system:
- **Default mode**: Uses configured sources from `[sources]` section
- **Local mode** (`--local`): Forces local repository usage for development

### **3. Universal Application**
The same unified logic applies to ALL workflows:
- **Build System**: OpenWrt compilation with correct source injection
- **Package Resolution**: Automatic Makefile patching for local development
- **Feed Configuration**: Direct LIBREMESH_FEED generation
- **Development Workflow**: Seamless local vs remote source switching

### **4. Deterministic Resolution**
Same configuration + same mode = same sources, every time:
- Predictable source selection
- Reproducible builds across environments
- Consistent development experience

## Command Business Logic

### **`./lime build [target]`** (Default Mode)
**Business Logic**: Build firmware using configured sources for production
- **Source Resolution**: Uses `[sources]` section from versions.conf
- **Feed Generation**: LIBREMESH_FEED from configured repository
- **Package Sources**: Configured tarballs, git tags, or feed defaults
- **Use Case**: CI/CD builds, release preparation, stable testing

**Implementation Flow**:
```
versions.conf [sources] → environment variables → feed injection → build
```

### **`./lime build --local [target]`** (Local Mode)
**Business Logic**: Build firmware using local sources for development
- **Source Resolution**: Forces local repository paths
- **Feed Generation**: Local file:// URLs for lime-packages
- **Package Sources**: Local repositories with git protocol
- **Use Case**: Active development, feature testing, rapid iteration

**Implementation Flow**:
```
local detection → path override → Makefile patching → local build
```

### **`./lime setup`** (Development Setup)
**Business Logic**: Prepare complete development environment
- **Repository Cloning**: Downloads all source repositories locally
- **Configuration**: Sets up both default and local mode capability
- **Environment**: Prepares for switching between modes
- **Target Users**: Developers working on LibreMesh code

### **`./lime setup --build-remote-only`** (CI/CD Setup)
**Business Logic**: Minimal setup for automated builds
- **Repository Cloning**: Skipped to save time and space
- **Configuration**: Uses only configured sources
- **Environment**: Optimized for non-interactive builds
- **Target Users**: CI/CD systems, release builders

## Source Resolution Decision Tree

```
User Command
    ↓
Contains --local flag?
    ├─ YES → Local Mode
    │   ├─ Force local repository paths
    │   ├─ Apply Makefile patching
    │   └─ Use file:// feed URLs
    │
    └─ NO → Default Mode
        ├─ Parse [sources] section
        ├─ Generate environment variables
        └─ Use configured sources
```

## Package-Level Source Injection

### lime-app Package Resolution

**Default Mode**:
```bash
# From versions.conf [sources]
lime-app=tarball:https://github.com/Fede654/lime-app/releases/download:v0.2.27

# Results in Makefile
PKG_SOURCE_URL=https://github.com/Fede654/lime-app/releases/download/v0.2.27/lime-app-v0.2.27.tar.gz
```

**Local Mode**:
```bash
# Detected local repository
lime-app=local:/home/fede/REPOS/lime-dev/repos/lime-app

# Results in patched Makefile
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=file:///home/fede/REPOS/lime-dev/repos/lime-app
PKG_VERSION:=dev-$(git-hash)
```

### Feed-Level Source Injection

**Default Mode**:
```bash
# From versions.conf [sources]
lime-packages=feed_default:src-git

# Results in environment variable
LIBREMESH_FEED="src-git libremesh https://github.com/javierbrk/lime-packages.git;final-release"
```

**Local Mode**:
```bash
# Detected local repository
lime-packages=local:/home/fede/REPOS/lime-dev/repos/lime-packages

# Results in environment variable
LIBREMESH_FEED="src-git libremesh file:///home/fede/REPOS/lime-dev/repos/lime-packages;final-release"
```

## Consistency Guarantees

### **Cross-Workflow Consistency**
- Same configuration produces same results across all tools
- Mode selection affects all components uniformly
- No hidden or implicit source selections

### **Reproducible Builds**
- Default mode always uses same configured sources
- Local mode always uses same local repositories
- Environment variables are deterministically generated

### **Development Workflow Parity**
- Local changes immediately reflected in builds
- No manual intervention required for source switching
- Automatic detection and patching

## Validation and Error Handling

### **Pre-Build Validation**
```bash
# Automatic validation
./lime build --local x86_64   # Validates local repositories exist
./lime build x86_64           # Validates configured sources accessible

# Manual validation
./lime verify all             # Comprehensive environment check
```

### **Source Availability Checks**
- **Configured sources**: Validates URLs and versions exist
- **Local sources**: Validates repositories are cloned and accessible
- **Dependencies**: Ensures all required packages are available

### **Error Recovery**
- **Missing local repos**: Suggests running `./lime setup`
- **Invalid configuration**: Points to specific configuration issues
- **Network failures**: Provides offline alternatives where possible

## Migration from Legacy System

### **Eliminated Complexity**
- ❌ LIME_BUILD_MODE environment variable
- ❌ Development vs release mode confusion
- ❌ Complex conditional logic in multiple files
- ❌ Separate [package_sources] configuration sections

### **Preserved Capabilities**
- ✅ All development workflow functionality
- ✅ All production build capabilities
- ✅ Package-level source customization
- ✅ Feed-level source configuration

### **Improved Reliability**
- ✅ Single source of truth
- ✅ Deterministic source resolution
- ✅ Comprehensive validation
- ✅ Clear error messages

## Performance Optimization

### **Build-Remote-Only Mode**
- **Disk Space**: Saves ~2GB by not cloning repositories
- **Setup Time**: Reduces initial setup from ~5 minutes to ~30 seconds
- **Network Usage**: Only downloads when building, not during setup
- **CI/CD Efficiency**: Optimized for automated environments

### **Local Development Mode**
- **Iteration Speed**: Immediate source updates without re-download
- **Development Workflow**: Native git workflow with local repositories
- **Debugging**: Direct source access for troubleshooting
- **Feature Development**: Rapid prototype-test-iterate cycles

This unified business logic eliminates complexity while maintaining all functionality, providing a foundation for reliable, maintainable LibreMesh development workflows.