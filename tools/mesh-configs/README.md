# LibreMesh Mesh Configuration Resources

This directory provides ready-to-deploy mesh network configurations for LibreMesh development, testing, and community deployments. These are standardized configurations that create known-good mesh networks for various use cases.

## Available Mesh Configurations

### 🧪 **TestMesh** (`lime-community-testmesh`)
- **Purpose**: Development and testing environment
- **Network**: TestMesh.org (10.13.0.0/16)
- **Features**: 
  - Dual-band WiFi with WPA2 encryption
  - Multiple routing protocols enabled
  - Development-friendly settings
  - Known WiFi password: `TestMesh2024!`

### 🏘️ **Community Template** *(planned)*
- **Purpose**: Template for real community deployments
- **Features**: Production-ready security, customizable parameters

### 🏢 **Enterprise Demo** *(planned)*  
- **Purpose**: Business/organization demonstrations
- **Features**: Enterprise-grade security, guest networks

### 🎯 **Performance Testing** *(planned)*
- **Purpose**: Network performance benchmarking
- **Features**: Optimized for throughput testing

## Quick Deployment

### Using lime-dev CLI

```bash
# Deploy TestMesh to default router (thisnode.info)
./lime mesh deploy testmesh

# Deploy to specific router
./lime mesh deploy testmesh 10.13.0.1

# Preview deployment without applying
./lime mesh deploy testmesh --dry-run

# Deploy with backup of existing config
./lime mesh deploy testmesh --backup
```

### Direct Script Usage

```bash
# Deploy TestMesh configuration
tools/mesh-configs/deploy-test-mesh.sh

# Deploy to specific router with custom password
ROUTER_PASSWORD=mypass tools/mesh-configs/deploy-test-mesh.sh 10.13.0.1
```

## Development Workflow Integration

### 1. **Setup Test Environment**
```bash
# Quick test mesh setup for development
./lime mesh deploy testmesh

# Start QEMU with test mesh config
./lime qemu start --mesh-config testmesh
```

### 2. **Multi-Node Testing**
```bash
# Deploy same config to multiple routers
./lime mesh deploy testmesh 10.13.0.1
./lime mesh deploy testmesh 10.13.0.2  
./lime mesh deploy testmesh 10.13.0.3

# Verify mesh connectivity
./lime mesh verify 10.13.0.1
```

### 3. **Development Cycle**
```bash
# 1. Setup known-good test environment
./lime mesh deploy testmesh

# 2. Make changes to lime-packages or librerouteros
# 3. Build and test
./lime build && ./lime qemu deploy

# 4. Reset to clean state when needed
./lime mesh deploy testmesh --force
```

## Configuration Structure

### Mesh Configuration Files

Each mesh configuration includes:

```
mesh-name/
├── lime-community           # Community configuration file
├── deploy.sh               # Deployment script  
├── README.md               # Configuration documentation
└── verify.sh               # Network verification script
```

### Configuration Parameters

All configurations follow LibreMesh hierarchical config standards:

- **Community-wide settings**: Shared by all mesh nodes
- **Template variables**: Dynamic hostname/SSID generation
- **Standard security**: WPA2 encryption, secure passwords
- **Multi-protocol**: BATMAN-adv, BMX6/BMX7, Babel support
- **Development-friendly**: Known passwords, logging enabled

## Creating New Mesh Configurations

### 1. **Create Configuration Directory**

```bash
mkdir tools/mesh-configs/your-mesh-name
cd tools/mesh-configs/your-mesh-name
```

### 2. **Create lime-community Configuration**

```uci
config lime 'system'
    option hostname 'YourMesh-%M4%M5%M6'
    option domain 'mesh.local'

config lime 'network'  
    option main_ipv4_address '10.YOUR.0.0/16'

config lime 'wifi' 'radio0'
    option ap_ssid 'YourMesh.org'
    option ap_key 'YourSecurePassword!'
    option ap_encryption 'psk2'
```

### 3. **Create Deployment Script**

```bash
# Copy and customize from existing deployment script
cp ../testmesh/deploy.sh ./deploy.sh
# Edit configuration parameters
```

### 4. **Add to lime CLI**

Add new mesh config to `scripts/lime` in the mesh command handler.

## Integration with lime-dev Tools

### QEMU Integration

```bash
# Start QEMU with specific mesh configuration
./lime qemu start --mesh-config testmesh

# Deploy mesh config to running QEMU instance
./lime qemu apply-mesh testmesh
```

### Build Integration

```bash
# Build firmware with embedded mesh configuration
./lime build --mesh-config testmesh configs/example_config_librerouter

# Include mesh config in firmware image
./lime build --embed-mesh testmesh
```

### Testing Integration

```bash
# Verify mesh network status
./lime mesh status testmesh

# Test mesh connectivity
./lime mesh test testmesh

# Monitor mesh network
./lime mesh monitor testmesh
```

## Mesh Configuration Standards

### Naming Conventions

- **Lowercase**: All mesh names in lowercase
- **Descriptive**: Clear purpose indication
- **Unique**: Avoid conflicts with existing networks

### Network Addressing

- **TestMesh**: `10.13.0.0/16` - Development and testing
- **Community**: `10.14.0.0/16` - Community template
- **Enterprise**: `10.15.0.0/16` - Business demonstrations
- **Performance**: `10.16.0.0/16` - Performance testing

### Security Requirements

- **WPA2 Minimum**: All configurations use WPA2+ encryption
- **Strong Passwords**: Minimum 12 characters, mixed case/numbers
- **Unique BSSIDs**: Each mesh config has unique BSSID
- **Documentation**: Security settings clearly documented

### Protocol Configuration

- **Multi-Protocol**: Support BATMAN-adv, BMX6/BMX7, Babel
- **Optimized Settings**: Protocol parameters tuned for use case
- **Fallback Support**: Graceful degradation if protocols unavailable

## Troubleshooting

### Common Issues

1. **Configuration Deployment Fails**
   ```bash
   # Check SSH connectivity
   ssh root@10.13.0.1
   
   # Verify configuration syntax
   uci -c . import lime-community < lime-community-testmesh
   ```

2. **Mesh Network Not Forming**
   ```bash
   # Check WiFi interfaces
   iwinfo
   
   # Verify routing protocols
   batctl if
   bmx6 -c show=status
   ```

3. **Network Connectivity Issues**
   ```bash
   # Check IP configuration
   ip addr show
   
   # Test mesh routing
   ping 10.13.0.1
   traceroute 10.13.0.1
   ```

### Debugging Commands

```bash
# Show mesh network status
./lime mesh status testmesh

# Export mesh configuration
./lime mesh export testmesh > my-mesh-backup.conf

# Reset mesh configuration
./lime mesh reset testmesh

# Show mesh network topology
./lime mesh topology testmesh
```

## Contributing

### Adding New Configurations

1. **Create configuration** following standards above
2. **Test thoroughly** on real hardware and QEMU
3. **Document use case** and configuration parameters
4. **Add integration** to lime CLI tool
5. **Submit pull request** with configuration and tests

### Improving Existing Configurations

1. **Test changes** on multiple hardware platforms
2. **Maintain backward compatibility** when possible
3. **Update documentation** for any parameter changes
4. **Verify integration** with lime-dev workflow

## References

- **[Hierarchical Configuration](../../docs/libremesh/HIERARCHICAL-CONFIGURATION.md)** - Configuration system details
- **[LibreMesh Documentation](https://libremesh.org/docs)** - Official user guides
- **[lime-dev Development](../../docs/DEVELOPMENT.md)** - Development workflow
- **[Mesh Protocol Documentation](https://libremesh.org/docs/development.html)** - Protocol details