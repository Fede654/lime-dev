# Business Logic Source of Truth - lime-dev Command System

## Core Business Logic

The `/scripts/lime` command system implements a **two-stage conditional resolution architecture** that ensures consistent source-of-truth across all development workflows:

### **Stage 1: Conditional Block Installation (Infrastructure)**
- **When**: During `lime update` procedure (one-time setup)
- **What**: Replace hardcoded feeds/sources with conditional logic blocks
- **Where**: Makefiles, scripts, configuration files throughout the system
- **Purpose**: Create the infrastructure for dynamic source selection

### **Stage 2: Runtime Conditional Resolution (Business Logic)**
- **When**: During actual execution (build, npm dev, QEMU deployment, etc.)
- **What**: Conditional blocks evaluate `LIME_BUILD_MODE` and select appropriate sources
- **Where**: Deep inside build system, npm scripts, QEMU launch scripts
- **Purpose**: Ensure consistent source selection across all workflows

## Business Logic Principles

### **1. Single Source of Truth**
All source decisions flow from `configs/versions.conf`:
- Repository URLs and branches
- Package-level source specifications  
- Build targets and versions
- Environment-specific overrides

### **2. Mode-Driven Resolution**
Every operation respects `LIME_BUILD_MODE`:
- `development`: Local repositories, experimental branches, rapid iteration
- `release`: Stable upstream sources, tested versions, production builds
- `testing`: Hybrid approach for validation workflows

### **3. Universal Application**
The same conditional logic applies to ALL workflows:
- **Build System**: OpenWrt compilation with correct feeds
- **npm Development**: lime-app using local repositories
- **QEMU Deployment**: Virtual testing with local lime-packages
- **CI/CD Pipelines**: Automated testing with correct sources

### **4. Immutable Resolution**
Same configuration + same mode = same sources, every time:
- Deterministic feed selection
- Reproducible builds across environments
- Consistent development experience

## Command Business Logic

### **`./lime build --mode development`**
**Business Logic**: Build firmware using development sources for rapid iteration
**Resolution Flow**:
1. Load `versions.conf` → Extract development overrides
2. Inject build environment → Set `LIME_BUILD_MODE=development`
3. Apply conditional blocks → Select javierbrk/lime-packages feed
4. Patch package Makefiles → Use local lime-app repository
5. Execute build → All components use development sources

### **`./lime dev`** (npm development)
**Business Logic**: Run lime-app development server using local sources
**Resolution Flow**:
1. Load `versions.conf` → Extract lime-app development path
2. Set development environment → Point to local repository
3. Launch npm dev server → Use local lime-app code
4. Live reload → Changes immediately visible

### **`./lime qemu --mode development`**
**Business Logic**: Launch QEMU with local lime-packages for rapid testing
**Resolution Flow**:
1. Load `versions.conf` → Extract development repositories
2. Build minimal firmware → Use local lime-packages
3. Launch QEMU → Load firmware with development packages
4. Network setup → Connect to development environment

### **`./lime update`**
**Business Logic**: Install/update conditional infrastructure (Stage 1)
**Resolution Flow**:
1. Backup original files → Preserve upstream versions
2. Install conditional blocks → Replace hardcoded sources
3. Validate installation → Ensure conditional logic works
4. Update documentation → Reflect current state

## Testing Business Logic

### **The Core Challenge**
Testing conditional resolution (Stage 2) without expensive execution:
- Need to verify runtime behavior without full builds
- Must capture actual feed resolution logic
- Validate that conditional blocks work correctly
- Ensure configuration immutability

### **Conditional Resolution Testing Strategy**
Test the actual conditional logic that will be executed during builds:

```bash
# Test conditional resolution without building
./scripts/utils/validate-build-mode.sh development

# This tests:
# 1. What feeds would be resolved based on LIME_BUILD_MODE
# 2. What package sources would be selected
# 3. Whether local repositories exist and are accessible
# 4. That same configuration produces identical results (immutability)
```

### **Key Testing Insights**

**Stage 1 vs Stage 2 Testing**:
- ❌ **Wrong**: Test if Makefiles are patched (Stage 1)
- ✅ **Correct**: Test what sources conditional blocks would resolve to (Stage 2)

**Configuration-Driven vs Fixed Expectations**:
- ❌ **Wrong**: Validate against hardcoded expected values
- ✅ **Correct**: Validate that resolved values match `versions.conf` configuration

**Feed Consistency Detection**:
The test correctly detects configuration mismatches:
```bash
$ ./scripts/utils/validate-build-mode.sh development
[FAIL] LibreMesh feed remote mismatch:
[FAIL]   Expected (from config): https://github.com/example/test-packages.git
[FAIL]   Actual (from git): https://github.com/javierbrk/lime-packages.git
```

This catches when:
- Configuration has been changed but build environment not updated
- Build directories have been prepared for different configuration
- Conditional logic is not correctly implementing the configuration

### **Business Logic Immutability**
Same configuration + same mode = identical source resolution:
- Environment variables are deterministic
- Feed selection is predictable  
- Package sources resolve consistently
- No time-dependent or random elements

## Implementation Patterns

### **Conditional Block Pattern**
Replace hardcoded values with mode-aware conditionals:

**Before (Hardcoded)**:
```bash
LIBREMESH_FEED="src-git libremesh https://github.com/libremesh/lime-packages.git;master"
```

**After (Conditional)**:
```bash
case "${LIME_BUILD_MODE:-development}" in
    development)
        LIBREMESH_FEED="src-git libremesh https://github.com/javierbrk/lime-packages.git;final-release"
        ;;
    release)
        LIBREMESH_FEED="src-git libremesh https://github.com/libremesh/lime-packages.git;master"
        ;;
esac
```

### **Package Source Injection Pattern**
Replace package Makefile variables with development sources:

**Before (Production)**:
```makefile
PKG_SOURCE_URL:=https://github.com/Fede654/lime-app/releases/download/$(PKG_VERSION)
```

**After (Development)**:
```makefile
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=file:///home/fede/REPOS/lime-dev/repos/lime-app
PKG_SOURCE_VERSION:=HEAD
```

## Critical Business Rules

### **Rule 1: No Hardcoded Sources**
Any hardcoded source is a violation of business logic:
- All sources must be configurable via `versions.conf`
- All workflows must respect `LIME_BUILD_MODE`
- No exceptions for "convenience" or "speed"

### **Rule 2: Stage 1/Stage 2 Separation**
Clear separation between infrastructure and resolution:
- Stage 1: One-time conditional block installation
- Stage 2: Runtime mode-based resolution
- Never mix the two stages

### **Rule 3: Universal Mode Respect**
Every script, Makefile, and workflow must:
- Check `LIME_BUILD_MODE` environment variable
- Implement appropriate conditional logic
- Default to development mode if unset

### **Rule 4: Testing Without Execution**
All business logic must be testable without expensive operations:
- Dry-run capabilities for all major workflows  
- Source resolution verification
- Configuration validation before execution

## Business Logic Evolution

### **Current State**
- Build system: ✅ Conditional blocks implemented
- Package injection: ✅ Runtime resolution working
- npm development: ❌ Still hardcoded
- QEMU deployment: ❌ Still hardcoded

### **Next Implementation Priority**
1. npm development workflow conditional logic
2. QEMU deployment mode-aware source selection  
3. CI/CD pipeline integration
4. Documentation workflow automation

### **Long-term Vision**
Every aspect of lime-dev development controlled by single source of truth:
- One configuration file controls all workflows
- Mode changes propagate to all systems instantly
- Developers can switch contexts without manual reconfiguration
- Testing and production environments are deterministically different

## Command Implementation Guide

When implementing new `/scripts/lime` commands, follow this pattern:

1. **Document Business Logic First**: What should this command accomplish?
2. **Identify Source Dependencies**: What repositories/packages does it need?
3. **Design Conditional Logic**: How should it behave in different modes?
4. **Implement Dry-Run**: How can we test without expensive execution?
5. **Add to versions.conf**: What configuration does it need?
6. **Write Tests**: Verify conditional resolution works correctly

The code is easy to change, but the business logic defines the architecture. Get the logic right first, then implement it faithfully.