# Claude Shim Pipeline

A composable shim architecture for extending Claude Code with multiple tool integrations (CCR, Serena, etc.) through transparent PATH interception.

## 🚀 Quick Start

```bash
# Install (assumes you have claude, ccr, and uvx installed)
./install.sh

# Use normally - shims are transparent (CCR skipped by default)
claude -p "Hello world"
# ✨ Claude Code shims active: serena, ccr (skipping, use --ccr to enable)

# Enable CCR with --ccr flag
claude --ccr --add-dir ~/project
# ✨ Claude Code shims active: ccr, serena
```

## 🏗️ Architecture Overview

The shim pipeline implements a **staged interception pattern** where each tool gets its chance to process Claude commands before passing control to the next stage.

```mermaid
flowchart TD
    A[User runs: claude -p "hello"] 
    B[PATH finds: ~/.config/claude/shims/claude]
    C[Shim forwards to: ~/.config/claude/libexec/claude-dispatcher]
    D[Dispatcher determines active wrappers]
    E[Stage 0: CCR Wrapper]
    F[Stage 1: Graphiti Wrapper] 
    G[Stage 2: Serena Wrapper]
    H[Real Claude Binary]
    
    A --> B --> C --> D
    D --> E --> F --> G --> H
    
    style A fill:#e1f5fe
    style G fill:#f3e5f5
    style D fill:#fff3e0
```

### Key Design Principles

1. **Zero Configuration**: Works automatically once installed - no per-project setup needed
2. **Transparent Operation**: User runs `claude` normally, shims work invisibly  
3. **Composable Pipeline**: Easy to add/remove/reorder tools through wrapper system
4. **Safe Fallbacks**: Missing tools are skipped gracefully, always reaches real Claude
5. **Mode Support**: `--ccr` flag enables CCR wrapper (skipped by default)

### Flags the dispatcher adds to session commands

Meta commands (`--version`, `--help`, `mcp`, `update`, `auth`, ...) pass straight through. Every other invocation gets:

- `--dangerously-skip-permissions`, unless `--safe` is given (a safety-net plugin blocks destructive commands)
- `--plugin-dir ~/.claude-plugin`, when that directory exists
- `--mcp-config=~/.claude/mcp-terminal-only.json`, when that file exists: MCP servers for terminal sessions only. Claude Code starts a copy of each stdio server per session, so servers that a desktop client does not need belong here rather than in `~/.claude.json`. The `=` form keeps the multi-value flag from swallowing a prompt that follows.

Each flag is added once, also when a wrapper re-dispatches.

## 📁 File Structure

```
~/.config/claude/
├── README.md                     # This file
├── install.sh                    # Installation script
├── shims/
│   └── claude                    # PATH interception point
├── libexec/
│   ├── claude-shim               # Generic shim template
│   └── claude-dispatcher         # Central pipeline orchestrator
└── wrappers.d/                   # Wrapper implementations
    ├── ccr/
    │   └── claude                # Claude Code Router integration
    ├── graphiti/
    │   └── claude                # Graphiti MCP server integration
    └── serena/
        └── claude                # Serena MCP server integration
```

## 🔄 Execution Flow

### Default Mode (`claude -p "hello"`)

1. **PATH Resolution**: System finds `~/.config/claude/shims/claude` first
2. **Shim Forwarding**: Shim calls `~/.config/claude/libexec/claude-dispatcher "claude" -p "hello"`
3. **Pipeline Orchestration**: Dispatcher manages staged execution:
   - **Stage 0**: CCR is skipped by default
   - **Stage 1**: Graphiti wrapper starts per-project MCP server, passes control
   - **Stage 2**: Serena wrapper starts per-project MCP server, calls real Claude binary
4. **Final Execution**: Real Claude runs with both Graphiti and Serena MCP integrations active

### CCR Mode (`claude --ccr --add-dir ~/project`)

1. **FLAG Detection**: Dispatcher detects `--ccr` flag, removes from args
2. **Wrapper Selection**: Full pipeline runs (CCR + Graphiti + Serena)
3. **Execution**: CCR → Graphiti → Serena → Real Claude
4. **Environment Accumulation**: Each wrapper sets MCP connection variables before passing control

**Key**: All wrappers use `exec` to chain together, so environment variables accumulate. The final Claude Code process receives all MCP server connection info (`SERENA_URL`, `GRAPHITI_GROUP_ID`, etc.)

### Pipeline Stage Tracking

The `CLAUDE_PIPELINE_STAGE` environment variable tracks progression:
- **Stage 0**: CCR wrapper runs, sets `CLAUDE_PIPELINE_STAGE=1`
- **Stage 1**: Serena wrapper runs, calls real Claude
- **Stage 2+**: Pipeline complete, execute real binary

## 🔧 Component Details

### 1. Shim (`~/.config/claude/shims/claude`)

**Purpose**: Intercept all `claude` commands through PATH manipulation

**Key Features**:
- Generic design: can be symlinked for other commands (future: `cursor`, etc.)
- Absolute path forwarding prevents recursion
- Preserves all arguments and environment

### 2. Dispatcher (`~/bin/claude-dispatcher`)

**Purpose**: Orchestrate the wrapper pipeline and manage execution flow

**Key Features**:
- **Mode Detection**: Handles `--ccr` flag for selective wrapper enablement
- **Stage Management**: Tracks pipeline progression through environment variables  
- **Wrapper Discovery**: Dynamically finds available wrappers in order
- **Clean Summary**: Shows single line of active shims instead of verbose debug
- **Fallback Safety**: Always reaches real Claude binary even if wrappers fail

## 🧭 Codex Shim Pipeline (Companion)

Codex uses a parallel shim pipeline under `~/.config/codex/` to keep behavior symmetric with Claude.

**Structure**:
```
~/.config/codex/
├── shims/
│   └── codex                  # PATH interception point
├── libexec/
│   ├── codex-dispatcher       # Central pipeline orchestrator
│   └── graphiti-stdio-launcher # Stdio launcher (uses GRAPHITI_GROUP_ID)
└── wrappers.d/
    └── graphiti/
        └── codex              # Sets GRAPHITI_GROUP_ID (project-aware)
```

**Notes**:
- Codex prefers stdio/streamable HTTP transports; SSE is not reliably supported.
- The Graphiti wrapper mirrors Claude’s project scoping and passes `GRAPHITI_GROUP_ID` into the stdio launcher.

### 3. CCR Wrapper (`wrappers.d/ccr/claude`)

**Purpose**: Integrate Claude Code Router for model routing and request manipulation

**Key Features**:
- **Service Management**: Auto-starts CCR service if needed
- **Path Handling**: Pipeline vs standalone mode path management
- **Graceful Fallback**: Passes through if CCR unavailable

### 4. Graphiti Wrapper (`wrappers.d/graphiti/claude`)

**Purpose**: Auto-manage Graphiti MCP servers with FalkorDB graph database per project

**Key Features**:
- **FalkorDB Auto-Start**: Manages Docker container with `--restart unless-stopped` 
- **Project-Aware GROUP_ID**: Git-based project scoping (e.g., "myproject", "dotfiles")
- **Global Scope Override**: `claude --global-scope` for cross-project sessions
- **PID-Based Parent Tracking**: Auto-cleanup when Claude Code exits (prevents process accumulation)
- **69-254x Performance**: FalkorDB delivers sub-6ms P99 latency vs Neo4j multi-second responses
- **Custom Entity Support**: ProgrammingLanguage, Project, HomeAssistantDevice entities preserved
- **Multi-Day Session Support**: No timeouts, perfect for extended coding sessions
- **Zero Manual Cleanup**: Automatic lifecycle management eliminates zombie processes

### 5. Serena Wrapper (`wrappers.d/serena/claude`)

**Purpose**: Auto-manage Serena MCP servers per project

**Key Features**:
- **Project Detection**: Uses git root or current directory
- **Automatic Startup**: Launches Serena MCP server on unique ports (9000-9999)
- **Process Management**: Uses uvx + nohup for reliable backgrounding
- **Health Checking**: Fast `/dev/tcp` port connectivity tests (avoids SSE hangs)
- **File Locking**: Prevents race conditions with concurrent `claude` calls
- **Cache System**: Reuses existing healthy servers per project
- **🆕 PID-Based Parent Tracking**: Auto-cleanup when Claude Code exits (prevents process accumulation)
- **🆕 Multi-Session Reference Counting**: Handles multiple concurrent sessions per project safely
- **🆕 Zero Manual Cleanup**: Automatic lifecycle management eliminates zombie processes
- **🆕 Atomic Operations**: `flock`-based reference counting prevents race conditions

**✅ Process Accumulation Crisis RESOLVED**: 
- PID-based monitoring detects Claude Code process death
- Reference counting handles multi-session scenarios
- Automatic server shutdown when last session ends
- No more zombie process accumulation

**✅ System Directory Protection IMPLEMENTED**:
- **Automatic Detection**: Blocks Serena when launched from system directories (~, ~/Library, /tmp, etc.)
- **Performance Protection**: Prevents 38GB+ indexing scope and hangs from GitHub Issues #470, #331
- **User-Friendly**: Clear messaging with tips to run from specific project directories
- **Zero False Positives**: Legitimate project directories work normally

**🚨 CRITICAL BUG DISCOVERED (Sept 26, 2025)**: Serena MCP Server Restart Loop
- **Symptom**: Single Serena process consuming 100% CPU for days due to rapid restart cycle
- **Detection**: Look for processes with extremely high CPU time, Activity Monitor shows 16,000+ hours
- **Immediate Action**: Manual termination required (`kill <PID>`) - reference counting prevents auto-cleanup
- **Logs**: Check `~/.cache/serena/<hash>/serena.log` for "Starting MCP server" every few milliseconds
- **Root Cause**: Serena internal bug (unknown trigger) - restart loop in MCP server lifecycle code
- **Architecture Gap**: Current monitors are session-centric (check if Claude alive) not server-centric (check if server healthy)
- **Prevention Plan**: See `~/dotfiles/serena_restart_loop_incident_2025_09_26.md` for:
  - Complete root cause analysis with evidence
  - Architectural decision: where monitoring should be implemented
  - Phase 1: Enhanced monitor_session() with server health checks (1-2 weeks)
  - Phase 2: Optional standalone daemon with full tiered response (4-6 weeks)

**⚠️ Monitoring Recommendations**:
- Periodically check `top` or Activity Monitor for runaway python processes
- Monitor MCP server log sizes (normal logs are <100KB, incident log was 354KB)
- Watch for connection leaks: `lsof -i :9007` should show minimal CLOSED connections
- Reference counting location: `~/.cache/serena/<hash>/refs/sessions.refs`

## 🛠️ Adding New Wrappers

1. **Create Wrapper**: Add executable script at `wrappers.d/TOOLNAME/claude`
2. **Update Order**: Add tool name to `WRAPPER_ORDER` array in dispatcher
3. **Handle Modes**: Add native mode logic if tool should be skipped
4. **Follow Pattern**: Use `CLAUDE_REAL_BINARY` for next execution

Example wrapper template:
```bash
#!/bin/bash
# Find next claude in chain
next_claude="${CLAUDE_REAL_BINARY:-$(PATH="filtered_path" command -v claude)}"

# Do your tool-specific work here
your_tool_setup

# Execute next in chain
exec "$next_claude" "$@"
```

## 🎯 Use Cases

### Development Workflow
- **IDE Integration**: Works with any IDE that calls `claude` 
- **Terminal Usage**: Transparent in all terminal sessions
- **Project Switching**: Automatic per-project Serena instances

### Model Routing (CCR)
- **Model Selection**: Route requests to different models/providers
- **Request Modification**: Transform prompts, add context, etc.
- **Cost Optimization**: Intelligent model selection based on request type

### Code Analysis (Serena)  
- **Semantic Search**: Understanding code structure and relationships
- **Memory System**: Project-specific knowledge graphs
- **IDE Context**: Rich codebase analysis for better responses

## 🔍 Troubleshooting

### Debug Mode
Temporarily enable debug output by editing dispatcher:
```bash
# Add this after line 14 in claude-dispatcher:
echo "🚀 DISPATCHER: $CMD_NAME called with args: $*" >&2
```

### Check Active Shims
```bash
claude --version  # Should show the summary line
```

### Reset Pipeline
```bash
# Clear any stuck pipeline stages
unset CLAUDE_PIPELINE_STAGE
```

### Check Wrapper Health
```bash
# Test CCR
ccr status

# Test Serena
ls ~/.cache/serena/*/port  # Check for running instances

# Test Graphiti
docker ps | grep falkordb-graphiti  # Check FalkorDB container
pgrep -f "graphiti_mcp_server.py"   # Check running servers
```

### MCP Server Process Management

**Health Monitoring Status**: ✅ **Active** (implemented Oct 1, 2025)
- Serena wrapper now monitors CPU/memory every 4 minutes
- Desktop notifications if 2+ sessions detect issues (>100% CPU or >2GB memory)
- See `~/dotfiles/serena_restart_loop_incident_2025_09_26.md` for implementation details

```bash
# Check current process status (should be minimal with new PID tracking)
pgrep -f "serena start-mcp-server" | wc -l    # Count Serena processes
pgrep -f "graphiti_mcp_server.py" | wc -l     # Count Graphiti processes

# Check Serena health monitoring (new)
ps aux | grep "monitor_session" | grep -v grep  # Active monitor processes
ls ~/.cache/serena/*/health.state               # Health check state files

# Check reference counting status
ls -la /tmp/graphiti-refs/                    # Graphiti reference files
find ~/.cache/serena -name "sessions.refs" -exec echo "=== {} ===" \; -exec cat {} \; 2>/dev/null # Serena references

# View active sessions per project
echo "Graphiti projects:"; ls /tmp/graphiti-refs/*.refs 2>/dev/null | while read f; do echo "$(basename "$f" .refs): $(wc -l < "$f") sessions"; done
echo "Serena projects:"; find ~/.cache/serena -name "sessions.refs" -exec sh -c 'echo "$(basename $(dirname $(dirname "$1"))): $(wc -l < "$1") sessions"' _ {} \;

# Manual cleanup (rarely needed with automatic PID tracking)
pkill -f "serena start-mcp-server"            # Kill all Serena servers
pkill -f "graphiti_mcp_server.py"             # Kill all Graphiti servers
pkill -f "group-id PROJECTNAME"               # Kill specific Graphiti project

# Clean up reference counting files (emergency only)
rm -rf /tmp/graphiti-refs/                    # Reset Graphiti references
find ~/.cache/serena -name "sessions.refs" -delete # Reset Serena references
```

### Performance Issues
```bash
# Check for problematic Serena indexing 
tail -f ~/.serena/logs/*/mcp_*.txt | grep "Processing .gitignore file"

# Avoid system directory launches (prevents massive indexing)
# ❌ BAD: claude (from ~ or /Library/*)
# ✅ GOOD: cd ~/myproject && claude
```

## 📚 Technical Background

### Why Shims Instead of Aliases?

**Aliases**: Only work in interactive shells, don't affect IDE/script usage
**Shell Scripts**: Limited by shell-specific features, PATH complexities
**Shims**: Universal interception, work everywhere `claude` is called

### Why Pipeline Stages vs Direct Chaining?

**Direct Chaining**: `wrapper1` → `wrapper2` → `real_claude` 
- Problem: Each wrapper needs to know about next wrapper
- Problem: Complex PATH manipulation to avoid recursion
- Problem: Adding/removing wrappers requires updating all

**Pipeline Stages**: `dispatcher` → `stage0` → `dispatcher` → `stage1` → `real_claude`
- ✅ Clean separation: each wrapper only knows about dispatcher
- ✅ Easy composition: just modify `WRAPPER_ORDER` array  
- ✅ Graceful degradation: missing wrappers are auto-skipped

### Why Environment Variables for State?

Process inheritance ensures stage information survives across `exec` calls, enabling stateless wrappers that don't need complex state management.

## 🚀 Future Extensions

### High Priority
- **Performance Monitoring**: Add metrics collection for wrapper performance and resource usage
- **Enhanced Logging**: Add structured logging for debugging complex wrapper interactions
- **Health Dashboard**: Web UI for monitoring wrapper status and process lifecycle

### Medium Priority  
- **More Commands**: Extend shim pattern to `cursor`, `code`, etc.
- **Configuration**: YAML config for wrapper order/settings
- **Health Dashboard**: Web UI for monitoring wrapper status and process accumulation
- **Logging**: Optional structured logging for debugging complex wrapper interactions

### Low Priority
- **Magic MCP Integration**: Add wrapper for AI-powered React component generation
- **SuperClaude Integration**: Framework orchestration wrapper for complex development workflows

## 🤝 Contributing

1. Fork the repository
2. Create your wrapper in `wrappers.d/toolname/`
3. Update `WRAPPER_ORDER` in dispatcher
4. Test with both standard and native modes
5. Submit pull request with clear description

## 🎯 Production Architecture (September 2025)

**Enterprise-grade MCP server lifecycle management** with automatic process cleanup and cross-platform compatibility.

### Key Capabilities
- **Multi-wrapper Pipeline**: CCR → Graphiti → Serena → Claude with proper environment variable propagation
- **Automatic Process Management**: PID-based session tracking prevents server accumulation
- **System Protection**: Blocks indexing in system directories (prevents 38GB+ scope issues)
- **Zero Dependencies**: Portable `mkdir` locking and `lsof` health checks work on any Unix system
- **Reference Counting**: Multi-session support with atomic cleanup when last session exits

### Technical Foundation  
- **Session Tracking**: `session_pid=$$` approach survives exec boundaries reliably
- **Pipeline Re-dispatch**: Wrappers chain through dispatcher for proper composition
- **Atomic Operations**: Race-condition-free server startup and reference management
- **Health Monitoring**: Fast port connectivity tests avoid SSE streaming hangs

Production-ready infrastructure suitable for public distribution with comprehensive process lifecycle management.

---

*This shim pipeline enables powerful Claude Code extensibility while maintaining the simple `claude` command interface developers expect.*
