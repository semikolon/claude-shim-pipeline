# Claude Shim Pipeline

A composable shim architecture for extending Claude Code with multiple tool integrations (CCR, Serena, etc.) through transparent PATH interception.

## 🚀 Quick Start

```bash
# Install (assumes you have claude, ccr, and uvx installed)
./install.sh

# Use normally - shims are transparent
claude -p "Hello world"
# ✨ Claude Code shims active: ccr, serena

# Skip CCR in native mode  
claude --native --add-dir ~/project
# ✨ Claude Code shims active: serena, ccr (skipping in --native mode)
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
    F[Stage 1: Serena Wrapper] 
    G[Real Claude Binary]
    
    A --> B --> C --> D
    D --> E --> F --> G
    
    style A fill:#e1f5fe
    style G fill:#f3e5f5
    style D fill:#fff3e0
```

### Key Design Principles

1. **Zero Configuration**: Works automatically once installed - no per-project setup needed
2. **Transparent Operation**: User runs `claude` normally, shims work invisibly  
3. **Composable Pipeline**: Easy to add/remove/reorder tools through wrapper system
4. **Safe Fallbacks**: Missing tools are skipped gracefully, always reaches real Claude
5. **Mode Support**: `--native` flag bypasses selected wrappers (like CCR) when needed

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
    └── serena/
        └── claude                # Serena MCP server integration
```

## 🔄 Execution Flow

### Standard Mode (`claude -p "hello"`)

1. **PATH Resolution**: System finds `~/.config/claude/shims/claude` first
2. **Shim Forwarding**: Shim calls `~/.config/claude/libexec/claude-dispatcher "claude" -p "hello"`
3. **Pipeline Orchestration**: Dispatcher manages staged execution:
   - **Stage 0**: CCR wrapper processes command, calls dispatcher for next stage
   - **Stage 1**: Serena wrapper starts MCP server, calls real Claude binary
4. **Final Execution**: Real Claude runs with full tool integration active

### Native Mode (`claude --native --add-dir ~/project`)

1. **FLAG Detection**: Dispatcher detects `--native` flag, removes from args
2. **Wrapper Selection**: Only Serena runs (CCR is bypassed)
3. **Execution**: Serena → Real Claude (with CCR skipped)

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
- **Mode Detection**: Handles `--native` flag for selective wrapper bypass
- **Stage Management**: Tracks pipeline progression through environment variables  
- **Wrapper Discovery**: Dynamically finds available wrappers in order
- **Clean Summary**: Shows single line of active shims instead of verbose debug
- **Fallback Safety**: Always reaches real Claude binary even if wrappers fail

### 3. CCR Wrapper (`wrappers.d/ccr/claude`)

**Purpose**: Integrate Claude Code Router for model routing and request manipulation

**Key Features**:
- **Service Management**: Auto-starts CCR service if needed
- **Path Handling**: Pipeline vs standalone mode path management
- **Graceful Fallback**: Passes through if CCR unavailable

### 4. Serena Wrapper (`wrappers.d/serena/claude`)

**Purpose**: Auto-manage Serena MCP servers per project

**Key Features**:
- **Project Detection**: Uses git root or current directory
- **Automatic Startup**: Launches Serena MCP server on unique ports (9000-9999)
- **Process Management**: Uses uvx + nohup for reliable backgrounding
- **Health Checking**: Fast `/dev/tcp` port connectivity tests (avoids SSE hangs)
- **File Locking**: Prevents race conditions with concurrent `claude` calls
- **Cache System**: Reuses existing healthy servers per project

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

- **GraphQL Integration**: Add `graphiti` wrapper for advanced memory
- **More Commands**: Extend to `cursor`, `code`, etc. 
- **Configuration**: YAML config for wrapper order/settings
- **Logging**: Optional structured logging for debugging
- **Health Dashboard**: Web UI for monitoring wrapper status

## 🤝 Contributing

1. Fork the repository
2. Create your wrapper in `wrappers.d/toolname/`
3. Update `WRAPPER_ORDER` in dispatcher
4. Test with both standard and native modes
5. Submit pull request with clear description

---

*This shim pipeline enables powerful Claude Code extensibility while maintaining the simple `claude` command interface developers expect.*