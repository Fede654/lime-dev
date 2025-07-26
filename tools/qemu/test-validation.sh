#!/bin/bash
#
# Test kernel validation system
#

# Source the smart driver injection functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/smart-driver-injection.sh"

echo "🧪 Testing Kernel Validation System"
echo "=================================="

# Test 1: Validate current system
echo ""
echo "Test 1: Current system validation"
result=$(validate_kernel_consistency "6.6.86")  # Wrong kernel intentionally
validation_code=$?

echo "Validation result: $result"
echo "Return code: $validation_code"

if [ $validation_code -ne 0 ]; then
    echo "✅ SUCCESS: Validation correctly detected mismatch"
else
    echo "❌ FAILURE: Validation should have detected mismatch"
fi

# Test 2: Validate with correct kernel
echo ""
echo "Test 2: Correct kernel validation"
result2=$(validate_kernel_consistency "5.15.167")  # Correct kernel
validation_code2=$?

echo "Validation result: $result2"
echo "Return code: $validation_code2"

if [ $validation_code2 -eq 0 ]; then
    echo "✅ SUCCESS: Validation correctly accepted matching kernel"
else
    echo "❌ FAILURE: Validation should have accepted correct kernel"
fi

echo ""
echo "🏁 Validation testing complete"