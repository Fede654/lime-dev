# BUILD_MODE Mechanism - DEPRECATED

> **⚠️ DEPRECATED**: This document describes the legacy LIME_BUILD_MODE system that has been eliminated.  
> **✅ See instead**: [UNIFIED-BUILD-ARCHITECTURE.md](UNIFIED-BUILD-ARCHITECTURE.md) for the current simplified system.

## Migration Summary

The complex LIME_BUILD_MODE system has been completely replaced with a simplified unified architecture:

### Before (Legacy - DEPRECATED)
```bash
./lime build --mode development [target]  # ❌ Removed
./lime build --mode release [target]      # ❌ Removed
```

### After (Unified - CURRENT)
```bash
./lime build [target]                     # ✅ Default mode (configured sources)
./lime build --local [target]             # ✅ Local mode (development sources)
```

## Key Changes

- **Eliminated**: Complex LIME_BUILD_MODE switches
- **Simplified**: Two clear modes: default vs local
- **Unified**: Single [sources] configuration section
- **Improved**: Better validation and error handling

## Updated Documentation

Please refer to the current documentation:

- **[Unified Build Architecture](UNIFIED-BUILD-ARCHITECTURE.md)** - Complete system overview
- **[Development Guide](DEVELOPMENT.md)** - Updated development workflows  
- **[Architecture Overview](ARCHITECTURE.md)** - System design and components

## Legacy Content Removed

The following legacy concepts have been eliminated:

- LIME_BUILD_MODE environment variable
- Development vs release mode distinction
- Complex feed configuration switching
- Separate package_sources sections
- Mode-specific validation logic

All functionality has been preserved but simplified under the unified architecture.