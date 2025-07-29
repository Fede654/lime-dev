#!/bin/bash
#
# Focused test for double confirmation logic
# Tests just the confirmation function without full build process
#

set -e

# Extract and test just the confirmation function
test_confirmation_function() {
    local test_name="$1"
    local input_sequence="$2"
    local expected_pattern="$3"
    
    # Create a standalone test script with just the confirmation logic
    local test_script=$(mktemp)
    cat > "$test_script" << 'CONFIRM_FUNC'
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_critical() { echo -e "${RED}[CRITICAL]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Mock BUILD_DIR for testing
BUILD_DIR="/tmp/test_build"
mkdir -p "$BUILD_DIR/bin/targets/test"
echo "test" > "$BUILD_DIR/bin/targets/test/firmware1.bin"
echo "test" > "$BUILD_DIR/bin/targets/test/firmware2.bin"

confirm_destructive_build() {
    local target="$1"
    
    if [[ -d "$BUILD_DIR" ]] || ls build/bin/targets/*/*.bin &>/dev/null 2>&1; then
        print_critical "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
        print_warning "This build will OVERWRITE existing build data:"
        
        if [[ -d "$BUILD_DIR" ]]; then
            local build_size=$(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1 || echo "unknown")
            print_warning "• Build directory: $build_size of data will be replaced"
        fi
        
        if ls build/bin/targets/*/*.bin &>/dev/null 2>&1 || ls "$BUILD_DIR/bin/targets"/*/*.bin &>/dev/null 2>&1; then
            local firmware_count=$(ls "$BUILD_DIR/bin/targets"/*/*.bin 2>/dev/null | wc -l || echo "2")
            print_warning "• Existing firmware files ($firmware_count files)"
        fi
        
        echo
        print_info "Build details:"
        print_info "• Target: $target"
        print_info "• Build time: ~15-45 minutes"
        print_info "• Result: New firmware files in build/bin/targets/"
        echo
        
        print_critical "🚨 ALL EXISTING BUILD DATA WILL BE LOST 🚨"
        echo
        
        # FIRST CONFIRMATION - Basic safety check
        local confirmation=""
        while [[ "$confirmation" != "yes" && "$confirmation" != "no" ]]; do
            echo -n "Type 'yes' to continue with build or 'no' to cancel: "
            read -r confirmation
            confirmation=$(echo "$confirmation" | tr '[:upper:]' '[:lower:]')
        done
        
        if [[ "$confirmation" == "no" ]]; then
            print_info "Build cancelled by user"
            print_info ""
            print_info "Alternative options:"
            print_info "• Use 'lime clean' to selectively clean build artifacts"
            print_info "• Backup existing firmware: cp build/bin/targets/*/*.bin ~/firmware-backup/"
            print_info "• Use 3-stage development: 'lime rebuild' (Stage 2) or 'lime rebuild incremental --multi' (Stage 3)"
            exit 0
        fi
        
        # SECOND CONFIRMATION - Double safety for destructive operation
        echo
        print_warning "⚠️  DOUBLE CONFIRMATION REQUIRED ⚠️"
        print_warning "You are about to permanently delete:"
        if [[ -d "$BUILD_DIR" ]]; then
            local build_size=$(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1 || echo "unknown size")
            print_warning "• Build directory: $build_size of build data"
        fi
        if ls "$BUILD_DIR/bin/targets"/*/*.bin &>/dev/null 2>&1; then
            local firmware_count=$(ls "$BUILD_DIR/bin/targets"/*/*.bin 2>/dev/null | wc -l)
            print_warning "• $firmware_count firmware files"
        fi
        echo
        print_critical "⚠️  FINAL CONFIRMATION: This action CANNOT be undone ⚠️"
        
        local final_confirmation=""
        while [[ "$final_confirmation" != "DELETE" && "$final_confirmation" != "cancel" ]]; do
            echo -n "Type 'DELETE' (in capitals) to confirm deletion or 'cancel' to abort: "
            read -r final_confirmation
        done
        
        if [[ "$final_confirmation" == "cancel" ]]; then
            print_info "Build cancelled at final confirmation step"
            print_info ""
            print_info "Data preservation alternatives:"
            print_info "• Archive current build: tar -czf lime-build-backup-$(date +%Y%m%d_%H%M%S).tar.gz build/"
            print_info "• Selective cleanup: 'lime clean --incremental' (preserves downloads and feeds)"
            print_info "• Development rebuild: 'lime rebuild' (faster, preserves more)"
            exit 0
        fi
        
        print_success "✅ Double confirmation completed - proceeding with destructive $target build"
        echo
    fi
}

# Run the confirmation function
confirm_destructive_build "librerouter-v1"
echo "TEST_SUCCESS: Function completed successfully"
CONFIRM_FUNC

    chmod +x "$test_script"
    
    # Run the test with input
    local output=$(echo -e "$input_sequence" | "$test_script" 2>&1 || true)
    
    # Check if output matches expected pattern
    if echo "$output" | grep -q "$expected_pattern"; then
        echo "✅ PASS: $test_name"
        echo "   Expected pattern found: $expected_pattern"
    else
        echo "❌ FAIL: $test_name"
        echo "   Expected pattern: $expected_pattern"
        echo "   Actual output:"
        echo "$output" | sed 's/^/     /'
    fi
    
    rm -f "$test_script"
    rm -rf "/tmp/test_build"
}

echo "🧪 Double Confirmation Logic Tests"
echo "=================================="

# Test 1: First confirmation - user says 'no'
test_confirmation_function \
    "First confirmation rejection" \
    "no" \
    "Build cancelled by user"

# Test 2: First 'yes', second 'cancel'
test_confirmation_function \
    "Second confirmation rejection" \
    "yes\ncancel" \
    "Build cancelled at final confirmation step"

# Test 3: First 'yes', invalid second input, then 'cancel'
test_confirmation_function \
    "Invalid second confirmation input" \
    "yes\ndelete\ncancel" \
    "Build cancelled at final confirmation step"

# Test 4: Successful double confirmation
test_confirmation_function \
    "Successful double confirmation" \
    "yes\nDELETE" \
    "Double confirmation completed"

echo
echo "🎯 Double Confirmation Logic Tests Complete"