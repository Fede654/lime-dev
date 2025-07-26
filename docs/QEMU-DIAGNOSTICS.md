# QEMU LibreMesh Diagnostic System

## Overview

The QEMU diagnostic system provides comprehensive testing and validation for LibreMesh/LibreRouterOS images running in QEMU virtual machines. This tool was developed from extensive real-world debugging sessions to identify common issues with development and production images.

## Quick Start

```bash
# Basic diagnostics (automatic with qemu start)
./tools/qemu/diagnose

# Verbose output with detailed analysis
./tools/qemu/diagnose --verbose

# JSON output for automation
./tools/qemu/diagnose --json

# Custom VM IP
./tools/qemu/diagnose --vm-ip 192.168.1.1
```

## Features

### Automated Testing
- **Network Connectivity**: Ping tests and port scanning
- **Service Availability**: SSH, HTTP, HTTPS port checks  
- **Console Access**: Screen session validation
- **System Information**: OS version, uptime, kernel info
- **Package Validation**: uhttpd, ubus, LuCI package detection
- **Web Interface**: HTTP response and content validation
- **Content Verification**: /www/ directory and lime-app presence

### Integration
- **Automatic Execution**: Runs after successful QEMU startup
- **Exit Codes**: Clear status indication for automation
- **Multiple Formats**: Text reports and JSON output
- **Error Classification**: Critical, partial, and warning levels

## Exit Codes

| Code | Status | Description |
|------|--------|-------------|
| 0 | FULLY_FUNCTIONAL | All tests passed, image ready for use |
| 1 | CRITICAL_FAILURE | System unusable, major issues detected |
| 2 | PARTIAL_FUNCTIONALITY | Some services missing but system functional |
| 3 | NETWORK_FAILURE | Network connectivity issues |
| 4 | SCRIPT_ERROR | Diagnostic script execution problems |

## Test Categories

### Critical Tests (Must Pass)
- Network ping connectivity
- Console access via screen
- Basic system information gathering

### Important Tests (Warnings if Failed)
- uhttpd binary presence
- HTTP port (80) availability  
- Web interface functionality

### Optional Tests (Informational)
- HTTPS port availability
- SSH service status
- lime-app specific content
- LuCI package installation

## Real-World Use Cases

### Development Image Validation
```bash
# Test a development build
lime qemu start
# Select development image (e.g., ca63283)
# Diagnostic automatically runs and reports:
# ⚠️ Image diagnostics: PARTIAL - Some services missing
```

**Common Development Image Issues:**
- Missing uhttpd package → No web interface
- Missing ubus service → Limited functionality  
- Missing LuCI components → No admin interface
- Incomplete package sets → Reduced features

### Production Image Verification
```bash
# Test stable release
lime qemu start  
# Select stable image (e.g., 2024.1)
# Diagnostic reports:
# ✅ Image diagnostics: PASSED - Fully functional
```

**Expected Production Results:**
- All services running correctly
- Web interface accessible on port 80
- Complete package installation
- lime-app and LuCI available

### CI/CD Integration
```bash
#!/bin/bash
# Automated testing pipeline
./tools/qemu/qemu-diagnostics.sh --json > results.json
exit_code=$?

case $exit_code in
    0) echo "✅ Image ready for release" ;;
    2) echo "⚠️ Image functional but incomplete" ;;
    *) echo "❌ Image failed validation" ;;
esac

exit $exit_code
```

## Diagnostic Output Examples

### Successful Image (Exit Code 0)
```
QEMU LibreMesh Diagnostic Report
==========================================
VM IP: 10.13.0.1
Overall Status: FULLY_FUNCTIONAL

Test Results:
----------------------------------------
Test                     Result          Details
----------------------------------------
network_ping            PASS            Ping successful
port_http               OPEN            HTTP server responding
port_ssh                OPEN            SSH service available
uhttpd_binary           FOUND           Web server installed
uhttpd_service          RUNNING         Service active
web_interface           PASS            LuCI interface active
lime_app               PASS            lime-app accessible
```

### Development Image Issues (Exit Code 2)
```
QEMU LibreMesh Diagnostic Report
==========================================
VM IP: 10.13.0.1
Overall Status: PARTIAL_FUNCTIONALITY

Test Results:
----------------------------------------
Test                     Result          Details
----------------------------------------
network_ping            PASS            Ping successful
port_http               CLOSED          HTTP port not responding
uhttpd_binary           NOT_FOUND       uhttpd package missing
ubus_available          NO              ubus service unavailable
web_interface           FAIL            No web server running

Recommendations:
----------------------------------------
⚠️ Image has partial functionality. Web services missing.
   - uhttpd web server may not be installed
   - Consider using a stable/recommended image
   - For development: install missing packages manually
```

### Network Failure (Exit Code 3)
```
QEMU LibreMesh Diagnostic Report
==========================================
VM IP: 10.13.0.1
Overall Status: NETWORK_FAILURE

Recommendations:
----------------------------------------
❌ Network connectivity failed. Check QEMU network configuration.
   - Verify TAP interfaces are up and bridged
   - Check VM network settings  
   - Ensure VM has booted completely
```

## Technical Implementation

### Test Methodology
Based on the extensive debugging session that identified the root cause of web service failures in development images:

1. **Network Layer**: Ping tests verify basic connectivity
2. **Transport Layer**: Port scans detect service availability
3. **Application Layer**: HTTP requests test web functionality
4. **System Layer**: Console commands gather internal state
5. **Package Layer**: Service and binary verification

### Console Integration
The diagnostic system uses the same screen session mechanism as the QEMU manager:
- Sends commands via `screen -X stuff`
- Captures output with `screen -X hardcopy`  
- Parses results for intelligent analysis
- Provides detailed error classification

### Automation Features
- **Non-interactive**: Runs without user input
- **Timeout Protection**: Prevents hanging on unresponsive systems
- **Error Recovery**: Graceful handling of failures
- **Structured Output**: JSON format for automation
- **Exit Codes**: Clear success/failure indication

## Troubleshooting

### Common Issues

**"Screen session not found"**
- QEMU not running or session name mismatch
- Solution: Check `screen -list` and verify QEMU status

**"Network connectivity failed"**  
- TAP interfaces not configured
- Solution: Check `ip link show | grep lime_tap`

**"Console unresponsive"**
- VM boot still in progress or crashed
- Solution: Wait longer or restart QEMU

### Debug Mode
```bash
# Enable verbose logging
./tools/qemu/diagnose --verbose

# Check temporary files
ls /tmp/qemu_diag_*.log

# Manual console access
sudo screen -r libremesh
```

## Integration with lime-dev Workflow

### Automatic Execution
The diagnostic runs automatically after:
```bash
lime qemu start
# ... QEMU boots ...
# 🔍 Running comprehensive image diagnostics...
# ✅ Image diagnostics: PASSED - Fully functional
```

### Manual Execution
```bash
# Quick check
./tools/qemu/diagnose

# Detailed analysis  
./tools/qemu/diagnose --verbose

# For scripts/automation
./tools/qemu/diagnose --json
```

### Development Workflow
1. **Build Image**: `make` or use pre-built images
2. **Start QEMU**: `lime qemu start` 
3. **Auto-Diagnose**: System validates image automatically
4. **Manual Debug**: Use `./tools/qemu/diagnose --verbose` for issues
5. **Fix Issues**: Address missing packages or configuration
6. **Re-test**: Validate fixes with repeated diagnostics

This diagnostic system ensures reliable image validation and provides clear guidance for troubleshooting LibreMesh development and deployment scenarios.