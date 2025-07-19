# Legacy Support Resources

This directory contains resources specifically for supporting legacy LibreRouter v1 devices that require special handling due to outdated firmware versions.

## safe-upgrade Scripts

### Files in This Directory

1. **`safe-upgrade`** - Main script with documentation header (used by upgrade process)
2. **`safe-upgrade.original`** - Pristine copy from upstream (for reference/verification)

### Purpose
These scripts are local copies maintained specifically for LibreRouter v1 legacy device support. This ensures compatibility with older firmware and prevents potential issues from upstream changes.

### Source Information
- **Original URL**: https://raw.githubusercontent.com/libremesh/lime-packages/refs/heads/master/packages/safe-upgrade/files/usr/sbin/safe-upgrade
- **Repository**: https://github.com/libremesh/lime-packages
- **Path**: `packages/safe-upgrade/files/usr/sbin/safe-upgrade`
- **Branch**: `master`

### Version Details

#### Original Upstream Version
- **SHA256 Hash**: `18e5c0bba3119366101a6f246201f4c3e220c96712a122fa05a7e25cad2c7cbd`
- **File Size**: 17,642 bytes
- **File**: `safe-upgrade.original`

#### Documentation-Enhanced Version (Used by Scripts)
- **SHA256 Hash**: `309149758a17b8f90454550478de5d20510e7984742d899549a9c1c36cae539b`
- **File Size**: 18,338 bytes (includes documentation header)
- **File**: `safe-upgrade`
- **Downloaded**: 2025-07-19
- **Known Working Version**: Verified to work with LibreRouter v1 legacy devices

### Why Local Copy?

1. **Stability**: Legacy devices require a stable, tested version of safe-upgrade
2. **Compatibility**: Ensures the upgrade process works with pre-1.5 firmware versions
3. **Reliability**: Avoids potential network issues when downloading from upstream
4. **Version Control**: Maintains a known-good version that has been tested with legacy hardware

### Usage

The `upgrade-legacy-router.sh` script automatically uses this local copy instead of downloading from upstream. The script:

1. Verifies the local file integrity using SHA256 hash
2. Copies the verified script to the cache directory
3. Uploads it to the legacy router via HTTP or hex transfer
4. Installs it as `/usr/sbin/safe-upgrade` on the router

### Updating

If the upstream safe-upgrade script receives important updates that need to be included for legacy support:

1. Download the new version from the original URL
2. Test thoroughly with legacy LibreRouter v1 devices  
3. Update the SHA256 hash in `upgrade-legacy-router.sh`
4. Update the documentation header in the local `safe-upgrade` file
5. Update this README with the new version information

### Historical Context

LibreRouter v1 devices with firmware older than v1.5 had several limitations:
- Outdated SSH algorithms requiring `-oHostKeyAlgorithms=+ssh-rsa`
- Limited transfer capabilities requiring special hex encoding for large files
- Incompatible safe-upgrade scripts that couldn't handle the dual-boot system properly

This local copy of safe-upgrade resolves these issues and enables reliable firmware upgrades for legacy hardware.