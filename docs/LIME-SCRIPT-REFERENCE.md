# Lime Script Complete Reference - Call Chain Documentation

This document provides extensive documentation of the `lime` script functionality, showing the complete call chains from entry point to final execution for every command and option.

## Main Entry Point

```
./scripts/lime -> main() -> case command dispatch
```

## Command Reference with Complete Call Chains

### 1. SETUP COMMANDS

#### `lime setup` [options]
```
lime setup
├── scripts/lime:355 -> exec scripts/setup.sh
└── scripts/setup.sh
    ├── main() -> check_directory()
    ├── case "install" (default)
    └── exec scripts/core/setup-lime-dev-safe.sh
        ├── validate_environment()
        ├── setup_directories()
        ├── scripts/utils/update-repos.sh
        ├── scripts/utils/env-setup.sh
        ├── scripts/utils/validate-config-integrity.sh
        └── tools/verify/setup.sh --quick
```

**Options:**
- `--build-remote-only`: Skip local repository cloning
- `--skip-validation`: Skip post-setup validation
- `--export-dot`: Export dependency graph as DOT file (with graph)

#### `lime setup check`
```
lime setup check
├── scripts/lime:355 -> exec scripts/setup.sh check
└── scripts/setup.sh
    ├── main() -> case "check"
    └── exec scripts/core/check-setup.sh
        ├── check_dependencies()
        ├── check_repositories()
        ├── scripts/utils/dependency-graph.sh ascii
        └── validate_configuration()
```

#### `lime setup update`
```
lime setup update
├── scripts/lime:355 -> exec scripts/setup.sh update
└── scripts/setup.sh
    ├── main() -> case "update"
    └── exec scripts/utils/update-repos.sh
        ├── parse_versions_config()
        ├── update_repository() (for each repo)
        ├── scripts/utils/validate-config-integrity.sh
        └── scripts/utils/dependency-graph.sh ascii
```

#### `lime setup graph` [--export-dot]
```
lime setup graph
├── scripts/lime:355 -> exec scripts/setup.sh graph
└── scripts/setup.sh
    ├── main() -> case "graph"
    ├── scripts/utils/dependency-graph.sh detailed
    └── if --export-dot: scripts/utils/dependency-graph.sh dot > graph.dot
```

#### `lime setup install-system`
```
lime setup install-system
├── scripts/lime:355 -> exec scripts/setup.sh install-system
└── scripts/setup.sh
    ├── main() -> case "install-system"
    ├── create_system_symlink()
    └── sudo ln -sf $(pwd)/scripts/lime /usr/local/bin/lime
```

### 2. BUILD COMMANDS

#### `lime build` [method] [target] [options]
```
lime build [options]
├── scripts/lime:358 -> exec scripts/build.sh
└── scripts/build.sh
    ├── main() -> parse_arguments()
    ├── confirm_build_override() (if existing build detected)
    ├── validate_target()
    ├── case method:
    │   ├── "native" (default):
    │   │   ├── scripts/utils/validate-build-mode.sh
    │   │   ├── scripts/utils/inject-build-environment.sh
    │   │   ├── scripts/utils/package-source-injector.sh apply
    │   │   └── scripts/core/librerouteros-wrapper.sh
    │   │       ├── cd build/
    │   │       ├── make menuconfig (if needed)
    │   │       ├── make download (if --download-only)
    │   │       └── make -j$(nproc) (full build)
    │   └── "docker":
    │       └── scripts/core/docker-build.sh
    │           ├── docker build -t lime-build .
    │           ├── docker run lime-build
    │           └── copy artifacts from container
    └── post_build_verification()
```

**Methods:**
- `native`: Direct build on host system (default, fastest)
- `docker`: Containerized build (requires network)

**Targets:**
- `librerouter-v1`: LibreRouter v1 hardware (default)
- `x86_64`: x86_64 virtual machine/QEMU target
- `ath79_generic_multiradio`: ATH79 multi-radio devices
- `hilink_hlk-7621a-evb`: HiLink HLK-7621A evaluation board
- `youhua_wr1200js`: Youhua WR1200JS router
- `librerouter-r2`: LibreRouter R2 (experimental)

**Options:**
- `--local`: Use local repository sources for development
- `--download-only`: Download dependencies only (no build)
- `--shell`: Open interactive shell (docker method only)
- `--clean [TYPE]`: Clean build environment
- `--skip-validation`: Skip build mode validation

#### `lime build --clean` [type]
```
lime build --clean [type]
├── scripts/lime:412 -> exec scripts/build.sh --clean [type]
└── scripts/build.sh
    ├── main() -> case "--clean"
    ├── clean_build_artifacts()
    └── case clean_type:
        ├── "all": rm -rf build/ downloads/ (3.2GB)
        ├── "build": rm -rf build/ (2.3GB)
        ├── "downloads": rm -rf downloads/ (854MB)
        └── "outputs": rm -rf build/bin/ (4MB)
```

### 3. REBUILD COMMANDS (Development Speed Optimization)

#### `lime rebuild` [type] [options]
```
lime rebuild [type]
├── scripts/lime:361-372 -> case dispatch
├── detect rebuild type (lime-app|incremental|selective)
└── exec scripts/rebuild.sh [type]
    ├── main() -> parse_arguments()
    ├── check_initial_build_required()
    ├── apply_local_sources()
    │   └── scripts/utils/package-source-injector.sh apply local
    └── case rebuild_type:
        ├── "lime-app": rebuild_lime_app_only()
        ├── "incremental": rebuild_lime_packages()
        └── "selective": rebuild_specific_package()
```

#### `lime rebuild lime-app` [--multi]
```
lime rebuild lime-app
├── scripts/lime:365 -> exec scripts/rebuild.sh lime-app
└── scripts/rebuild.sh -> rebuild_lime_app_only()
    ├── check_initial_build_required()
    ├── apply_local_sources()
    ├── cd build/
    ├── make package/feeds/libremesh/lime-app/clean
    ├── make package/feeds/libremesh/lime-app/compile
    ├── verify_package_creation()
    ├── generate_firmware_image():
    │   ├── if --multi: make -j$(nproc) (2-5 min, risky)
    │   └── else: make target/linux/install (3-8 min, safe)
    └── show_deployment_options()
```

#### `lime rebuild incremental` [--multi]
```
lime rebuild incremental
├── scripts/lime:370 -> exec scripts/rebuild.sh incremental
└── scripts/rebuild.sh -> rebuild_lime_packages()
    ├── check_initial_build_required()
    ├── apply_local_sources()
    ├── cd build/
    ├── for each lime package:
    │   ├── make package/feeds/libremesh/$pkg/clean
    │   ├── make package/feeds/libremesh/$pkg/compile
    │   └── verify_package_creation()
    ├── generate_firmware_image():
    │   ├── if --multi: make -j$(nproc) (3-8 min, risky)
    │   └── else: make target/linux/install (5-10 min, safe)
    └── show_results()
```

**Lime packages rebuilt:**
- lime-app, lime-system, shared-state, lime-proto-babeld
- lime-proto-batadv, lime-hwd-openwrt-wan, ubus-lime-utils
- ubus-lime-metrics, lime-debug

#### `lime rebuild selective --package PKG` [--multi]
```
lime rebuild selective --package shared-state
├── scripts/lime:370 -> exec scripts/rebuild.sh selective --package shared-state
└── scripts/rebuild.sh -> rebuild_specific_package()
    ├── check_initial_build_required()
    ├── apply_local_sources()
    ├── find_package_path() (libremesh/packages/base feeds)
    ├── cd build/
    ├── make $package_path/clean
    ├── make $package_path/compile
    ├── verify_package_creation()
    ├── generate_firmware_image():
    │   ├── if --multi: make -j$(nproc) (faster, risky)
    │   └── else: make target/linux/install (safer)
    └── show_results()
```

#### `lime rebuild-fast` [--multi]
```
lime rebuild-fast
├── scripts/lime:375 -> exec scripts/rebuild.sh lime-app
└── (Same as lime rebuild lime-app)
```

**Rebuild Options:**
- `--local`: Force local sources (automatically applied)
- `--multi`: Use multi-threaded firmware generation (faster but risky)
- `--package PKG`: Specific package to rebuild (use with selective)

### 4. VERIFICATION COMMANDS

#### `lime verify` [command] [options]
```
lime verify [command]
├── scripts/lime:383 -> run_verify_command()
└── case verify_command:
    ├── "all" (default): exec tools/verify/setup.sh
    ├── "setup": exec tools/verify/setup.sh --quick
    ├── "platform": exec tools/verify/setup.sh --platform-only
    └── "qemu": exec tools/verify/setup.sh --platform-only
```

#### `lime verify all` [--verbose]
```
lime verify all
├── scripts/lime:202 -> exec tools/verify/setup.sh
└── tools/verify/setup.sh
    ├── detect_platform()
    ├── load platform script:
    │   ├── tools/verify/platforms/linux.sh
    │   ├── tools/verify/platforms/macos.sh
    │   └── tools/verify/platforms/windows.sh
    ├── check_system_requirements()
    ├── check_build_environment()
    ├── check_repositories()
    ├── validate_configurations()
    └── generate_verification_report()
```

### 5. SECURITY COMMANDS

#### `lime security scan` [options] [path]
```
lime security scan [options]
├── scripts/lime:387 -> run_security_command()
├── case "scan": exec scripts/security/simple-scan.sh
└── scripts/security/simple-scan.sh
    ├── parse_arguments()
    ├── scan_target="${path:-$LIME_DEV_ROOT}"
    ├── security_checks():
    │   ├── check_hardcoded_secrets()
    │   ├── check_libremesh_defaults()
    │   ├── check_dangerous_patterns()
    │   ├── check_file_permissions()
    │   ├── check_ssh_keys()
    │   └── check_insecure_protocols()
    ├── if --quick: secrets_only_scan()
    ├── if --fail-fast: exit 1 on first issue
    └── generate_security_report()
```

**Security scan options:**
- `--quick`: Quick scan (secrets only)
- `--fail-fast`: Exit with error if issues found (for CI/CD)
- `[path]`: Scan specific directory

### 6. QEMU MANAGEMENT

#### `lime qemu` [command] [options]
```
lime qemu [command]
├── scripts/lime:395 -> run_qemu_command()
├── case qemu_command -> exec tools/qemu/qemu-manager.sh
└── tools/qemu/qemu-manager.sh
    ├── case command:
    │   ├── "start": start_qemu_environment()
    │   ├── "stop": stop_qemu_environment()
    │   ├── "status": check_qemu_status()
    │   ├── "restart": stop_qemu_environment() && start_qemu_environment()
    │   ├── "deploy": deploy_lime_app_to_qemu()
    │   └── "console": connect_qemu_console()
    └── qemu_operation_handler()
```

#### `lime qemu start`
```
lime qemu start
├── tools/qemu/qemu-manager.sh start
└── start_qemu_environment()
    ├── check_firmware_availability()
    ├── setup_qemu_network()
    ├── tools/qemu/qemu-network-libremesh.sh
    ├── start_qemu_instance()
    ├── wait_for_network_ready()
    └── validate_qemu_connectivity()
```

### 7. UPSTREAM CONTRIBUTION

#### `lime upstream` [command] [repo]
```
lime upstream [command]
├── scripts/lime:391 -> run_upstream_command()
└── case upstream_command:
    ├── "setup": exec tools/upstream/setup-aliases.sh setup
    ├── "aliases": exec tools/upstream/setup-aliases.sh aliases
    └── "prepare": show_upstream_workflow()
```

#### `lime upstream setup` [repo]
```
lime upstream setup [repo]
├── tools/upstream/setup-aliases.sh setup
└── setup_upstream_remotes()
    ├── for repo in [lime-app|lime-packages|librerouteros|all]:
    │   ├── cd repos/$repo/
    │   ├── git remote add upstream <official-repo-url>
    │   ├── setup_git_aliases()
    │   └── configure_contribution_workflow()
    └── show_contribution_instructions()
```

### 8. PATCH MANAGEMENT

#### `lime patches` [command] [options]
```
lime patches [command]
├── scripts/lime:422 -> exec scripts/utils/apply-patches.sh
└── scripts/utils/apply-patches.sh
    ├── case command:
    │   ├── "list": list_available_patches()
    │   ├── "apply": apply_all_patches()
    │   └── "apply --dry-run": preview_patch_application()
    ├── patch_libremesh_packages()
    ├── patch_build_system()
    └── validate_patch_application()
```

### 9. MESH NETWORK MANAGEMENT

#### `lime mesh` [command] [config] [target]
```
lime mesh [command]
├── scripts/lime:426 -> exec scripts/utils/mesh-manager.sh
└── scripts/utils/mesh-manager.sh
    ├── case command:
    │   ├── "list": list_mesh_configurations()
    │   ├── "deploy": deploy_mesh_config()
    │   ├── "status": check_mesh_status()
    │   └── "verify": verify_mesh_connectivity()
    └── mesh_operation_handler()
```

#### `lime mesh deploy testmesh` [target_ip]
```
lime mesh deploy testmesh [10.13.0.1]
├── scripts/utils/mesh-manager.sh deploy testmesh
└── deploy_mesh_config()
    ├── load_mesh_configuration()
    ├── tools/mesh-configs/deploy-test-mesh.sh
    ├── upload_configuration_to_router()
    ├── restart_libremesh_services()
    └── validate_mesh_deployment()
```

### 10. LEGACY ROUTER UPGRADE

#### `lime upgrade` [target_ip] [firmware.bin]
```
lime upgrade [target_ip] [firmware.bin]
├── scripts/lime:431 -> exec scripts/core/upgrade-legacy-router.sh
└── scripts/core/upgrade-legacy-router.sh
    ├── parse_upgrade_arguments()
    ├── case upgrade_type:
    │   ├── safe_upgrade_only():
    │   │   ├── download_safe_upgrade_script()
    │   │   ├── scripts/utils/transfer-legacy-hex.sh
    │   │   ├── ssh_upload_to_router()
    │   │   └── execute_safe_upgrade()
    │   └── firmware_upgrade():
    │       ├── perform_safe_upgrade()
    │       ├── upload_firmware_binary()
    │       ├── trigger_firmware_upgrade()
    │       └── verify_upgrade_success()
    └── post_upgrade_validation()
```

### 11. UTILITY COMMANDS

#### `lime update` (alias for setup update)
```
lime update
├── scripts/lime:404 -> exec scripts/setup.sh update
└── (Same as lime setup update)
```

#### `lime deps`
```
lime deps
├── scripts/lime:408 -> exec scripts/utils/dependency-graph.sh ascii
└── scripts/utils/dependency-graph.sh
    ├── parse_versions_config()
    ├── analyze_repository_dependencies()
    ├── generate_ascii_graph()
    └── show_dependency_summary()
```

#### `lime clean` [type]
```
lime clean [type]
├── scripts/lime:411-415 -> exec scripts/build.sh --clean [type]
└── (Same as lime build --clean)
```

#### `lime reset` [options]
```
lime reset [options]
├── scripts/lime:418 -> exec scripts/core/reset.sh
└── scripts/core/reset.sh
    ├── parse_reset_options()
    ├── case reset_mode:
    │   ├── default: reset_preserving_lime_app()
    │   ├── --all: reset_all_repositories()
    │   └── --dry-run: show_reset_preview()
    ├── backup_current_state()
    ├── reset_repository_states()
    └── restore_lime_app_if_preserving()
```

#### `lime dev-cycle`
```
lime dev-cycle
├── scripts/lime:379 -> exec scripts/dev-cycle.sh
└── scripts/dev-cycle.sh
    ├── check_qemu_environment()
    ├── rebuild_lime_app()
    ├── deploy_to_qemu()
    ├── run_integration_tests()
    └── show_development_summary()
```

## File Structure Reference

```
scripts/
├── lime                           # Main entry point
├── setup.sh                      # Setup operations dispatcher
├── build.sh                      # Build operations dispatcher  
├── rebuild.sh                    # Incremental rebuild operations
├── dev-cycle.sh                  # Development cycle automation
├── core/
│   ├── setup-lime-dev-safe.sh   # Safe setup implementation
│   ├── check-setup.sh           # Setup status checker
│   ├── reset.sh                 # Repository reset utility
│   ├── librerouteros-wrapper.sh # LibreRouterOS build wrapper
│   ├── docker-build.sh          # Docker build implementation
│   └── upgrade-legacy-router.sh # Legacy router upgrade utility
├── utils/
│   ├── update-repos.sh          # Repository update utility
│   ├── dependency-graph.sh      # Dependency analysis
│   ├── package-source-injector.sh # Local source injection
│   ├── validate-build-mode.sh   # Build mode validation
│   ├── inject-build-environment.sh # Environment injection
│   ├── apply-patches.sh         # Patch management
│   ├── mesh-manager.sh          # Mesh network management
│   ├── env-setup.sh             # Environment setup
│   ├── config-parser.sh         # Configuration parsing
│   ├── validate-config-integrity.sh # Config validation
│   ├── versions-parser.sh       # Version management
│   └── transfer-legacy-hex.sh   # Legacy transfer utility
└── security/
    └── simple-scan.sh           # Security scanning tool

tools/
├── verify/
│   ├── setup.sh                 # Environment verification
│   └── platforms/
│       ├── linux.sh            # Linux-specific checks
│       ├── macos.sh            # macOS-specific checks
│       └── windows.sh          # Windows-specific checks
├── upstream/
│   └── setup-aliases.sh        # Upstream contribution setup
├── qemu/
│   ├── qemu-manager.sh         # QEMU management
│   ├── qemu-network-libremesh.sh # Network setup
│   ├── deploy-to-qemu.sh       # Deployment automation
│   └── verify-qemu.sh          # QEMU verification
└── mesh-configs/
    ├── deploy-test-mesh.sh     # TestMesh deployment
    └── mesh-verification.sh    # Mesh connectivity verification
```

## Performance Characteristics

### Build Times
- **Full build**: 15-45 minutes (everything from scratch)
- **lime rebuild incremental**: 5-10 minutes (packages + optimized target build)
- **lime rebuild lime-app**: 3-8 minutes (lime-app + optimized target build)
- **lime rebuild --multi**: 2-8 minutes (multi-threaded, risky)

### Clean Operation Sizes
- **lime clean all**: 3.2GB (complete cleanup)
- **lime clean build**: 2.3GB (build directory only)
- **lime clean downloads**: 854MB (downloads cache only)
- **lime clean outputs**: 4MB (binary outputs only)

### Optimization Modes
- **Default mode**: `make target/linux/install` (optimized, safe)
- **Multi-threaded mode**: `make -j$(nproc)` (fastest, risky)
- **Single-threaded mode**: `make -j1` (slowest, most reliable)

## Error Handling and Recovery

Each major operation includes:
- Pre-execution validation
- Environment verification
- Post-execution validation
- Automatic cleanup on failure
- Detailed error reporting
- Recovery suggestions

## Integration Points

- **CI/CD**: `--fail-fast` options for automated testing
- **IDE**: F5 debugging configurations
- **QEMU**: Seamless integration for testing
- **Docker**: Containerized builds for reproducibility
- **Git**: Upstream contribution workflow
- **Security**: Automated security scanning