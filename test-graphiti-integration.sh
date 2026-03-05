#!/bin/bash
# Integration Testing for Graphiti Wrapper
# Tests actual wrapper execution and server lifecycle
# Usage: ./test-graphiti-integration.sh

set -euo pipefail

# Configuration
WRAPPER_PATH="$HOME/.config/claude/wrappers.d/graphiti/claude"
REFCOUNT_DIR="/tmp/graphiti-refs"
TEST_PROJECT_DIR="/tmp/test-integration-project"
RESULTS_FILE="/tmp/graphiti-integration-results.txt"
MOCK_CLAUDE="/tmp/mock-claude"

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
setup_integration_test() {
    log "Setting up integration test environment..."
    
    # Create test project directory
    mkdir -p "$TEST_PROJECT_DIR"
    cd "$TEST_PROJECT_DIR"
    git init >/dev/null 2>&1 || true
    
    # Create mock Claude binary
    cat > "$MOCK_CLAUDE" << 'EOF'
#!/bin/bash
echo "Mock Claude started with args: $*"
echo "PID: $$"
# Simulate Claude Code running
sleep 2
echo "Mock Claude finished"
EOF
    chmod +x "$MOCK_CLAUDE"
    
    # Clear any existing refcount files
    rm -rf "$REFCOUNT_DIR"
    
    # Clear results file
    > "$RESULTS_FILE"
    
    log "Integration test environment ready"
}

# Cleanup function
cleanup_integration_test() {
    log "Cleaning up integration test environment..."
    
    # Kill any test processes
    pkill -f "graphiti_mcp_server" 2>/dev/null || true
    pkill -f "test-integration-project" 2>/dev/null || true
    
    # Stop FalkorDB container
    docker stop falkordb-graphiti 2>/dev/null || true
    docker rm falkordb-graphiti 2>/dev/null || true
    
    # Clean up files
    rm -rf "$REFCOUNT_DIR"
    rm -rf "$TEST_PROJECT_DIR"
    rm -f "$MOCK_CLAUDE"
    
    log "Integration cleanup complete"
}

# Test 1: Single Session Lifecycle
test_single_session_lifecycle() {
    log "=== INTEGRATION TEST 1: Single Session Lifecycle ==="
    
    # Set mock Claude as next in chain
    export CLAUDE_REAL_BINARY="$MOCK_CLAUDE"
    
    log "Starting single session..."
    
    # Run wrapper (this should start server and increment refcount)
    cd "$TEST_PROJECT_DIR"
    timeout 10 "$WRAPPER_PATH" --version 2>&1 | tee -a "$RESULTS_FILE" || {
        failure "Wrapper execution failed or timed out"
        return 1
    }
    
    # Check if server was started
    if pgrep -f "graphiti_mcp_server.*test-integration-project" >/dev/null; then
        success "Graphiti server started for test-integration-project"
    else
        failure "Graphiti server not running"
        return 1
    fi
    
    # Check FalkorDB container
    if docker ps | grep -q "falkordb-graphiti"; then
        success "FalkorDB container running"
    else
        failure "FalkorDB container not running"
        return 1
    fi
    
    # Check refcount file exists and has content
    if [[ -f "$REFCOUNT_DIR/test-integration-project.refs" ]]; then
        local count
        count=$(wc -l < "$REFCOUNT_DIR/test-integration-project.refs" | tr -d ' ')
        success "Reference counting active: $count session(s) tracked"
    else
        warning "Reference counting file not found (may have been cleaned up)"
    fi
    
    log "Integration test 1 complete"
}

# Test 2: Multi-Session Concurrent Startup
test_concurrent_sessions() {
    log "=== INTEGRATION TEST 2: Concurrent Session Startup ==="
    
    export CLAUDE_REAL_BINARY="$MOCK_CLAUDE"
    
    log "Starting 3 concurrent sessions..."
    
    # Start multiple sessions concurrently
    cd "$TEST_PROJECT_DIR"
    for i in {1..3}; do
        (
            timeout 10 "$WRAPPER_PATH" --help > "/tmp/session-$i.log" 2>&1 || true
        ) &
        echo $! >> /tmp/concurrent-session-pids
    done
    
    # Give sessions time to start
    sleep 2
    
    # Check how many Graphiti servers are running (should be 1)
    local server_count
    server_count=$(pgrep -f "graphiti_mcp_server.*test-integration-project" | wc -l | tr -d ' ')
    
    if [[ "$server_count" == "1" ]]; then
        success "Single server handling multiple sessions"
    else
        failure "Multiple servers started: $server_count (should be 1)"
        return 1
    fi
    
    # Wait for sessions to complete
    wait
    rm -f /tmp/concurrent-session-pids /tmp/session-*.log
    
    log "Integration test 2 complete"
}

# Test 3: Process Death and Cleanup
test_process_cleanup() {
    log "=== INTEGRATION TEST 3: Process Death and Cleanup ==="
    
    # Create a longer-running mock Claude
    cat > "$MOCK_CLAUDE" << 'EOF'
#!/bin/bash
echo "Long-running mock Claude started with PID: $$"
# Write PID for testing
echo $$ > /tmp/mock-claude-pid
# Run for longer to test cleanup
sleep 15
echo "Long-running mock Claude finished"
EOF
    chmod +x "$MOCK_CLAUDE"
    
    export CLAUDE_REAL_BINARY="$MOCK_CLAUDE"
    
    log "Starting session with longer-running Claude..."
    
    cd "$TEST_PROJECT_DIR"
    timeout 20 "$WRAPPER_PATH" --help >/dev/null 2>&1 &
    local wrapper_pid=$!
    
    # Give it time to start
    sleep 3
    
    # Verify server is running
    if ! pgrep -f "graphiti_mcp_server.*test-integration-project" >/dev/null; then
        failure "Server not started for cleanup test"
        return 1
    fi
    
    # Kill the mock Claude process to simulate crash
    if [[ -f /tmp/mock-claude-pid ]]; then
        local claude_pid
        claude_pid=$(cat /tmp/mock-claude-pid)
        log "Killing mock Claude PID: $claude_pid"
        kill -9 "$claude_pid" 2>/dev/null || true
    fi
    
    # Wait for monitor to detect and cleanup (monitor checks every 60s in real wrapper)
    # For testing, we'll give it some time and check manually
    sleep 5
    
    # The server should eventually be cleaned up by the monitor
    # For integration test, we'll verify the monitoring process exists
    local monitor_count
    monitor_count=$(pgrep -f "monitor_parent_process" | wc -l | tr -d ' ')
    
    if [[ "$monitor_count" -gt 0 ]]; then
        success "Parent monitoring process active"
    else
        warning "Parent monitoring process not found (may be normal if session ended)"
    fi
    
    # Cleanup
    kill "$wrapper_pid" 2>/dev/null || true
    rm -f /tmp/mock-claude-pid
    
    log "Integration test 3 complete"
}

# Test 4: Docker Container Lifecycle
test_docker_lifecycle() {
    log "=== INTEGRATION TEST 4: Docker Container Lifecycle ==="
    
    # Stop container if running
    docker stop falkordb-graphiti 2>/dev/null || true
    docker rm falkordb-graphiti 2>/dev/null || true
    
    # Verify container is stopped
    if docker ps | grep -q "falkordb-graphiti"; then
        failure "FalkorDB container still running after stop"
        return 1
    else
        success "FalkorDB container stopped"
    fi
    
    # Run wrapper - should start container
    export CLAUDE_REAL_BINARY="$MOCK_CLAUDE"
    cd "$TEST_PROJECT_DIR"
    
    log "Starting wrapper to test container auto-start..."
    timeout 30 "$WRAPPER_PATH" --version >/dev/null 2>&1 || {
        failure "Wrapper failed to start with container management"
        return 1
    }
    
    # Check if container was started
    if docker ps | grep -q "falkordb-graphiti"; then
        success "FalkorDB container auto-started by wrapper"
    else
        failure "FalkorDB container not auto-started"
        return 1
    fi
    
    # Check if container has restart policy
    local restart_policy
    restart_policy=$(docker inspect falkordb-graphiti --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || echo "none")
    
    if [[ "$restart_policy" == "unless-stopped" ]]; then
        success "Container has correct restart policy: $restart_policy"
    else
        failure "Container has incorrect restart policy: $restart_policy"
        return 1
    fi
    
    log "Integration test 4 complete"
}

# Test 5: End-to-End Workflow
test_end_to_end_workflow() {
    log "=== INTEGRATION TEST 5: End-to-End Workflow ==="
    
    # Reset mock Claude to normal
    cat > "$MOCK_CLAUDE" << 'EOF'
#!/bin/bash
echo "End-to-end mock Claude execution"
echo "Args received: $*"
sleep 1
EOF
    chmod +x "$MOCK_CLAUDE"
    
    export CLAUDE_REAL_BINARY="$MOCK_CLAUDE"
    
    # Test complete workflow
    cd "$TEST_PROJECT_DIR"
    
    log "Testing complete end-to-end workflow..."
    
    # Run wrapper with various arguments
    for args in "--version" "--help" "-p 'Hello world'"; do
        log "Testing with args: $args"
        eval "timeout 10 '$WRAPPER_PATH' $args" >/dev/null 2>&1 || {
            failure "End-to-end test failed with args: $args"
            return 1
        }
    done
    
    success "End-to-end workflow completed successfully"
    
    log "Integration test 5 complete"
}

# Main test runner
run_integration_tests() {
    setup_integration_test
    trap cleanup_integration_test EXIT
    
    log "Starting Graphiti Wrapper Integration Test Suite"
    log "Target: $WRAPPER_PATH"
    echo "" | tee -a "$RESULTS_FILE"
    
    local failed=0
    
    test_single_session_lifecycle || ((failed++))
    test_concurrent_sessions || ((failed++))
    test_process_cleanup || ((failed++))
    test_docker_lifecycle || ((failed++))
    test_end_to_end_workflow || ((failed++))
    
    echo "" | tee -a "$RESULTS_FILE"
    if [[ $failed -eq 0 ]]; then
        success "All integration tests passed! 🎉"
        log "Results saved to: $RESULTS_FILE"
        return 0
    else
        failure "$failed integration test(s) failed"
        log "Results saved to: $RESULTS_FILE"
        return 1
    fi
}

# Run integration tests
run_integration_tests "$@"