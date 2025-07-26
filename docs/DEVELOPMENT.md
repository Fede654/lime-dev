# LibreMesh Development Workflow

## Quick Start

```bash
# Setup complete environment
./lime setup

# Build LibreRouterOS firmware (using configured sources)
./lime build configs/example_config_librerouter

# Build with local development sources
./lime build --local configs/example_config_librerouter

# Start QEMU development environment
./lime qemu start

# Update legacy router safe-upgrade
./lime upgrade thisnode.info
```

## Development Workflows

### Firmware Development

1. **Environment Setup** (once)
   ```bash
   # Complete setup
   ./lime setup
   
   # Setup for build-remote-only (tagged releases)
   ./lime setup --build-remote-only
   
   # Verify environment
   ./lime verify all
   ```

2. **Edit Source Code**
   ```bash
   # LibreRouterOS packages
   cd repos/lime-packages/
   # Edit packages/package-name/
   
   # LibreRouterOS firmware
   cd repos/librerouteros/
   # Edit target/linux/ or package/
   ```

3. **Build and Test**
   ```bash
   # Build firmware with local sources (development)
   ./lime build --local configs/example_config_x86_64
   
   # Build firmware with configured sources (production)
   ./lime build configs/example_config_x86_64
   
   # Test in QEMU
   ./lime qemu start
   
   # Clean build if needed
   ./lime clean
   ```

### lime-app Development

1. **Start Development Environment**
   ```bash
   # Start virtual router
   ./lime qemu start
   ```

2. **Edit and Deploy**
   ```bash
   # Edit lime-app source
   cd repos/lime-app/src/
   # Make changes to components/
   
   # Deploy changes to QEMU
   ./lime qemu deploy
   ```

3. **Test Changes**
   ```bash
   # Access development instance
   curl http://10.13.0.1/app/
   
   # Or open in browser: http://10.13.0.1/app/
   ```

4. **Stop Environment**
   ```bash
   ./lime qemu stop
   ```

### Legacy Router Support

1. **Update safe-upgrade Script**
   ```bash
   # Interactive update (prompts for password)
   ./lime upgrade thisnode.info
   
   # With password option
   ./lime upgrade 10.13.0.1 -p mypassword
   
   # Using environment variable
   ROUTER_PASSWORD=mypass ./lime upgrade thisnode.info
   ```

2. **Complete Firmware Upgrade Automation**
   ```bash
   # Download firmware from: https://downloads.libremesh.org/
   # Look for: librerouter-v1-xxx-sysupgrade.bin
   
   # Reliable method (30+ minutes, always works)
   ./lime upgrade-complete thisnode.info firmware.bin
   
   # Fast method (30 seconds, experimental)  
   ./lime upgrade-complete thisnode.info firmware.bin --fast
   
   # With auto-confirmation (dangerous)
   ./lime upgrade-complete thisnode.info firmware.bin --auto-confirm
   ```

3. **Verify Update**
   ```bash
   # Check router status
   ssh -oHostKeyAlgorithms=+ssh-rsa root@thisnode.info 'safe-upgrade show'
   ```

4. **Upgrade Firmware via Web Interface** (Recommended)
   ```bash
   # Open web interface
   # http://thisnode.info -> System -> Software -> Upload firmware
   
   # This is the fastest and most reliable method
   ```

## Build System

### Native Builds

```bash
# Build for different targets (using configured sources)
./lime build configs/example_config_x86_64         # Virtual machines
./lime build configs/example_config_librerouter    # LibreRouter hardware

# Build with local development sources
./lime build --local configs/example_config_x86_64
./lime build --local configs/example_config_librerouter

# Custom build options
export JOBS=$(nproc)                                # Use all CPU cores
export V=s                                          # Verbose output
./lime build --local configs/example_config_x86_64
```

### Docker Builds

```bash
# Docker-based builds (more consistent)
./lime build docker librerouter-v1
./lime build docker x86_64

# Clean Docker environment
docker system prune -a
```

### Build Customization

```bash
# Edit build configuration
cp configs/example_config_x86_64 configs/my_config
vim configs/my_config

# Build with custom config (configured sources)
./lime build configs/my_config

# Build with custom config (local sources)
./lime build --local configs/my_config
```

## QEMU Development

### Virtual Router Management

```bash
# Start virtual router
./lime qemu start

# Check status
./lime qemu status

# Stop virtual router
./lime qemu stop

# Development cycle (for lime-app)
./lime qemu dev-cycle
```

### Network Configuration

```bash
# Default network
# Router: 10.13.0.1
# Host bridge: 10.13.0.2

# Custom network (if needed)
export LIME_BRIDGE_IP=10.13.0.2/16
./lime qemu start

# Reset network interfaces
sudo ip link delete lime_br0 2>/dev/null || true
./lime qemu start
```

### Image Management

```bash
# Images are stored in: repos/lime-packages/build/
# Supported: LibreMesh and LibreRouterOS images
# Auto-detection based on available images
```

## Environment Management

### Verification and Troubleshooting

```bash
# Check complete environment
./lime verify all

# Check specific components
./lime verify platform    # Platform-specific checks
./lime verify qemu        # QEMU environment
./lime verify repos       # Repository integrity

# Reset environment
./lime clean              # Clean build artifacts
./lime update            # Update repositories (alias for 'lime setup update')
```

### Dependency Management

```bash
# Check dependencies
./lime setup check

# Install missing dependencies
./lime setup

# Install for build-remote-only mode
./lime setup --build-remote-only

# Platform-specific installation
# Ubuntu/Debian: apt-get
# RHEL/CentOS/Fedora: yum/dnf
# Arch Linux: pacman
```

### Repository Management

```bash
# Update all repositories (alias for 'lime setup update')
./lime update

# Manual repository updates
cd repos/lime-packages && git pull
cd repos/librerouteros && git pull
cd repos/lime-app && git pull
```

## Debugging and Troubleshooting

### Build Issues

```bash
# Verbose build output
export V=s
./lime build configs/example_config_x86_64

# Check logs
ls logs/

# Clean and rebuild
./lime clean
./lime build configs/example_config_x86_64
```

### QEMU Issues

```bash
# Check KVM availability
kvm-ok

# Verify user groups
groups | grep kvm

# Check network interfaces
ip addr show lime_br0
ip addr show | grep lime_tap

# Reset QEMU environment
sudo ip link delete lime_br0 2>/dev/null || true
./lime qemu start
```

### Legacy Router Issues

```bash
# Test SSH connectivity
ssh -oHostKeyAlgorithms=+ssh-rsa root@thisnode.info

# Check password (default: toorlibre1)
ROUTER_PASSWORD=toorlibre1 ./lime upgrade thisnode.info

# Debug transfer issues
./scripts/transfer-legacy-hex.sh thisnode.info /tmp/test.txt
```

## Advanced Development

### Custom Configurations

```bash
# Create custom build configuration
cp configs/example_config_x86_64 configs/my_custom_config
vim configs/my_custom_config

# Edit package selections
# Add: CONFIG_PACKAGE_my-package=y
# Remove: # CONFIG_PACKAGE_unwanted-package is not set

# Build with custom config
./lime build configs/my_custom_config
```

### Multi-Target Development

```bash
# Build for multiple targets
./lime build configs/example_config_x86_64
./lime build configs/example_config_librerouter

# Test x86_64 in QEMU
./lime qemu start

# Flash LibreRouter hardware with generated firmware
# Output: cache/openwrt-ath79-generic-librerouter-v1-squashfs-sysupgrade.bin
```

### Performance Optimization

```bash
# Parallel builds
export JOBS=$(nproc)

# Build cache
export DOWNLOAD_DIR=/path/to/cache

# Memory optimization
# Ensure 8GB+ RAM for large builds
# Ensure 20GB+ disk space
```

## Integration with Upstream

### Contributing to LibreMesh

```bash
# Make changes in repos/lime-packages/
cd repos/lime-packages
git checkout -b my-feature-branch

# Edit packages/my-package/
# Test changes with local sources
cd ../../
./lime build --local configs/example_config_x86_64
./lime qemu start

# Commit and push
cd repos/lime-packages
git add .
git commit -m "Add new feature"
git push origin my-feature-branch

# Create pull request on GitHub
```

### lime-app Development

```bash
# lime-app development workflow
cd repos/lime-app
git checkout -b my-ui-feature

# Start development environment
cd ../../
./lime qemu start

# Edit UI components
cd repos/lime-app/src/
# Make changes

# Deploy and test
cd ../../
./lime qemu deploy

# Test at http://10.13.0.1/app/
```

## Best Practices

### Development Workflow

1. Always verify environment: `./lime verify all`
2. Use QEMU for testing: `./lime qemu start`
3. Clean builds when in doubt: `./lime clean`
4. Update repositories regularly: `./lime update`
5. Test on multiple targets when possible

### Code Quality

1. Follow existing code conventions
2. Test changes thoroughly in QEMU
3. Verify builds on clean environment
4. Document new features and changes

### Legacy Router Support

1. Test on actual hardware when possible
2. Use default password `toorlibre1` for consistency  
3. Verify web interface functionality after updates
4. Create backups before making changes

### Performance

1. Use parallel builds: `export JOBS=$(nproc)`
2. Use build cache for repeated builds
3. Clean environments periodically
4. Monitor disk space and memory usage