# LibreMesh Hierarchical Configuration System

## Overview

LibreMesh implements a sophisticated hierarchical configuration management system that enables flexible mesh network deployments. This system automatically merges multiple configuration files during boot time, providing a clear priority-based override mechanism for network-wide, device-specific, and node-specific settings.

## Configuration Files and Priority

The system processes four configuration files in strict priority order (highest to lowest):

### 1. `/etc/config/lime-node` 🔴 **HIGHEST PRIORITY**
- **Purpose**: Node-specific configurations and local customizations
- **Scope**: Single device only
- **Use Cases**:
  - Interface-specific configurations (`config net eth0`)
  - Local admin overrides
  - Device-specific network settings
  - Custom firewall rules for specific nodes
  - Hardware-specific optimizations

**Example**:
```uci
config generic main
    option hostname 'node-gateway-01'
    option anygw_mac '02:ca:ff:ee:ba:be'

config net eth0
    option proto 'dhcp'
    option auto '1'
```

### 2. `/etc/config/lime-MAC_ADDRESS` 🟡 **SECOND PRIORITY**
- **Purpose**: MAC address-specific device configurations  
- **Scope**: Specific hardware device (e.g., `lime-000011223344`)
- **Use Cases**:
  - Hardware-specific settings based on MAC address
  - Automatic device identification and configuration
  - Factory-preset device configurations
  - Model-specific optimizations

**Example filename**: `/etc/config/lime-001a2b3c4d5e`

### 3. `/etc/config/lime-community` 🟠 **THIRD PRIORITY**
- **Purpose**: Community-wide mesh network settings
- **Scope**: All nodes in the mesh community
- **Use Cases**:
  - Mesh network ESSID and encryption
  - IP addressing schemes
  - Routing protocols configuration
  - Community-wide services (captive portal, etc.)
  - Bandwidth management policies

**Important**: Interface-specific configurations (`config net`) are **NOT ALLOWED** in community files and will cause unpredictable behavior.

**Example**:
```uci
config lime system
    option hostname 'LiMe-%M4%M5%M6'
    option domain 'thisnode.info'

config lime network
    option main_ipv4_address '10.13.0.0/16'
    option anygw_dhcp_start '2'
    option anygw_dhcp_limit '0'

config lime wifi radio0
    option modes 'ap adhoc'
    option ap_ssid 'LibreMesh.org'
    option adhoc_ssid 'LiMe'
    option adhoc_bssid 'ca:fe:00:c0:ff:ee'
```

### 4. `/etc/config/lime-defaults` 🟢 **LOWEST PRIORITY**
- **Purpose**: System default configuration provided by LibreMesh
- **Scope**: Global defaults for all LibreMesh installations
- **Use Cases**:
  - Base LibreMesh configuration
  - Fallback values for undefined options
  - Standard protocol configurations
  - Default security settings

**Important**: Should **NOT** be edited by end users or community administrators.

## Configuration Merging Algorithm

### Boot-Time Process

1. **Initialization**: System runs `/etc/uci-defaults/91_lime-config` during first boot
2. **File Discovery**: Scans for all four configuration files
3. **Priority Merging**: Merges files in priority order into `/etc/config/lime-autogen`
4. **Template Processing**: Processes template variables (`%Mn`, `%Nn`, `%H`)
5. **Module Execution**: Applies configurations through LibreMesh modules
6. **UCI Commit**: Commits all changes to system UCI configuration

### Merging Rules

```
Higher Priority File + Lower Priority File = Final Configuration
```

- **Option Override**: If same option exists in multiple files, higher priority wins
- **Section Addition**: Missing sections from lower priority files are added
- **Complete Override**: Higher priority sections completely replace lower priority ones
- **Interface Safety**: Interface-specific configs only allowed in `lime-node`

### Example Merging

**lime-defaults**:
```uci
config lime system
    option hostname 'LiMe-Node'
    option domain 'lan'

config lime wifi radio0
    option modes 'ap'
    option channel '11'
```

**lime-community**:
```uci
config lime system
    option domain 'mesh.local'

config lime wifi radio0
    option ap_ssid 'CommunityMesh'
    option channel '6'
```

**lime-node**:
```uci
config lime system
    option hostname 'gateway-node-01'

config net eth0
    option proto 'static'
    option ipaddr '192.168.1.1'
```

**Final Result (lime-autogen)**:
```uci
config lime system
    option hostname 'gateway-node-01'    # From lime-node (highest priority)
    option domain 'mesh.local'           # From lime-community
    
config lime wifi radio0
    option modes 'ap'                    # From lime-defaults
    option ap_ssid 'CommunityMesh'       # From lime-community
    option channel '6'                   # From lime-community

config net eth0                         # Only from lime-node (interface-specific)
    option proto 'static'
    option ipaddr '192.168.1.1'
```

## Template Variables

The configuration system supports dynamic value substitution:

### Available Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `%M1` to `%M6` | MAC address bytes (hex) | `%M4%M5%M6` → `a1b2c3` |
| `%N1` to `%N6` | Network ID bytes (from ap_ssid hash) | `%N4%N5%N6` → `1a2b3c` |
| `%H` | Hostname | `%H` → `lime-node` |

### Template Examples

```uci
config lime system
    option hostname 'Node-%M4%M5%M6'
    # Result: Node-a1b2c3

config lime wifi radio0
    option ap_ssid 'Mesh-%N4%N5%N6'
    # Result: Mesh-1a2b3c
```

## Implementation Details

### Core Components

| Component | Location | Purpose |
|-----------|----------|---------|
| **Configuration Library** | `/usr/lib/lua/lime/config.lua` | Core merging logic |
| **Configuration Binary** | `/usr/bin/lime-config` | CLI interface |
| **Boot Script** | `/etc/uci-defaults/91_lime-config` | First boot execution |
| **Template Files** | `/usr/share/lime/defaults/` | Default templates |

### Key Functions

```lua
-- Main configuration generation
config.uci_autogen()

-- Merge two UCI files
config.uci_merge_files(source, target, result)

-- Get configuration file path
config.get_config_path()

-- Template variable substitution
config.substitute_vars(content)
```

### Configuration Constants

```lua
config.UCI_AUTOGEN_NAME = 'lime-autogen'      -- Final merged configuration
config.UCI_NODE_NAME = 'lime-node'            -- Node-specific config
config.UCI_MAC_NAME = 'lime-000000000000'     -- MAC-specific config (dynamic)
config.UCI_COMMUNITY_NAME = 'lime-community'  -- Community config  
config.UCI_DEFAULTS_NAME = 'lime-defaults'    -- System defaults
```

## Best Practices

### For Community Administrators

1. **Use lime-community for network-wide settings**:
   ```uci
   config lime network
       option main_ipv4_address '10.13.0.0/16'
       
   config lime wifi radio0
       option ap_ssid 'CommunityMesh'
   ```

2. **Avoid interface-specific configurations in lime-community**:
   ```uci
   # ❌ DON'T DO THIS in lime-community
   config net eth0
       option proto 'dhcp'
   ```

3. **Use template variables for consistency**:
   ```uci
   config lime system
       option hostname 'Community-%M4%M5%M6'
   ```

### For Node Administrators

1. **Override community settings when needed**:
   ```uci
   # In lime-node
   config lime system
       option hostname 'custom-gateway-node'
   ```

2. **Add interface-specific configurations**:
   ```uci
   # Only allowed in lime-node
   config net eth1
       option proto 'static'
       option ipaddr '192.168.100.1'
   ```

3. **Preserve community compatibility**:
   - Don't override essential mesh settings unless necessary
   - Document local customizations
   - Test connectivity with other community nodes

### For Developers

1. **Respect the hierarchy**:
   - Default values go in `lime-defaults`
   - Community templates in `lime-community` 
   - Node-specific overrides in `lime-node`

2. **Use configuration modules**:
   ```lua
   -- Create a new configuration module
   local config = require('lime.config')
   local wireless = require('lime.modules.wireless')
   
   function mymodule.configure(args)
       local uci = config.get_uci_cursor()
       -- Configure based on merged settings
   end
   ```

3. **Test merging behavior**:
   ```bash
   # Regenerate configuration
   lime-config
   
   # Check merged result
   uci show lime-autogen
   ```

## Integration with First Boot Wizard

The hierarchical configuration system integrates with the **First Boot Wizard** for seamless community onboarding:

### Community Distribution Process

1. **Discovery**: New node searches for existing mesh nodes
2. **Download**: Retrieves `lime-community` configuration from neighbors
3. **Integration**: Merges downloaded community config with local settings
4. **Validation**: Ensures configuration compatibility and safety
5. **Application**: Applies merged configuration and restarts services

### Automatic Configuration Sharing

```bash
# Community configuration is automatically shared via:
/usr/lib/lua/lime/network.lua          # Network discovery
/usr/lib/lua/lime/firstbootwizard.lua  # Configuration download
```

## Configuration Validation

### Safety Checks

The system includes several validation mechanisms:

1. **Interface Validation**: Prevents interface configs in community files
2. **Syntax Checking**: Validates UCI syntax before applying
3. **Dependency Verification**: Ensures required packages are installed
4. **Network Compatibility**: Checks for conflicting network settings

### Error Handling

```bash
# Check configuration validity
lime-config --test

# View configuration errors
logread | grep lime-config

# Reset to defaults if needed
lime-config --reset
```

## Troubleshooting

### Common Issues

1. **Configuration Not Applied**:
   ```bash
   # Regenerate configuration
   lime-config
   
   # Check for errors
   logread | grep lime
   ```

2. **Interface Configuration Ignored**:
   - Ensure interface configs are only in `lime-node`
   - Check for syntax errors in UCI files

3. **Community Settings Override Local**:
   - Add overrides to `lime-node` (higher priority)
   - Verify file precedence order

4. **Template Variables Not Substituted**:
   ```bash
   # Check MAC address detection
   ip link show | grep ether
   
   # Verify template processing
   uci show lime-autogen | grep '%'
   ```

### Debugging Commands

```bash
# Show final merged configuration
uci show lime-autogen

# List all configuration files
ls -la /etc/config/lime-*

# View configuration merge process
lime-config --debug

# Check system configuration modules
ls /usr/lib/lua/lime/modules/

# View boot logs
logread | grep uci-defaults
```

## Advanced Usage

### Custom Configuration Modules

Create custom modules to extend the configuration system:

```lua
-- /usr/lib/lua/lime/modules/custom.lua
local config = require('lime.config')
local custom = {}

function custom.configure(args)
    local uci = config.get_uci_cursor()
    
    -- Read from merged configuration
    local hostname = uci:get('lime-autogen', 'system', 'hostname')
    
    -- Apply custom logic
    if hostname:match('^gateway%-') then
        -- Configure gateway-specific settings
        uci:set('network', 'wan', 'proto', 'dhcp')
    end
    
    uci:save('network')
end

function custom.setup_interface(args)
    -- Interface-specific configuration
end

return custom
```

### Configuration Export/Import

```bash
# Export community configuration
tar -czf community-config.tar.gz /etc/config/lime-community

# Import on new node
tar -xzf community-config.tar.gz -C /
lime-config
```

### Remote Configuration Management

```bash
# Update community configuration via SSH
scp lime-community root@node-ip:/etc/config/
ssh root@node-ip "lime-config && /etc/init.d/network restart"
```

## Security Considerations

### Configuration Security

1. **File Permissions**: Configuration files should be readable by root only
2. **Validation**: Always validate configurations before applying
3. **Backup**: Keep backups of working configurations
4. **Audit**: Monitor configuration changes in production networks

### Network Security

1. **Encryption**: Use proper wireless encryption in community configs
2. **Access Control**: Implement appropriate firewall rules
3. **Authentication**: Configure secure administrative access
4. **Monitoring**: Log configuration changes and network access

## References

### Documentation
- LibreMesh Configuration Guide: `/www/docs/lime-example.txt`
- UCI Configuration System: [OpenWrt UCI Documentation](https://openwrt.org/docs/guide-user/base-system/uci)
- LibreMesh Architecture: `docs/libremesh/ARCHITECTURE.md`

### Source Code
- Configuration Library: `repos/lime-packages/packages/lime-system/files/usr/lib/lua/lime/config.lua`
- Boot Scripts: `repos/lime-packages/packages/lime-system/files/etc/uci-defaults/`
- Configuration Modules: `repos/lime-packages/packages/lime-system/files/usr/lib/lua/lime/modules/`

### Community Resources
- LibreMesh Website: https://libremesh.org
- Documentation Wiki: https://libremesh.org/docs
- Community Forum: https://lists.libremesh.org
- IRC Channel: #libremesh on OFTC