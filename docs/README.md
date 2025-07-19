# lime-dev Documentation

This directory contains comprehensive documentation for the lime-dev umbrella repository and LibreMesh development environment.

## 📁 Documentation Structure

### 🏗️ lime-dev Repository (Umbrella Project)
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - lime-dev repository structure and design decisions
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Development environment setup and workflows  
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Contribution guidelines and standards
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[INFRASTRUCTURE_REPLICATION.md](INFRASTRUCTURE_REPLICATION.md)** - Replicating the development infrastructure
- **[SCRIPT_CONSOLIDATION.md](SCRIPT_CONSOLIDATION.md)** - Script organization and consolidation

### 🌐 LibreMesh Technology
- **[libremesh/](libremesh/)** - LibreMesh-specific developer documentation
  - **[Hierarchical Configuration System](libremesh/HIERARCHICAL-CONFIGURATION.md)** - Multi-level configuration management
  - **[Architecture & Protocols](libremesh/README.md)** - LibreMesh system architecture guides
  - **Package Development, APIs, and Community Setup** *(see libremesh/ directory)*

### 🖥️ QEMU Integration
- **[qemu/](qemu/)** - Virtualization and testing environment
  - **[QEMU-INTEGRATION.md](qemu/QEMU-INTEGRATION.md)** - Integration with lime-dev
  - **[QEMU-CONFIGURATIONS.md](qemu/QEMU-CONFIGURATIONS.md)** - Virtual machine configurations
  - **[QEMU-IMPLEMENTATION-DECISIONS.md](qemu/QEMU-IMPLEMENTATION-DECISIONS.md)** - Design decisions and rationale

## 🎯 Quick Navigation

### For New Developers
1. **Start Here**: [Main README](../README.md) - Repository overview and quick setup
2. **Development Setup**: [DEVELOPMENT.md](DEVELOPMENT.md) - Complete development environment
3. **LibreMesh Concepts**: [libremesh/](libremesh/) - Understanding LibreMesh technology
4. **Build System**: [ARCHITECTURE.md](ARCHITECTURE.md) - Repository structure and build process

### For LibreMesh Contributors
1. **LibreMesh Documentation**: [libremesh/](libremesh/) - LibreMesh-specific guides
2. **Configuration System**: [libremesh/HIERARCHICAL-CONFIGURATION.md](libremesh/HIERARCHICAL-CONFIGURATION.md) - Essential for LibreMesh development
3. **Development Workflow**: [DEVELOPMENT.md](DEVELOPMENT.md) - Building and testing
4. **Contribution Guidelines**: [CONTRIBUTING.md](CONTRIBUTING.md) - Standards and processes

### For Community Administrators
1. **Configuration Management**: [libremesh/HIERARCHICAL-CONFIGURATION.md](libremesh/HIERARCHICAL-CONFIGURATION.md) - Multi-level settings
2. **Device Upgrade**: [Legacy Router Upgrade](../scripts/core/upgrade-legacy-router.sh) - Automated device management
3. **Patch Management**: [Patches System](../patches/) - Community-specific modifications
4. **Troubleshooting**: [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions

## 📖 Documentation Types

### 🏗️ **Repository Documentation** (lime-dev specific)
**Purpose**: Explains the lime-dev umbrella repository, build system, and development workflows

**Contents**:
- Repository architecture and structure
- Build system configuration and usage
- Development environment setup
- Script organization and utilities
- QEMU integration and testing

### 🌐 **LibreMesh Documentation** (Technology specific)  
**Purpose**: Covers LibreMesh mesh networking technology, protocols, and APIs

**Contents**:
- LibreMesh configuration system
- Mesh networking protocols and architecture
- Package development and APIs
- Community deployment guides
- Network administration and troubleshooting

### 🔧 **Integration Documentation** (Cross-cutting)
**Purpose**: Documents how lime-dev and LibreMesh work together

**Contents**:
- Building LibreMesh with lime-dev
- Testing LibreMesh in QEMU environments
- Patch management for LibreMesh packages
- Device upgrade and management workflows

## 🔗 External Resources

### Official LibreMesh
- **[LibreMesh Website](https://libremesh.org)** - Project homepage and user documentation
- **[LibreMesh GitHub](https://github.com/libremesh)** - Source code repositories
- **[Community Documentation](https://libremesh.org/docs)** - User guides and tutorials

### Development Resources
- **[OpenWrt Documentation](https://openwrt.org/docs)** - Base system documentation
- **[UCI Configuration](https://openwrt.org/docs/guide-user/base-system/uci)** - Configuration system
- **[BATMAN-adv](https://www.open-mesh.org/projects/batman-adv/wiki)** - Mesh routing protocol

### Community Support
- **[Mailing Lists](https://lists.libremesh.org)** - Development and user discussions
- **[IRC Channel](irc://irc.oftc.net/libremesh)** - Real-time chat support
- **[GitHub Issues](https://github.com/libremesh/lime-packages/issues)** - Bug reports and feature requests

## 🚀 Contributing to Documentation

### Documentation Standards
- **Clear Structure**: Use consistent markdown formatting and heading hierarchy
- **Practical Examples**: Include working code examples and configurations
- **Cross-References**: Link related concepts within and outside the repository
- **Testing**: Verify all examples and procedures work correctly
- **Maintenance**: Keep documentation updated with code changes

### Adding Documentation
1. **Identify Category**: Repository-specific → docs/, LibreMesh-specific → docs/libremesh/
2. **Create Content**: Follow existing documentation patterns and standards
3. **Update Indexes**: Add links to relevant README.md files
4. **Cross-Reference**: Link from related documentation files
5. **Test Examples**: Verify all code and configuration examples work
6. **Submit PR**: Follow standard lime-dev contribution process

### Documentation Locations

```
docs/                          # lime-dev repository documentation
├── README.md                  # This index file
├── ARCHITECTURE.md            # Repository structure
├── DEVELOPMENT.md             # Development environment  
├── TROUBLESHOOTING.md         # Common issues
├── libremesh/                 # LibreMesh technology documentation
│   ├── README.md              # LibreMesh docs index
│   ├── HIERARCHICAL-CONFIGURATION.md  # Configuration system
│   └── [additional guides]    # Architecture, APIs, deployment
└── qemu/                      # QEMU virtualization
    ├── QEMU-INTEGRATION.md    # lime-dev integration
    └── [qemu configs]         # Virtual machine setup
```

## 📊 Documentation Status

### ✅ Complete
- lime-dev repository architecture and development setup
- LibreMesh hierarchical configuration system
- QEMU integration and virtualization
- Patch management system
- Legacy device upgrade workflows

### 🚧 In Progress  
- LibreMesh package development guide
- Community deployment procedures
- API documentation and references
- Advanced troubleshooting scenarios

### 📋 Planned
- LibreMesh protocol deep dives
- Performance optimization guides
- Security hardening procedures
- Integration testing frameworks

---

**Getting Started**: New to lime-dev? Start with the [main README](../README.md), then proceed to [DEVELOPMENT.md](DEVELOPMENT.md) for setup, and explore [libremesh/](libremesh/) for LibreMesh-specific concepts.