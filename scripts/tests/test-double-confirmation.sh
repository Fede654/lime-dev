#!/bin/bash
#
# Test script for double confirmation in lime build
# Ensures destructive operations require proper two-stage confirmation
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIME_BUILD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_SCRIPT="$LIME_BUILD_DIR/scripts/build.sh"

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

test_count=0
pass_count=0
fail_count=0

print_test_header() { echo -e "${BLUE}[TEST]${NC} $1"; }
print_test_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((pass_count++)); }
print_test_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((fail_count++)); }
print_test_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

run_test() {
    local test_name="$1"
    local input_sequence="$2"
    local expected_behavior="$3"
    
    ((test_count++))
    print_test_header "Test $test_count: $test_name"
    
    # Create temporary test environment
    local temp_dir=$(mktemp -d)
    local test_build_dir="$temp_dir/build"
    mkdir -p "$test_build_dir/bin/targets/test"
    
    # Create fake firmware files to simulate existing build data
    echo "fake firmware 1" > "$test_build_dir/bin/targets/test/firmware1.bin"
    echo "fake firmware 2" > "$test_build_dir/bin/targets/test/firmware2.bin"
    
    # Create fake build directory with some data
    mkdir -p "$test_build_dir/feeds" "$test_build_dir/tmp"
    echo "build data" > "$test_build_dir/feeds/test_data"
    
    # Run build script with simulated input and capture output
    local output_file=$(mktemp)
    local exit_code=0
    
    cd "$temp_dir"
    
    # Set up environment to use our test build directory and skip config validation
    export BUILD_DIR="$test_build_dir"
    export SKIP_CONFIG_VALIDATION="true"
    export SKIP_MANDATORY_VALIDATION="true"
    
    # Simulate the input sequence and capture output
    echo -e "$input_sequence" | timeout 15s "$BUILD_SCRIPT" native librerouter-v1 > "$output_file" 2>&1 || exit_code=$?
    
    local output=$(cat "$output_file")
    
    # Test the behavior
    case "$expected_behavior" in
        "first_no_cancellation")
            if echo "$output" | grep -q "Build cancelled by user" && \
               echo "$output" | grep -q "Alternative options:" && \
               ! echo "$output" | grep -q "DOUBLE CONFIRMATION REQUIRED"; then
                print_test_pass "Correctly cancelled at first confirmation with alternatives"
            else
                print_test_fail "First confirmation cancellation not working properly"
                echo "Output: $output"
            fi
            ;;
        "second_cancel_cancellation")
            if echo "$output" | grep -q "DOUBLE CONFIRMATION REQUIRED" && \
               echo "$output" | grep -q "Build cancelled at final confirmation step" && \
               echo "$output" | grep -q "Data preservation alternatives:"; then
                print_test_pass "Correctly cancelled at second confirmation with preservation alternatives"
            else
                print_test_fail "Second confirmation cancellation not working properly"
                echo "Output: $output"
            fi
            ;;
        "invalid_final_confirmation")
            if echo "$output" | grep -q "DOUBLE CONFIRMATION REQUIRED" && \
               echo "$output" | grep -q "Type 'DELETE' (in capitals)" && \
               ! echo "$output" | grep -q "Double confirmation completed"; then
                print_test_pass "Correctly rejected invalid final confirmation"
            else
                print_test_fail "Invalid final confirmation not properly rejected"
                echo "Output: $output"
            fi
            ;;
        "successful_double_confirmation")
            if echo "$output" | grep -q "DOUBLE CONFIRMATION REQUIRED" && \
               echo "$output" | grep -q "Double confirmation completed" && \
               echo "$output" | grep -q "proceeding with destructive"; then
                print_test_pass "Successfully completed double confirmation"
            else
                print_test_fail "Double confirmation not completing properly"
                echo "Output: $output"
            fi
            ;;
    esac
    
    # Cleanup
    rm -rf "$temp_dir" "$output_file"
    unset BUILD_DIR
    cd "$LIME_BUILD_DIR"
}

main() {
    print_test_header "Double Confirmation Test Suite"
    print_test_info "Testing destructive build operation confirmations"
    echo
    
    # Test 1: First confirmation - user says 'no'
    run_test "First confirmation cancellation" "no" "first_no_cancellation"
    
    # Test 2: First confirmation 'yes', second confirmation 'cancel'
    run_test "Second confirmation cancellation" "yes\ncancel" "second_cancel_cancellation"
    
    # Test 3: First confirmation 'yes', invalid second confirmation
    run_test "Invalid final confirmation" "yes\ndelete\ncancel" "invalid_final_confirmation"
    
    # Test 4: Full double confirmation success
    run_test "Successful double confirmation" "yes\nDELETE" "successful_double_confirmation"
    
    echo
    print_test_header "Test Results Summary"
    echo "  Total tests: $test_count"
    echo "  Passed: $pass_count"
    echo "  Failed: $fail_count"
    
    if [[ $fail_count -eq 0 ]]; then
        print_test_pass "All double confirmation tests passed! ✅"
        echo
        print_test_info "The build system properly:"
        print_test_info "• Requires two separate confirmations for destructive operations"
        print_test_info "• Provides helpful alternatives at each cancellation point"
        print_test_info "• Rejects invalid confirmation inputs"
        print_test_info "• Only proceeds after explicit 'DELETE' confirmation"
        exit 0
    else
        print_test_fail "Some tests failed! Double confirmation may not be working properly"
        exit 1
    fi
}

# Test that build script exists
if [[ ! -f "$BUILD_SCRIPT" ]]; then
    print_test_fail "Build script not found: $BUILD_SCRIPT"
    exit 1
fi

main "$@"