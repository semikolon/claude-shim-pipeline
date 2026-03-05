#!/bin/bash
# Comprehensive Testing Suite for Graphiti Wrapper
# Validates PID-based tracking and reference counting system
# Usage: ./test-graphiti-wrapper.sh [phase_number|all]

set -euo pipefail

# Configuration
WRAPPER_PATH="$HOME/.config/claude/wrappers.d/graphiti/claude"
REFCOUNT_DIR="/tmp/graphiti-refs"
TEST_PROJECT_DIR="/tmp/test-graphiti-project"
RESULTS_FILE="/tmp/graphiti-test-results.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*" | tee -a "$RESULTS_FILE"
}

success() {
    echo -e "${GREEN}✅ PASS:${NC} $*" | tee -a "$RESULTS_FILE"
}

failure() {
    echo -e "${RED}❌ FAIL:${NC} $*" | tee -a "$RESULTS_FILE"
}

warning() {
    echo -e "${YELLOW}⚠️  WARN:${NC} $*" | tee -a "$RESULTS_FILE"
}

# Setup function
setup_test_environment() {
    log "Setting up test environment..."
    
    # Create test project directory
    mkdir -p "$TEST_PROJECT_DIR"
    cd "$TEST_PROJECT_DIR"
    
    # Initialize as git repo for GROUP_ID detection
    git init >/dev/null 2>&1 || true
    
    # Clear any existing refcount files
    rm -rf "$REFCOUNT_DIR"
    
    # Clear results file
    > "$RESULTS_FILE"
    
    log "Test environment ready"
}

# Cleanup function
cleanup_test_environment() {
    log "Cleaning up test environment..."
    
    # Kill any test processes
    pkill -f "test-graphiti-project" 2>/dev/null || true
    
    # Clean up refcount files
    rm -rf "$REFCOUNT_DIR"
    
    # Remove test directory
    rm -rf "$TEST_PROJECT_DIR"
    
    log "Cleanup complete"
}

# Phase 1: PID Detection Accuracy
test_pid_detection() {
    log "=== PHASE 1: PID Detection Accuracy ==="
    
    # Source the wrapper functions
    source "$WRAPPER_PATH" 2>/dev/null || {
        failure "Cannot source wrapper functions"
        return 1
    }
    
    # Test find_claude_code_pid function
    log "Testing find_claude_code_pid function..."
    
    # Create a mock process tree
    bash -c '
        # Simulate dispatcher calling wrapper
        echo $PPID > /tmp/test-parent-pid
        echo $$ > /tmp/test-current-pid
        sleep 2
    ' &
    local mock_pid=$!
    sleep 0.5
    
    # Test PID detection
    local detected_pid
    detected_pid=$(find_claude_code_pid)
    
    kill $mock_pid 2>/dev/null || true
    
    if [[ "$detected_pid" =~ ^[0-9]+$ ]] && [[ "$detected_pid" -ne 1 ]]; then
        success "PID detection returned valid PID: $detected_pid"
    else
        failure "PID detection failed or returned fallback PID 1: $detected_pid"
        return 1
    fi
    
    log "Phase 1 complete"
}

# Phase 2: Reference Counting Logic
test_reference_counting() {
    log "=== PHASE 2: Reference Counting Logic ==="
    
    local test_group="test-graphiti-project"
    
    # Test increment/decrement functions
    log "Testing reference counting functions..."
    
    # Source functions
    source "$WRAPPER_PATH" 2>/dev/null || {
        failure "Cannot source wrapper functions"
        return 1
    }
    
    # Test increment
    increment_refcount "$test_group" "12345"
    increment_refcount "$test_group" "67890"
    
    local count
    count=$(get_refcount "$test_group")
    if [[ "$count" == "2" ]]; then
        success "Reference increment works: $count sessions"
    else
        failure "Reference increment failed: expected 2, got $count"
        return 1
    fi
    
    # Test decrement (should not trigger cleanup)
    if decrement_refcount "$test_group" "12345"; then
        count=$(get_refcount "$test_group")
        if [[ "$count" == "1" ]]; then
            success "Reference decrement works: $count session remaining"
        else
            failure "Reference decrement failed: expected 1, got $count"
            return 1
        fi
    else
        failure "Decrement returned cleanup signal too early"
        return 1
    fi
    
    # Test final decrement (should trigger cleanup)
    if ! decrement_refcount "$test_group" "67890"; then
        count=$(get_refcount "$test_group")
        if [[ "$count" == "0" ]]; then
            success "Final decrement triggered cleanup signal"
        else
            failure "Final decrement failed: expected 0, got $count"
            return 1
        fi
    else
        failure "Final decrement should have returned cleanup signal"
        return 1
    fi
    
    log "Phase 2 complete"
}

# Phase 3: Multi-Session Simulation
test_multisession_behavior() {
    log "=== PHASE 3: Multi-Session Simulation ==="
    
    local test_group="test-graphiti-project"
    
    # Start multiple simulated sessions concurrently
    log "Starting 3 concurrent sessions..."
    
    for i in {1..3}; do
        (
            # Simulate session startup
            source "$WRAPPER_PATH" 2>/dev/null
            increment_refcount "$test_group" "$$"
            sleep 2
            # Session ends - decrement should be handled by monitor
        ) &
        echo $! >> /tmp/test-session-pids
    done
    
    sleep 1
    
    # Check concurrent refcount
    source "$WRAPPER_PATH" 2>/dev/null
    local count
    count=$(get_refcount "$test_group")
    if [[ "$count" == "3" ]]; then
        success "Concurrent session tracking: $count active sessions"
    else
        failure "Concurrent session tracking failed: expected 3, got $count"
        return 1
    fi
    
    # Wait for sessions to end
    wait
    
    # Manually simulate cleanup for each PID
    while read -r pid; do
        decrement_refcount "$test_group" "$pid" || true
    done < /tmp/test-session-pids
    
    rm -f /tmp/test-session-pids
    
    # Final count should be 0
    count=$(get_refcount "$test_group")
    if [[ "$count" == "0" ]]; then
        success "Session cleanup completed: $count sessions remaining"
    else
        failure "Session cleanup incomplete: $count sessions still tracked"
        return 1
    fi
    
    log "Phase 3 complete"
}

# Phase 4: Process Monitoring Simulation
test_process_monitoring() {
    log "=== PHASE 4: Process Monitoring Simulation ==="
    
    local test_group="test-graphiti-project"
    
    # Create a long-running process to monitor
    bash -c 'sleep 30' &
    local test_pid=$!
    
    log "Started test process PID: $test_pid"
    
    # Source functions and increment refcount
    source "$WRAPPER_PATH" 2>/dev/null
    increment_refcount "$test_group" "$test_pid"
    
    # Verify process is being tracked
    local count
    count=$(get_refcount "$test_group")
    if [[ "$count" == "1" ]]; then
        success "Process being tracked: PID $test_pid"
    else
        failure "Process tracking failed"
        return 1
    fi
    
    # Kill the process to simulate crash
    kill "$test_pid" 2>/dev/null || true
    sleep 1
    
    # Manually simulate what monitor would do
    if ! kill -0 "$test_pid" 2>/dev/null; then
        if ! decrement_refcount "$test_group" "$test_pid"; then
            success "Process death triggered cleanup signal"
        else
            failure "Process death should have triggered cleanup"
            return 1
        fi
    else
        failure "Test process still running when it should be dead"
        return 1
    fi
    
    log "Phase 4 complete"
}

# Phase 5: Race Condition Testing
test_race_conditions() {
    log "=== PHASE 5: Race Condition Testing ==="
    
    local test_group="test-graphiti-project"
    
    # Start many concurrent operations
    log "Testing race conditions with 10 concurrent operations..."
    
    for i in {1..10}; do
        (
            source "$WRAPPER_PATH" 2>/dev/null
            increment_refcount "$test_group" "race-$$-$i"
            sleep 0.1
            decrement_refcount "$test_group" "race-$$-$i" || true
        ) &
    done
    
    # Wait for all operations to complete
    wait
    
    # Check final state - should be 0
    source "$WRAPPER_PATH" 2>/dev/null
    local count
    count=$(get_refcount "$test_group")
    if [[ "$count" == "0" ]]; then
        success "Race condition test passed: clean final state"
    else
        failure "Race condition test failed: $count references leaked"
        return 1
    fi
    
    log "Phase 5 complete"
}

# Main test runner
run_tests() {
    local phase="${1:-all}"
    
    setup_test_environment
    trap cleanup_test_environment EXIT
    
    log "Starting Graphiti Wrapper Test Suite"
    log "Target: $WRAPPER_PATH"
    log "Mode: $phase"
    echo "" | tee -a "$RESULTS_FILE"
    
    local failed=0
    
    case "$phase" in
        "1"|"pid")
            test_pid_detection || ((failed++))
            ;;
        "2"|"refcount")
            test_reference_counting || ((failed++))
            ;;
        "3"|"multisession")
            test_multisession_behavior || ((failed++))
            ;;
        "4"|"monitoring")
            test_process_monitoring || ((failed++))
            ;;
        "5"|"race")
            test_race_conditions || ((failed++))
            ;;
        "all")
            test_pid_detection || ((failed++))
            test_reference_counting || ((failed++))
            test_multisession_behavior || ((failed++))
            test_process_monitoring || ((failed++))
            test_race_conditions || ((failed++))
            ;;
        *)
            failure "Unknown phase: $phase"
            echo "Usage: $0 [1|2|3|4|5|all]"
            exit 1
            ;;
    esac
    
    echo "" | tee -a "$RESULTS_FILE"
    if [[ $failed -eq 0 ]]; then
        success "All tests passed! 🎉"
        log "Results saved to: $RESULTS_FILE"
        return 0
    else
        failure "$failed test(s) failed"
        log "Results saved to: $RESULTS_FILE"
        return 1
    fi
}

# Run tests with provided arguments
run_tests "$@"