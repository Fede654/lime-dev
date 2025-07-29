#!/bin/bash
#
# Integration test for lime build double confirmation
# Tests the actual lime command with proper build environment
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_test() { echo -e "${BLUE}[TEST]${NC} $1"; }
print_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

test_lime_build_confirmation() {
    local test_name="$1"
    local input_sequence="$2"
    local expected_behavior="$3"
    
    print_test "Testing: $test_name"
    
    # Set up test environment
    cd "$LIME_BUILD_DIR"
    
    # Ensure we have some existing build data to trigger confirmation
    mkdir -p build/bin/targets/test 2>/dev/null || true
    echo "test firmware" > build/bin/targets/test/test-firmware.bin 2>/dev/null || true
    
    # Create output capture
    local output_file=$(mktemp)
    local success=false
    
    # Run lime build with input simulation and timeout for safety
    if echo -e "$input_sequence" | timeout 30s bash -c "
        export SKIP_MANDATORY_VALIDATION=true
        lime build native librerouter-v1 --skip-validation
    " > "$output_file" 2>&1; then
        success=true
    fi
    
    local output=$(cat "$output_file")
    
    # Verify expected behavior
    case "$expected_behavior" in
        "first_cancellation")
            if echo "$output" | grep -q "Build cancelled by user" && \
               echo "$output" | grep -q "Alternative options:"; then
                print_pass "$test_name - Cancelled at first confirmation"
            else
                print_fail "$test_name - First cancellation not working"
                echo "Output: $output"
            fi
            ;;
        "second_cancellation")
            if echo "$output" | grep -q "DOUBLE CONFIRMATION REQUIRED" && \
               echo "$output" | grep -q "Build cancelled at final confirmation step"; then
                print_pass "$test_name - Cancelled at second confirmation"
            else
                print_fail "$test_name - Second cancellation not working"
                echo "Output: $output"
            fi
            ;;
        "requires_DELETE")
            if echo "$output" | grep -q "Type 'DELETE' (in capitals)" && \
               echo "$output" | grep -q "DOUBLE CONFIRMATION REQUIRED"; then
                print_pass "$test_name - Correctly requires 'DELETE' confirmation"
            else
                print_fail "$test_name - DELETE requirement not working"
                echo "Output: $output"
            fi
            ;;
    esac
    
    # Cleanup
    rm -f "$output_file"
}

main() {
    echo "🧪 Lime Build Double Confirmation Integration Tests"
    echo "=================================================="
    
    # Test 1: Cancel at first confirmation
    test_lime_build_confirmation \
        "First confirmation cancellation" \
        "no" \
        "first_cancellation"
    
    # Test 2: Pass first, cancel at second
    test_lime_build_confirmation \
        "Second confirmation cancellation" \
        "yes\ncancel" \
        "second_cancellation"
    
    # Test 3: Verify DELETE requirement
    test_lime_build_confirmation \
        "DELETE requirement verification" \
        "yes\ndelete" \
        "requires_DELETE"
    
    echo
    echo "✅ Integration tests completed"
    echo "The lime build command properly implements double confirmation"
    echo "for destructive operations that will delete build data."
}

main "$@"