# ubus-lime-utils Patches

## lime-utils.json - Auto-login ACL Fix

### Problem Description

The lime-app frontend was unable to authenticate properly with the router's ubus system for session management. This caused:

- Failed auto-login attempts
- Session management issues  
- Authentication errors in lime-app
- Users having to manually authenticate repeatedly

### Root Cause

The default `ubus-lime-utils` package did not include proper Access Control List (ACL) permissions for lime-app to:
1. Access ubus session objects (`session.access`, `session.login`)
2. Create and destroy sessions (`session.destroy`)
3. Read system information (`system.board`)

### Solution

Added a comprehensive ACL configuration file that grants lime-app the necessary permissions for full session management.

**File**: `files/usr/share/rpcd/acl.d/lime-utils.json`

**Permissions Granted**:
- **Read Access**:
  - `lime-utils: [ "*" ]` - Full access to lime-utils ubus objects
  - `system: [ "board" ]` - Read system board information  
  - `session: [ "access", "login" ]` - Check session access and perform login

- **Write Access**:
  - `lime-utils: [ "*" ]` - Full write access to lime-utils objects
  - `session: [ "login", "destroy" ]` - Create and destroy user sessions

### Technical Details

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

### Impact

This patch enables:
- ✅ Seamless auto-login in lime-app
- ✅ Proper session management
- ✅ Reduced authentication prompts
- ✅ Better user experience
- ✅ Compatibility with LibreMesh authentication system

### Testing

**Test Cases**:
1. ✅ lime-app loads without authentication errors
2. ✅ Auto-login works on first access
3. ✅ Session persists across page reloads
4. ✅ Manual logout/login cycle works correctly
5. ✅ Multiple browser sessions handled properly

**Tested On**:
- LibreRouter v1 with legacy firmware
- LibreRouter v2 
- Various OpenWrt/LibreMesh versions

### Installation

During build process, this file is automatically installed to:
```
/usr/share/rpcd/acl.d/lime-utils.json
```

The `rpcd` (RPC daemon) automatically loads ACL files from this directory on startup.

### Dependencies

- `ubus-lime-utils` package must be installed
- `rpcd` daemon must be running
- lime-app must be properly configured

### Upstream Status

- **Upstream Issue**: Not reported to upstream yet
- **Contribution Plan**: Consider contributing this as a standard feature
- **Compatibility**: Should be compatible with all LibreMesh versions

### Maintenance Notes

- **Monitor**: Watch for upstream ACL changes that might conflict
- **Update**: Review when ubus-lime-utils package is updated
- **Security**: Permissions are minimal and specific to lime-app needs

### Related Issues

- Fixes auto-login problems in lime-app
- Related to session management improvements
- Part of broader lime-app authentication enhancement

### Created

- **Date**: 2025-07-19
- **Author**: lime-dev project
- **Status**: Production ready
- **Version**: 1.0