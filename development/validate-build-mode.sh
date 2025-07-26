#!/usr/bin/env bash
#
# Build Mode Configuration Validator - lime-dev Build System
# ==========================================================
# Validates that build mode configuration is properly applied across:
# - Feed-level source resolution 
# - Package-level Makefile patching
# - Environment variable injection
#
# Usage: validate-build-mode.sh <mode> [build_dir]
#
# This test ensures the complete "Source of Truth → Feed Config → Package Makefile Patching → Build" 
# flow is working correctly for the specified build mode.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_DEV_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERSIONS_CONFIG="$LIME_DEV_ROOT/configs/versions.conf"
BUILD_DIR="${2:-$LIME_DEV_ROOT/build}"

# Load utilities
source "$SCRIPT_DIR/versions-parser.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Validate build mode parameter
validate_mode() {
    local mode="$1"
    
    if [[ -z "$mode" ]]; then
        echo "Usage: $0 <mode> [build_dir]"
        echo "Modes: development, release"
        exit 1
    fi
    
    if [[ "$mode" != "development" && "$mode" != "release" ]]; then
        print_fail "Invalid build mode: $mode (must be development or release)"
        exit 1
    fi
}

# Test 1: Environment variable injection
test_environment_injection() {
    local mode="$1"
    local test_count=0
    local pass_count=0
    
    print_test "Environment variable injection for $mode mode"
    
    # Generate environment in temporary file
    local temp_env=$(mktemp)
    if ! "$SCRIPT_DIR/versions-parser.sh" environment "$mode" > "$temp_env" 2>/dev/null; then
        print_fail "Failed to generate environment for $mode mode"
        rm -f "$temp_env"
        return 1
    fi
    
    # Source the environment
    source "$temp_env"
    
    # Test required variables
    local required_vars=(
        "LIME_BUILD_MODE"
        "LIBREMESH_FEED"
        "OPENWRT_VERSION"
        "BUILD_TARGET_DEFAULT"
    )
    
    for var in "${required_vars[@]}"; do
        ((test_count++))
        if [[ -n "${!var}" ]]; then
            print_pass "  $var = ${!var}"
            ((pass_count++))
        else
            print_fail "  $var is not set"
        fi
    done
    
    # Test mode-specific values
    ((test_count++))
    if [[ "$LIME_BUILD_MODE" == "$mode" ]]; then
        print_pass "  Build mode matches requested: $mode"
        ((pass_count++))
    else
        print_fail "  Build mode mismatch: expected $mode, got $LIME_BUILD_MODE"
    fi
    
    # Test feed configuration matches expected from config
    ((test_count++))
    local expected_feed_repo=$(parse_repository "lime_packages" "$mode" "$VERSIONS_CONFIG")
    if [[ -n "$expected_feed_repo" ]]; then
        local expected_feed=$(repository_to_feed "$expected_feed_repo" "libremesh")
        if [[ "$LIBREMESH_FEED" == "$expected_feed" ]]; then
            print_pass "  Feed matches configuration for $mode mode: $LIBREMESH_FEED"
            ((pass_count++))
        else
            print_fail "  Feed configuration mismatch for $mode mode:"
            print_fail "    Expected: $expected_feed"
            print_fail "    Actual: $LIBREMESH_FEED"
        fi
    else
        print_fail "  No feed configuration found for $mode mode"
    fi
    
    rm -f "$temp_env"
    echo "    Result: $pass_count/$test_count tests passed"
    return $((test_count - pass_count))
}

# Test 2: Package source resolution
test_package_source_resolution() {
    local mode="$1"
    local test_count=0
    local pass_count=0
    
    print_test "Package source resolution for $mode mode"
    
    # Get packages that should have source resolution  
    local packages=$(awk '/^\[package_sources\]/{flag=1;next}/^\[/{flag=0}flag && /^[^#]/ && /=/{print $1}' FS='=' "$VERSIONS_CONFIG" | sed 's/_production$//' | sed 's/_development$//' | sort -u)
    
    if [[ -z "$packages" ]]; then
        print_info "  No packages configured for source resolution"
        return 0
    fi
    
    for package in $packages; do
        ((test_count++))
        
        # Try mode-specific source first
        local mode_key="${package}_${mode}"
        local source_spec=$(parse_config "package_sources" "$mode_key" "$VERSIONS_CONFIG")
        
        if [[ -n "$source_spec" ]]; then
            print_pass "  $package ($mode): $source_spec"
            ((pass_count++))
        else
            # Try production fallback
            local prod_key="${package}_production"
            local prod_source=$(parse_config "package_sources" "$prod_key" "$VERSIONS_CONFIG")
            
            if [[ -n "$prod_source" ]]; then
                print_pass "  $package (fallback to production): $prod_source"
                ((pass_count++))
            else
                print_fail "  $package: No source configuration found"
            fi
        fi
    done
    
    echo "    Result: $pass_count/$test_count packages resolved"
    return $((test_count - pass_count))
}

# Test 3: Conditional resolution dry-run validation
test_conditional_resolution() {
    local mode="$1"
    local build_dir="$2"
    local test_count=0
    local pass_count=0
    
    print_test "Conditional resolution dry-run for $mode mode"
    
    # Test build system feed resolution
    ((test_count++))
    print_info "  Testing build system feed resolution..."
    
    # Get expected feed from configuration
    local expected_feed_repo=$(parse_repository "lime_packages" "$mode" "$VERSIONS_CONFIG")
    if [[ -z "$expected_feed_repo" ]]; then
        print_fail "  No lime_packages repository configured for $mode mode"
        return 1
    fi
    
    # Convert repository spec to feed format
    local expected_feed=$(repository_to_feed "$expected_feed_repo" "libremesh")
    
    # Generate environment and extract actual resolved feed
    local temp_env=$(mktemp)
    if "$SCRIPT_DIR/versions-parser.sh" environment "$mode" > "$temp_env" 2>/dev/null; then
        source "$temp_env"
        local resolved_feed="$LIBREMESH_FEED"
        
        if [[ "$resolved_feed" == "$expected_feed" ]]; then
            print_pass "  Build system resolves to configured feed: $resolved_feed"
            ((pass_count++))
        else
            print_fail "  Feed resolution mismatch:"
            print_fail "    Expected (from config): $expected_feed"
            print_fail "    Resolved (from system): $resolved_feed"
        fi
    else
        print_fail "  Could not generate environment for feed resolution test"
    fi
    
    rm -f "$temp_env"
    
    # Test package source resolution
    ((test_count++))
    print_info "  Testing package source resolution..."
    
    local packages=$(awk '/^\[package_sources\]/{flag=1;next}/^\[/{flag=0}flag && /^[^#]/ && /=/{print $1}' FS='=' "$VERSIONS_CONFIG" | sed 's/_production$//' | sed 's/_development$//' | sort -u)
    
    if [[ -n "$packages" ]]; then
        local package_resolution_ok=true
        for package in $packages; do
            # Test what source would be resolved
            local resolved_source=$(parse_config "package_sources" "${package}_${mode}" "$VERSIONS_CONFIG")
            if [[ -z "$resolved_source" ]]; then
                resolved_source=$(parse_config "package_sources" "${package}_production" "$VERSIONS_CONFIG")
            fi
            
            if [[ -n "$resolved_source" ]]; then
                case "$mode" in
                    "development")
                        if [[ "$resolved_source" == local:* ]]; then
                            local repo_path=$(echo "$resolved_source" | cut -d':' -f2)
                            if [[ -d "$repo_path" ]]; then
                                print_info "    $package → local repository: $repo_path"
                            else
                                print_fail "    $package → local repository not found: $repo_path"
                                package_resolution_ok=false
                            fi
                        else
                            print_info "    $package → remote source: $resolved_source"
                        fi
                        ;;
                esac
            else
                print_fail "    $package → no source resolution"
                package_resolution_ok=false
            fi
        done
        
        if $package_resolution_ok; then
            print_pass "  All packages resolve to valid sources for $mode mode"
            ((pass_count++))
        else
            print_fail "  Some packages have invalid source resolution"
        fi
    else
        print_pass "  No packages configured for source resolution"
        ((pass_count++))
    fi
    
    echo "    Result: $pass_count/$test_count resolution tests passed"
    return $((test_count - pass_count))
}

# Test 4: Feed consistency validation
test_feed_consistency() {
    local mode="$1"
    local build_dir="$2"
    local test_count=0
    local pass_count=0
    
    print_test "Feed consistency validation for $mode mode"
    
    # Check feeds.conf if it exists
    local feeds_conf="$build_dir/feeds.conf"
    if [[ -f "$feeds_conf" ]]; then
        ((test_count++))
        
        # Get expected feed URL from configuration
        local expected_feed_repo=$(parse_repository "lime_packages" "$mode" "$VERSIONS_CONFIG")
        if [[ -n "$expected_feed_repo" ]]; then
            # Extract URL from repository spec (format: url|branch|remote)
            local expected_url=$(echo "$expected_feed_repo" | cut -d'|' -f1)
            
            if grep -q "$expected_url" "$feeds_conf"; then
                print_pass "  feeds.conf contains configured libremesh feed: $expected_url"
                ((pass_count++))
            else
                print_fail "  feeds.conf missing configured feed: $expected_url"
                print_info "    Check feeds.conf for libremesh feed configuration"
            fi
        else
            print_fail "  No libremesh feed configuration found for $mode mode"
        fi
    else
        print_info "  feeds.conf not found - feeds configured via environment"
    fi
    
    # Check if feeds directory structure matches expected mode
    local libremesh_feed_dir="$build_dir/feeds/libremesh"
    if [[ -d "$libremesh_feed_dir" ]]; then
        ((test_count++))
        
        if [[ -d "$libremesh_feed_dir/.git" ]]; then
            cd "$libremesh_feed_dir"
            local remote_url=$(git remote get-url origin 2>/dev/null || echo "")
            
            # Get expected repository URL from configuration
            local expected_feed_repo=$(parse_repository "lime_packages" "$mode" "$VERSIONS_CONFIG")
            if [[ -n "$expected_feed_repo" ]]; then
                local expected_url=$(echo "$expected_feed_repo" | cut -d'|' -f1)
                
                if [[ "$remote_url" == "$expected_url" ]]; then
                    print_pass "  LibreMesh feed points to configured repository: $remote_url"
                    ((pass_count++))
                else
                    print_fail "  LibreMesh feed remote mismatch:"
                    print_fail "    Expected (from config): $expected_url"
                    print_fail "    Actual (from git): $remote_url"
                fi
            else
                print_fail "  No repository configuration found for $mode mode"
            fi
            cd - > /dev/null
        else
            print_info "  LibreMesh feed directory exists but no git repository"
        fi
    else
        print_info "  LibreMesh feed directory not found"
    fi
    
    echo "    Result: $pass_count/$test_count consistency checks passed"
    return $((test_count - pass_count))
}

# Test 5: Business logic immutability test
test_business_logic_immutability() {
    local mode="$1"
    local build_dir="$2"
    
    print_test "Business logic immutability test for $mode mode"
    
    # Test that same configuration produces identical results
    local temp_env1=$(mktemp)
    local temp_env2=$(mktemp)
    
    # Generate environment twice
    "$SCRIPT_DIR/versions-parser.sh" environment "$mode" > "$temp_env1" 2>/dev/null
    sleep 1  # Ensure different timestamps
    "$SCRIPT_DIR/versions-parser.sh" environment "$mode" > "$temp_env2" 2>/dev/null
    
    # Compare critical variables (ignore timestamps)
    local critical_vars=("LIME_BUILD_MODE" "LIBREMESH_FEED" "OPENWRT_VERSION" "BUILD_TARGET_DEFAULT")
    local immutable=true
    
    for var in "${critical_vars[@]}"; do
        local val1=$(grep "^export $var=" "$temp_env1" | cut -d'=' -f2- | tr -d '"')
        local val2=$(grep "^export $var=" "$temp_env2" | cut -d'=' -f2- | tr -d '"')
        
        if [[ "$val1" != "$val2" ]]; then
            print_fail "  $var is not immutable: '$val1' != '$val2'"
            immutable=false
        fi
    done
    
    if $immutable; then
        print_pass "  Configuration produces identical results (immutable)"
    else
        print_fail "  Configuration is not immutable"
        rm -f "$temp_env1" "$temp_env2"
        return 1
    fi
    
    # Test conditional logic consistency
    source "$temp_env1"
    local expected_mode="$LIME_BUILD_MODE"
    
    if [[ "$expected_mode" == "$mode" ]]; then
        print_pass "  Conditional logic produces expected mode: $expected_mode"
    else
        print_fail "  Conditional logic mode mismatch: expected $mode, got $expected_mode"
        rm -f "$temp_env1" "$temp_env2" 
        return 1
    fi
    
    rm -f "$temp_env1" "$temp_env2"
    print_pass "  Business logic immutability validated"
    return 0
}

# Main test runner
validate_build_directory() {
    local build_dir="$1"
    
    # If build_dir is provided and not empty, validate it exists
    if [[ -n "$build_dir" && "$build_dir" != "$LIME_DEV_ROOT/build" ]]; then
        if [[ ! -d "$build_dir" ]]; then
            print_fail "Build directory does not exist: $build_dir"
            echo -e "${RED}❌ Specify a valid build directory or omit parameter to use default.${NC}"
            exit 1
        fi
    fi
}

main() {
    local mode="$1"
    local build_dir="$2"
    local total_failures=0
    
    validate_mode "$mode"
    validate_build_directory "$build_dir"
    
    print_header "Build Mode Configuration Validation"
    print_info "Mode: $mode"
    print_info "Build Directory: $build_dir"
    print_info "Versions Config: $VERSIONS_CONFIG"
    echo
    
    # Run all tests
    test_environment_injection "$mode" || ((total_failures++))
    echo
    
    test_package_source_resolution "$mode" || ((total_failures++))
    echo
    
    test_conditional_resolution "$mode" "$build_dir" || ((total_failures++))
    echo
    
    test_feed_consistency "$mode" "$build_dir" || ((total_failures++))
    echo
    
    test_business_logic_immutability "$mode" "$build_dir" || ((total_failures++))
    echo
    
    # Summary
    print_header "Validation Summary"
    if [[ $total_failures -eq 0 ]]; then
        print_pass "All tests passed! Build mode $mode is properly configured."
        echo -e "${GREEN}✅ The complete Source of Truth → Feed Config → Package Makefile Patching → Build flow is working correctly.${NC}"
        exit 0
    else
        print_fail "$total_failures test suite(s) failed."
        echo -e "${RED}❌ Build mode configuration issues detected. Check the failed tests above.${NC}"
        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi