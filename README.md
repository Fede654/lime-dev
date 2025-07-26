# Lime-Dev

A comprehensive development environment for LibreMesh ecosystem projects. Provides firmware build systems, QEMU-based development tools, legacy router support, and automated workflows for LibreMesh, LibreRouterOS, and lime-app development.

## What is Lime-Dev?

Lime-Dev solves common LibreMesh development challenges:

- **Firmware Building**: Native and Docker-based LibreRouterOS compilation
- **LibreRouter v1 Support**: Upgrade utility for LibreRouter v1 devices (pre-1.5 firmware)
- **lime-app Development**: Complete framework for LibreMesh web interface development with QEMU integration
- **Cross-Platform Setup**: Automated environment configuration across Linux distributions
- **Build Automation**: Consistent, reproducible firmware builds with proper dependency management

## Key Features

### 🔧 Firmware Development
- LibreRouterOS build system with Docker support
- Multiple target configurations (x86_64, LibreRouter v1, etc.)
- Automated dependency management and toolchain setup
- Cross-platform build support (Ubuntu, RHEL, Arch Linux)

### 🖥️ QEMU Virtualization
- Virtual LibreMesh routers for lime-app development
- Network simulation with bridge interfaces
- Support for both LibreMesh and LibreRouterOS images
- Development workflow automation

### 🔄 LibreRouter v1 Support
- LibreRouter v1 upgrade utility for safe-upgrade and firmware updates
- Enables web-based firmware upgrades on legacy devices
- Handles SSH legacy algorithms and SCP/SFTP limitations
- Automated backup and verification

### 🛠️ Development Tools
- Unified CLI interface (`./lime`) for all operations
- Environment verification and troubleshooting
- Code analysis and quality checking
- Upstream contribution workflows

## Quick Start

### Complete Environment Setup

```bash
# Clone and setup
git clone <your-lime-dev-repo>
cd lime-dev
./lime setup install

# Verify setup
./lime verify all
```

### Build Firmware

```bash
# Build LibreRouterOS for x86_64 (using configured sources)
./lime build configs/example_config_x86_64

# Build for LibreRouter hardware
./lime build configs/example_config_librerouter

# Build with local development sources
./lime build --local configs/example_config_x86_64

# Docker-based build
./lime build docker librerouter-v1
```

### lime-app Development

```bash
# Start QEMU development environment
./lime qemu start

# Develop and deploy lime-app
cd repos/lime-app
npm install
npm run dev              # Development server
./dev.sh deploy          # Deploy to QEMU router

# Test at: http://10.13.0.1/app/
```

### QEMU Development

```bash
# Start virtual router
./lime qemu start

# Deploy lime-app changes (from repos/lime-app/)
./lime qemu deploy

# Access at http://10.13.0.1/app/
```

### LibreRouter v1 Upgrade Utility

```bash
# Update safe-upgrade on LibreRouter v1 (pre-1.5 firmware)
./lime upgrade thisnode.info

# Complete firmware upgrade
./lime upgrade 10.13.0.1 firmware.bin

# With custom password
./lime upgrade 10.13.0.1 -p mypassword

# After update, use web interface at http://thisnode.info
```

## Project Structure

```
lime-dev/
├── scripts/               # Core automation scripts
│   ├── lime              # Main CLI interface
│   ├── build.sh          # Build management
│   ├── setup.sh          # Environment setup
│   ├── core/             # Core functionality
│   │   └── upgrade-legacy-router.sh  # Legacy router support
│   └── utils/            # Utility scripts
│       └── transfer-legacy-hex.sh    # Hex file transfer
├── repos/                # Managed source repositories
│   ├── librerouteros/    # LibreRouterOS firmware source
│   ├── lime-app/         # LibreMesh web interface
│   ├── lime-packages/    # LibreMesh package collection
│   └── kconfig-utils/    # Kernel configuration utilities
├── configs/              # Build configurations
│   ├── example_config_x86_64         # Virtual machine builds
│   └── example_config_librerouter    # LibreRouter hardware
├── docs/                 # Documentation
│   ├── TROUBLESHOOTING.md           # Common issues and solutions
│   ├── DEVELOPMENT.md               # Development workflows
│   └── ARCHITECTURE.md              # System architecture
├── cache/                # Build cache and temporary files
└── logs/                 # Build logs and debugging output
```

## 📚 Documentation

### lime-dev Development Environment
- **[Development Guide](docs/DEVELOPMENT.md)** - Complete setup and development workflow
- **[Architecture Overview](docs/ARCHITECTURE.md)** - Repository structure and design decisions  
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[QEMU Integration](docs/qemu/)** - Virtual testing environment setup

### LibreMesh Technology  
- **[LibreMesh Developer Docs](docs/libremesh/)** - LibreMesh-specific development guides
- **[Hierarchical Configuration](docs/libremesh/HIERARCHICAL-CONFIGURATION.md)** - Multi-level configuration management system
- **[Package Development](docs/libremesh/)** - Creating and maintaining LibreMesh packages *(planned)*

## Common Workflows

### Firmware Development

```bash
# Setup development environment
./lime setup

# Edit packages in repos/lime-packages/
# Edit firmware in repos/librerouteros/

# Build with local sources for development
./lime build --local configs/example_config_x86_64
./lime qemu start

# Clean build
./lime clean
./lime build --local configs/example_config_x86_64
```

### lime-app Development

```bash
# Start QEMU environment
./lime qemu start

# Edit code in repos/lime-app/src/
# Deploy changes
./lime qemu deploy

# Access development instance
curl http://10.13.0.1/app/

# Stop when done
./lime qemu stop
```

### Legacy Router Management

```bash
# Check router connectivity
ssh -oHostKeyAlgorithms=+ssh-rsa root@thisnode.info

# Update safe-upgrade script
./lime upgrade thisnode.info

# Verify update
ssh -oHostKeyAlgorithms=+ssh-rsa root@thisnode.info 'safe-upgrade show'

# Upgrade firmware via web interface
# Open: http://thisnode.info -> System -> Software -> Upload firmware
```

## System Requirements

### Host System
- **Linux**: Ubuntu 20.04+, RHEL 8+, Arch Linux (recommended)
- **macOS**: Supported with limited QEMU performance
- **Windows**: Via WSL2 (experimental)

### Hardware Requirements
- **CPU**: x86_64 with virtualization support (for QEMU)
- **Memory**: 4GB minimum, 8GB+ recommended
- **Storage**: 20GB+ free space
- **Network**: Internet connection for downloads

### Software Dependencies
- Git
- SSH client and sshpass
- Docker (optional, for containerized builds)
- QEMU (for development environment)
- Standard build tools (automatically installed)

## Advanced Configuration

### Build Customization

```bash
# Custom build jobs
export JOBS=$(nproc)
./lime build configs/example_config_x86_64

# Custom download cache
export DOWNLOAD_DIR=/path/to/cache
./lime build configs/example_config_librerouter

# Local development with verbose output
export V=s
./lime build --local configs/example_config_x86_64

# Force local mode for all packages
export LIME_LOCAL_MODE=true
./lime build configs/example_config_x86_64
```

### QEMU Networking

```bash
# Custom network configuration
export LIME_BRIDGE_IP=10.13.0.2/16
./lime qemu start

# Reset network interfaces
sudo ip link delete lime_br0 2>/dev/null || true
./lime qemu start
```

### Legacy Router Customization

```bash
# Custom SSH password
export ROUTER_PASSWORD=mypassword
./lime upgrade 10.13.0.1

# Custom transfer timeout
export SSH_TIMEOUT=30
./lime upgrade thisnode.info
```

## Troubleshooting

Common issues and solutions are documented in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

### Quick Diagnostics

```bash
# Check environment
./lime verify all

# Check specific components
./lime verify platform
./lime verify qemu
./lime verify repos

# Reset environment
./lime clean
./lime update
```

### Getting Help

```bash
# Main help
./lime --help

# Command-specific help
./lime build --help
./lime qemu --help
./lime upgrade --help

# Verify setup
./lime setup check
```

## Contributing

This repository focuses on development infrastructure and tooling. For LibreMesh core development:

- **LibreMesh packages**: [lime-packages repository](https://github.com/libremesh/lime-packages)
- **Web interface**: [lime-app repository](https://github.com/libremesh/lime-app)
- **Documentation**: [LibreMesh website](https://libremesh.org)

### Development Workflow

1. Set up environment: `./lime setup install`
2. Make changes in `repos/` subdirectories
3. Test with QEMU: `./lime qemu start`
4. Build firmware: `./lime build`
5. Verify changes: `./lime verify all`

## License

This project follows the licensing of its component repositories:
- LibreRouterOS: GPL-2.0
- LibreMesh packages: GPL-3.0
- lime-app: GPL-3.0
- Development scripts: GPL-3.0

## Acknowledgments

- **LibreMesh Community**: For the mesh networking software stack
- **LibreRouter Project**: For the open hardware platform
- **OpenWrt Project**: For the underlying firmware framework