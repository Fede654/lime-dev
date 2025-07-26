# BUILD_MODE Mechanism - lime-dev Unified Build System

## Missing Package Dependencies Analysis

During the build process, several package warnings appear for missing dependencies. These are non-critical but indicate packages that could enhance functionality:

### Network Performance Libraries
- **`libev`**: High-performance event loop library for asynchronous network operations
  - **Used by**: `addrwatch`, `bfdd`, network monitoring tools
  - **Decision**: Include for enhanced network monitoring in mesh environments

### Authentication & RPC Libraries
- **`libpam`**: Pluggable Authentication Modules for advanced authentication
  - **Used by**: Advanced SSH services, VPN servers, custom authentication
  - **Decision**: Optional - only include if advanced authentication needed
  - **Alternative**: Use `dropbear` simple authentication for embedded systems

- **`libtirpc`**: Transport Independent RPC library with IPv6 support
  - **Used by**: `nfs-kernel-server`, `rpcbind`, distributed services
  - **Decision**: Include if NFS or distributed services are needed
  - **Alternative**: `librpc` for lighter embedded use

### Legacy Routing Protocols
- **`bird1-ipv4`** / **`bird1-ipv6`**: BIRD Internet Routing Daemon (legacy v1.6)
  - **Used by**: BGP, OSPF routing protocols for IPv4/IPv6
  - **LibreMesh Context**: Normally uses `babeld`, `batman-adv`, or `bmx7`
  - **Decision**: Skip unless specific BGP/OSPF requirements exist
  - **Modern Alternative**: `bird2` (unified IPv4/IPv6 support)

### Recommendation Summary

**Include in builds**:
- `libev` - Enhances network performance
- `libtirpc` - Enables NFS and distributed services

**Optional/Skip**:
- `libpam` - Use only for advanced authentication needs
- `bird1-ipv4`/`bird1-ipv6` - LibreMesh uses better mesh routing protocols

---

## Overview

The `LIME_BUILD_MODE` system provides unified control over the entire lime-dev build toolchain, enabling seamless switching between development and release configurations without requiring manual interventions or CI/CD pipeline modifications.

## Problem Solved

**Original Issue**: The build system had disconnected mechanisms where:
- `LIME_BUILD_MODE` variable existed but was ignored by critical build components  
- Different Makefiles were used for development vs production (lime-packages vs librerouteros)
- lime-app versions were hardcoded in multiple places with inconsistent sources
- Development iteration required full CI/CD cycles for each change

**Solution**: Surgical intervention at the feed configuration level that makes `LIME_BUILD_MODE` the single source of truth for the entire build system.

## Architecture

### Control Flow

```
./lime build --mode [development|release]
    ↓
scripts/build.sh (sets LIME_BUILD_MODE environment variable)
    ↓  
scripts/utils/versions-parser.sh (generates environment)
    ↓
repos/librerouteros/librerouteros_build.sh (respects LIME_BUILD_MODE)
    ↓
Feed configuration (selects appropriate package sources)
    ↓
OpenWrt build system (uses configured feeds)
```

### Key Files

1. **Control Point**: `scripts/build.sh:203`
   - Accepts `--mode [development|release]` parameter
   - Sets `LIME_BUILD_MODE` environment variable

2. **Environment Generation**: `scripts/utils/versions-parser.sh`
   - Processes `configs/versions.conf` configuration
   - Generates environment variables for build process

3. **Feed Selection**: `repos/librerouteros/librerouteros_build.sh:48-65`
   - **SURGICAL INTERVENTION POINT**
   - Uses `LIME_BUILD_MODE` to select appropriate package feeds
   - Controls which repositories and branches are used

4. **Package Makefiles**: Auto-configured via feed selection
   - `repos/lime-packages/packages/lime-app/Makefile` (development)
   - `repos/librerouteros/feeds/libremesh/packages/lime-app/Makefile` (release)

## Build Modes

### Development Mode (`LIME_BUILD_MODE=development`)

**Purpose**: Rapid iteration with experimental packages
- **lime-app source**: `github.com/Fede654/lime-app` (fork with latest features)
- **lime-packages**: `github.com/javierbrk/lime-packages.git;final-release`
- **Version**: Latest development versions (v0.2.27+)
- **Use case**: Hardware testing, feature development, mesh testing

**Command**:
```bash
./lime build --mode development [target]
```

### Release Mode (`LIME_BUILD_MODE=release`)

**Purpose**: Stable production builds
- **lime-app source**: `github.com/libremesh/lime-app` (official upstream)
- **lime-packages**: `github.com/libremesh/lime-packages.git;master`
- **Version**: Stable releases (v0.2.25)
- **Use case**: Production deployment, official releases

**Command**:
```bash
./lime build --mode release [target]
```

## Implementation Details

### Feed Configuration Logic

**File**: `repos/librerouteros/librerouteros_build.sh:48-65`

```bash
case "${LIME_BUILD_MODE:-development}" in
    development)
        # Development mode: Use experimental packages for rapid iteration
        lo:define_default_value LIBREMESH_FEED "${LIBREMESH_FEED:-src-git libremesh https://github.com/javierbrk/lime-packages.git;final-release}"
        librerouteros:dbg "Using development feed: javierbrk/lime-packages"
        ;;
    release)
        # Release mode: Use stable upstream packages
        lo:define_default_value LIBREMESH_FEED "${LIBREMESH_FEED:-src-git libremesh https://github.com/libremesh/lime-packages.git;master}"
        librerouteros:dbg "Using release feed: libremesh/lime-packages"
        ;;
    *)
        # Unknown mode: default to development with warning
        librerouteros:dbg "Unknown LIME_BUILD_MODE: ${LIME_BUILD_MODE}, defaulting to development"
        lo:define_default_value LIBREMESH_FEED "${LIBREMESH_FEED:-src-git libremesh https://github.com/javierbrk/lime-packages.git;final-release}"
        ;;
esac
```

### Environment Variable Precedence

1. **Explicit LIBREMESH_FEED**: If set, overrides mode-based selection
2. **LIME_BUILD_MODE**: Controls default feed selection
3. **Fallback**: Defaults to development mode if neither is set

## Upstream Compatibility

### Non-Disruptive Design

- **Feed overlay system**: Changes remain local to lime-dev environment
- **LibreRouterOS compatibility**: Core build logic unchanged, only feed configuration modified  
- **Upstream synchronization**: `tools/upstream/setup-aliases.sh` workflow preserved
- **CI/CD preservation**: Both repositories maintain independent CI systems

### Repository Relationships

- **lime-packages**: Personal fork (`Fede654/lime-packages`) with experimental features
- **librerouteros**: Official GitLab repository with stable integration
- **lime-app**: Upstream tracking with development fork for rapid iteration

## Usage Examples

### Development Workflow

```bash
# Start development build with latest features
./lime build --mode development ath79-generic

# For lime-app iteration (if needed)
cd repos/lime-app
npm run build:production
cp -r build/* ../lime-packages/packages/lime-app/files/www/app/
```

### Release Workflow

```bash
# Build stable release version
./lime build --mode release librerouter-v1

# Verify stable upstream packages are used
grep "libremesh.git" logs/build.log
```

### Mode Verification

```bash
# Check current mode
echo $LIME_BUILD_MODE

# Verify feed selection in build logs
tail -f logs/build.log | grep "Using.*feed"
```

## Build Mode Validation System

### Pre-Build Configuration Validation

To prevent expensive failed builds due to configuration issues, the system includes automated validation:

```bash
# Validation is automatically run before builds when using --mode
./lime build --mode development librerouter-v1

# Manual validation (useful for CI/CD)
./scripts/utils/validate-build-mode.sh development
```

### Validation Test Suite

The validation system checks:

1. **Environment Variable Injection**
   - All required variables are set
   - Build mode matches request
   - Feed configuration is correct for mode

2. **Package Source Resolution**
   - Package sources are properly defined
   - Mode-specific sources exist or fallback to production

3. **Makefile Patching Validation**
   - Development packages use local repositories
   - Release packages use original configuration
   - Patch application is successful

4. **Feed Consistency**
   - feeds.conf matches expected mode
   - Git repositories point to correct remotes

5. **Complete Flow Integration**
   - End-to-end validation of entire system

### Validation Examples

**Successful Validation**:
```bash
$ ./scripts/utils/validate-build-mode.sh development
[PASS] All tests passed! Build mode development is properly configured.
✅ The complete Source of Truth → Feed Config → Package Makefile Patching → Build flow is working correctly.
```

**Failed Validation**:
```bash
$ ./scripts/utils/validate-build-mode.sh development
[FAIL] lime_app: Not patched for development mode
❌ Build mode configuration issues detected. Check the failed tests above.
```

## Troubleshooting

### Common Issues

1. **Mode not propagating**: Check environment variable export in build scripts
2. **Wrong packages used**: Verify feed configuration in build logs  
3. **Build failures**: Ensure target hardware supports selected package versions
4. **Validation failures**: Run `./scripts/utils/validate-build-mode.sh <mode>` for detailed diagnosis

### Debug Commands

```bash
# Comprehensive build mode validation
./scripts/utils/validate-build-mode.sh development

# Check environment generation
QUIET=false scripts/utils/versions-parser.sh environment development

# Test package source injection
./scripts/utils/package-source-injector.sh test development

# Verify feed configuration
grep LIBREMESH_FEED repos/librerouteros/librerouteros_build.sh

# Check build mode propagation
./lime build --mode development --dry-run
```

### Cost-Saving Benefits

The validation system prevents expensive build failures by:
- **Early Detection**: Catches configuration issues before CPU-intensive compilation
- **Configuration Verification**: Ensures all components use correct sources
- **Integration Testing**: Validates the complete source-to-build pipeline
- **CI/CD Integration**: Can be used in automated pipelines for pre-build checks

## Future Maintenance

### When Upstream Changes

1. **New lime-app releases**: Update version references in appropriate Makefiles
2. **Package source changes**: Modify feed URLs in build script
3. **New build modes**: Extend case statement in `librerouteros_build.sh`

### Testing Changes

1. **Mode switching**: Verify both development and release modes work
2. **Feed selection**: Check correct repositories are used for each mode
3. **Build success**: Ensure targets build successfully in both modes
4. **Upstream sync**: Verify contribution workflow remains functional

## Technical Debt Resolution

This mechanism resolves the following technical debt:

- ✅ **BUILD_MODE disconnection**: Now fully integrated throughout build chain
- ✅ **Makefile duplication**: Single control point selects appropriate sources  
- ✅ **Documentation errors**: Corrected npm script references
- ✅ **Configuration inconsistency**: Unified source of truth via `versions-parser.sh`
- ✅ **Development iteration friction**: No CI/CD required for development builds

The system maintains architectural clarity while providing practical development velocity improvements.