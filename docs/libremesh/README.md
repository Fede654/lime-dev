# LibreMesh Developer Documentation

This directory contains comprehensive developer documentation for LibreMesh mesh networking technology. These guides focus on LibreMesh-specific concepts, architecture, and development practices, complementing the lime-dev umbrella repository documentation.

## 📚 Documentation Structure

### Core LibreMesh Concepts
- **[Hierarchical Configuration System](HIERARCHICAL-CONFIGURATION.md)** - Multi-level configuration management with priority-based merging
- **[Architecture Overview](ARCHITECTURE.md)** *(planned)* - LibreMesh system architecture and components
- **[Mesh Networking Protocols](MESH-PROTOCOLS.md)** *(planned)* - BATMAN-adv, Babel, and routing protocols

### Development Guides  
- **[Package Development](PACKAGE-DEVELOPMENT.md)** *(planned)* - Creating and maintaining LibreMesh packages
- **[Configuration Modules](CONFIG-MODULES.md)** *(planned)* - Extending the configuration system
- **[Web Interface Development](WEB-INTERFACE.md)** *(planned)* - lime-app frontend development

### Administration & Deployment
- **[Community Setup Guide](COMMUNITY-SETUP.md)** *(planned)* - Deploying mesh networks for communities
- **[Node Administration](NODE-ADMIN.md)** *(planned)* - Managing individual mesh nodes
- **[Troubleshooting Guide](TROUBLESHOOTING.md)** *(planned)* - Common issues and solutions

### Integration & APIs
- **[ubus API Reference](UBUS-API.md)** *(planned)* - System bus API for applications
- **[Network APIs](NETWORK-API.md)** *(planned)* - Networking and routing APIs
- **[Monitoring & Statistics](MONITORING.md)** *(planned)* - Network monitoring and metrics

## 🎯 Quick Navigation

### For New Developers
1. Start with [Hierarchical Configuration System](HIERARCHICAL-CONFIGURATION.md) to understand LibreMesh configuration management
2. Review the main [lime-dev README](../../README.md) for development environment setup
3. Check [lime-dev DEVELOPMENT](../DEVELOPMENT.md) for build system and workflow

### For Community Administrators  
1. Read [Hierarchical Configuration System](HIERARCHICAL-CONFIGURATION.md) sections on community configuration
2. Refer to lime-dev [upgrade scripts](../../scripts/core/upgrade-legacy-router.sh) for device management
3. Use lime-dev [patch system](../../patches/) for community-specific modifications

### For Mesh Network Operators
1. Understand configuration hierarchy for network-wide settings
2. Learn about device-specific and node-specific customizations
3. Explore automated deployment and management tools in lime-dev

## 🔗 Related Documentation

### lime-dev Repository Documentation
- **[README.md](../../README.md)** - Main lime-dev repository overview and setup
- **[DEVELOPMENT.md](../DEVELOPMENT.md)** - Development environment and build system
- **[ARCHITECTURE.md](../ARCHITECTURE.md)** - lime-dev umbrella repository architecture
- **[QEMU Integration](../qemu/)** - Virtualization and testing environment

### External LibreMesh Resources
- **[Official LibreMesh Documentation](https://libremesh.org/docs)** - User guides and tutorials
- **[LibreMesh GitHub](https://github.com/libremesh)** - Source code repositories
- **[Community Forum](https://lists.libremesh.org)** - Discussion and support
- **[Development Wiki](https://github.com/libremesh/lime-packages/wiki)** - Technical specifications

## 🚀 Contributing to LibreMesh Documentation

### Documentation Standards
- **Clear Structure**: Use consistent heading hierarchy and formatting
- **Practical Examples**: Include working configuration examples and code snippets  
- **Cross-References**: Link related concepts and external documentation
- **Up-to-Date**: Keep documentation synchronized with code changes

### Adding New Documentation
1. Create new `.md` files in appropriate subdirectories
2. Update this README.md index with links to new content
3. Add cross-references from related documents
4. Test all examples and configurations
5. Submit via standard lime-dev contribution process

### Documentation Categories

#### 📖 **Concept Guides** 
- Explain LibreMesh architectural concepts
- Focus on understanding rather than step-by-step procedures
- Include diagrams and conceptual examples

#### 🔧 **Technical References**
- Detailed API documentation
- Configuration file specifications  
- Protocol and data structure references

#### 📋 **How-To Guides**
- Step-by-step procedures for specific tasks
- Problem-solving oriented
- Practical examples with expected outcomes

#### 🎓 **Tutorials**
- Learning-oriented comprehensive guides
- Cover complete workflows from start to finish
- Suitable for newcomers to LibreMesh development

## 📝 Documentation Roadmap

### High Priority
- [ ] **Architecture Overview** - Complete LibreMesh system architecture
- [ ] **Package Development Guide** - Creating and maintaining LibreMesh packages
- [ ] **Community Setup Guide** - Comprehensive deployment guide

### Medium Priority  
- [ ] **Configuration Modules Guide** - Extending the configuration system
- [ ] **ubus API Reference** - Complete API documentation
- [ ] **Troubleshooting Guide** - Common issues and solutions

### Low Priority
- [ ] **Protocol Deep Dives** - Detailed mesh networking protocol guides
- [ ] **Performance Optimization** - Network tuning and optimization
- [ ] **Security Hardening** - Security best practices and configurations

## 🔍 Finding Information

### Search Strategy
1. **Start Local**: Check this LibreMesh documentation directory first
2. **Expand to lime-dev**: Look in main lime-dev documentation for build/development info
3. **Check Source**: Examine source code in `repos/lime-packages/` for implementation details
4. **External Resources**: Consult official LibreMesh documentation and community forums

### Common Documentation Locations
```
docs/libremesh/           # LibreMesh-specific guides (this directory)
docs/                     # lime-dev umbrella repository documentation  
repos/lime-packages/      # LibreMesh source code and inline documentation
patches/                  # Community patches and modifications
scripts/                  # Development tools and utilities
tools/                    # Additional development tools
```

### Getting Help
- **IRC**: #libremesh on OFTC network
- **Mailing List**: libremesh@lists.libremesh.org
- **GitHub Issues**: Report documentation gaps or errors
- **Community Forum**: General discussion and questions

## 📊 Documentation Metrics

- **Coverage**: Core concepts documented, APIs and tutorials in progress
- **Accuracy**: Documentation reviewed and tested with LibreMesh 2023.05+
- **Maintenance**: Updated with major lime-dev releases
- **Community**: Contributions welcome from developers and users

---

**Note**: This documentation focuses on LibreMesh-specific development. For lime-dev repository structure, build system, and umbrella project information, see the main [lime-dev documentation](../)