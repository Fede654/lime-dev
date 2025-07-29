#!/bin/bash
#
# Master test runner for double confirmation functionality
# Guarantees that destructive build operations require proper confirmation
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "${BLUE}$1${NC}"; }
print_success() { echo -e "${GREEN}$1${NC}"; }

main() {
    print_header "🛡️  Double Confirmation Test Suite"
    print_header "======================================"
    echo
    print_header "This test suite guarantees that destructive 'lime build' operations"
    print_header "require proper two-stage confirmation to prevent accidental data loss."
    echo
    
    # Run all confirmation tests
    local all_passed=true
    
    print_header "📋 Test 1: Confirmation Logic Unit Tests"
    echo "Testing the confirmation function in isolation..."
    if ! "$SCRIPT_DIR/test-confirmation-logic.sh"; then
        all_passed=false
    fi
    echo
    
    print_header "📋 Test 2: Integration Tests with Lime Command"
    echo "Testing actual lime build command with confirmation..."
    if ! "$SCRIPT_DIR/test-lime-build-confirmation.sh"; then
        all_passed=false
    fi
    echo
    
    # Summary
    if [[ "$all_passed" == "true" ]]; then
        print_success "🎉 ALL TESTS PASSED!"
        echo
        print_success "✅ Double confirmation is working correctly"
        print_success "✅ Users cannot accidentally delete build data"
        print_success "✅ First confirmation (yes/no) works properly"
        print_success "✅ Second confirmation requires 'DELETE' in capitals"
        print_success "✅ Cancellation provides helpful alternatives"
        print_success "✅ Integration with lime command works properly"
        echo
        print_header "🛡️  GUARANTEE: Destructive operations are properly protected"
        exit 0
    else
        echo "❌ Some tests failed - double confirmation may not be working"
        exit 1
    fi
}

main "$@"