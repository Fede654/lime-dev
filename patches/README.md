# LibreMesh Development Patches

This directory contains custom patches and modifications for the LibreMesh ecosystem that are maintained independently of upstream feeds.

## Directory Structure

```
patches/
├── lime-packages/           # Patches for LibreMesh packages
│   └── ubus-lime-utils/     # Specific package patches
├── librerouteros/           # Patches for LibreRouterOS
├── openwrt/                 # Patches for OpenWrt base
└── lime-app/                # Patches for lime-app frontend
```

## Current Patches

### openwrt/

#### openwrt-librerouter-device-compatibility.patch - LibreRouter R2 Sysupgrade Fix
- **Purpose**: Fix sysupgrade device compatibility check for LibreRouter R2
- **Problem**: Device name mismatch causing sysupgrade to require `--force` flag
- **Solution**: Remove manual SUPPORTED_DEVICES override to allow automatic device name conversion
- **File**: `target/linux/ramips/image/mt7621.mk`
- **Created**: 2025-10-17
- **Status**: Production ready

**Technical Details**:

The issue occurred due to a mismatch between how the system identifies itself and what the firmware image accepts:

1. **Device Tree** defines: `compatible = "librerouter,librerouter-r2", "mediatek,mt7621-soc"`
2. **System boot** reads this and generates: `/tmp/sysinfo/board_name` = `librerouter,librerouter-r2`
3. **OpenWRT default behavior**: Automatically converts device name `librerouter_librerouter-r2` → `librerouter,librerouter-r2` (underscore to comma)
4. **Manual override problem**: `SUPPORTED_DEVICES := librerouter-r2` was breaking this conversion

**Root Cause**: The manual `SUPPORTED_DEVICES` override in mt7621.mk was setting the value to `librerouter-r2` instead of using the automatic conversion that produces `librerouter,librerouter-r2`.

**Solution**: Remove the manual override line, allowing OpenWRT's default mechanism (defined in `include/image.mk:516`) to automatically convert underscores to commas, matching the device tree compatible string.

**Result**: After applying this patch and rebuilding the firmware, `sysupgrade` works without requiring the `--force` flag, as the device name matches correctly.

### lime-packages/ubus-lime-utils/

#### lime-utils.json - Auto-login ACL Fix
- **Purpose**: Fixes lime-app auto-login system by providing proper ubus session access
- **Problem**: lime-app couldn't authenticate with ubus for session management
- **Solution**: Added ACL permissions for `session.login`, `session.access`, and `session.destroy`
- **File**: `files/usr/share/rpcd/acl.d/lime-utils.json`
- **Created**: 2025-07-19
- **Status**: Production ready

**Technical Details**:
```json
{
    "lime-app": {
        "description": "lime-app public access with session management",
        "read": {
            "ubus": {
                "lime-utils": [ "*" ],
                "system": [ "board" ],
                "session": [ "access", "login" ]
            }
        },
        "write": {
            "ubus": {
                "lime-utils": [ "*" ],
                "session": [ "login", "destroy" ]
            }
        }
    }
}
```

## Patch Management Workflow

### Adding New Patches

1. **Create patch structure**:
   ```bash
   mkdir -p patches/[package-name]/[subpath]
   ```

2. **Add patch files**:
   ```bash
   cp modified-file patches/[package-name]/[subpath]/
   ```

3. **Document the patch**:
   - Update this README.md
   - Add patch description and rationale
   - Include technical details and testing info

4. **Commit to repository**:
   ```bash
   git add patches/
   git commit -m "feat: Add [patch-name] patch for [purpose]"
   ```

### Applying Patches During Build

Patches in this directory should be automatically applied during the build process. Integration with the build system:

1. **Feed Integration**: Patches override upstream package files
2. **Build Scripts**: Automatically copy patch files to appropriate locations
3. **Verification**: Build system validates patch application

### Updating Patches

When upstream packages change:

1. **Test Compatibility**: Verify patches still apply cleanly
2. **Update if Needed**: Modify patches for upstream changes  
3. **Document Changes**: Update patch documentation
4. **Test Thoroughly**: Ensure functionality still works

## Integration with Build System

### Automatic Patch Application

The lime-dev build system should automatically:

1. **Copy Patch Files**: During feed preparation
2. **Override Upstream**: Replace upstream files with patched versions
3. **Validate Changes**: Ensure patches apply successfully
4. **Log Application**: Record which patches were applied

### Build Script Integration

Add to build scripts:
```bash
# Apply lime-dev patches
if [[ -d "$LIME_BUILD_DIR/patches" ]]; then
    echo "Applying lime-dev patches..."
    rsync -av "$LIME_BUILD_DIR/patches/" "$BUILD_TARGET/"
fi
```

## Patch Categories

### 🔧 **Bug Fixes**
- Critical fixes for upstream issues
- Security patches
- Compatibility fixes

### ✨ **Enhancements** 
- Feature additions
- Performance improvements
- User experience improvements

### 🔗 **Integration Patches**
- Cross-component compatibility
- API adjustments
- Configuration modifications

## Best Practices

1. **Minimal Changes**: Keep patches as small as possible
2. **Clear Documentation**: Document why each patch is needed
3. **Upstream Contribution**: Consider contributing fixes upstream when possible
4. **Testing**: Thoroughly test all patches before committing
5. **Version Tracking**: Track which upstream versions patches apply to

## Related Files

- `configs/versions.conf` - Controls which repositories and versions are used
- `scripts/utils/patch-*.sh` - Patch application scripts
- `build/` - Build output directory (patches applied here)

## Maintenance Notes

- **Review Quarterly**: Check if patches are still needed with upstream updates
- **Upstream Monitoring**: Watch for upstream fixes that might replace our patches
- **Testing Matrix**: Maintain test cases for all patched functionality
- **Documentation**: Keep this README updated with all patches