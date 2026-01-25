# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Installation and Setup

Install the shim pipeline:
```bash
./install.sh
```

The installer uses Gum for a beautiful TUI experience. If Gum is not installed, it falls back to basic prompts.

## Development Commands

### Installation
- `./install.sh` - Interactive installer with wrapper selection
- `./install.sh` (fallback mode) - Basic installer when Gum unavailable

### Testing the Pipeline
```bash
# Test basic functionality (default: graphiti wrapper, CCR skipped)
claude --version
# Should show: ✨ Claude Code: 🔓 YOLO mode · SHIMS: graphiti (global and per-project memory) · T✓G✓

# Verify PATH order (shim must be first)
which -a claude | head -2
# Expected:
# ~/.config/claude/shims/claude   ← FIRST
# ~/.local/bin/claude             ← Native binary
```

### Debugging
```bash
# Enable debug logging
CLAUDE_DEBUG=1 claude --version
cat /tmp/claude-shims-debug.log

# Check Graphiti daemon status (shown in status line as G✓/G✗)
pgrep -f graphiti_mcp_server

# Reset pipeline stages if stuck
unset CLAUDE_PIPELINE_STAGE
```

## Architecture Overview

The Claude Shim Pipeline implements a **staged interception pattern** where each tool gets its chance to process Claude commands before passing control to the next stage.

### Core Components

1. **Shim (`shims/claude`)** - PATH interception point that forwards all calls to the dispatcher
2. **Dispatcher (`libexec/claude-dispatcher`)** - Central orchestrator that manages the wrapper pipeline
3. **Wrappers (`wrappers.d/*/claude`)** - Tool-specific integrations (CCR, Serena, etc.)

### Execution Flow

**Default Mode:**
```
User calls `claude` → PATH finds shim → Dispatcher → All wrappers except CCR → Real Claude
```

**CCR Mode (`--ccr` flag):**
```
User calls `claude --ccr` → PATH finds shim → Dispatcher → CCR wrapper → Serena wrapper → Real Claude
```

### Pipeline Stage Management

The `CLAUDE_PIPELINE_STAGE` environment variable tracks progression through the wrapper chain:
- Stage 0: CCR wrapper runs, sets `CLAUDE_PIPELINE_STAGE=1`
- Stage 1: Serena wrapper runs, calls real Claude
- Stage 2+: Pipeline complete, execute real binary

### Wrapper Discovery

Wrappers are executed in the order defined by `WRAPPER_ORDER` array in the dispatcher:
```bash
WRAPPER_ORDER=("ccr" "graphiti")  # ccr first, then graphiti (serena disabled 2025-12)
```

## Key Design Principles

1. **Zero Configuration** - Works automatically once installed, no per-project setup needed
2. **Transparent Operation** - User runs `claude` normally, shims work invisibly
3. **Composable Pipeline** - Easy to add/remove/reorder tools through wrapper system
4. **Safe Fallbacks** - Missing tools are skipped gracefully, always reaches real Claude
5. **Mode Support** - `--ccr` flag enables CCR wrapper (skipped by default)

## File Structure

```
~/.config/claude/
├── install.sh                    # Installation script
├── shims/
│   └── claude                    # PATH interception point
├── libexec/
│   ├── claude-shim               # Generic shim template
│   └── claude-dispatcher         # Central pipeline orchestrator
└── wrappers.d/                   # Wrapper implementations
    ├── ccr/
    │   └── claude                # Claude Code Router (--ccr flag)
    └── graphiti/
        └── claude                # Graphiti GROUP_ID injection
```

## Wrapper Development

### Adding New Wrappers

1. Create executable script at `wrappers.d/TOOLNAME/claude`
2. Update `WRAPPER_ORDER` array in dispatcher
3. Handle native mode logic if tool should be skipped
4. Follow the wrapper pattern using `CLAUDE_REAL_BINARY`

### Wrapper Pattern

```bash
#!/bin/bash
# Find next claude in chain
next_claude="${CLAUDE_REAL_BINARY:-$(PATH="filtered_path" command -v claude)}"

# Do your tool-specific work here
your_tool_setup

# Execute next in chain
exec "$next_claude" "$@"
```

## Integration Details

### CCR (Claude Code Router)
- **Purpose**: Routes requests to different models/providers
- **Default Mode**: Skipped by default (must use `--ccr` flag to enable)
- **Fallback**: Passes through if CCR unavailable

### Graphiti (Knowledge Graph)
- **Purpose**: Sets per-project GROUP_ID for knowledge graph isolation
- **Features**:
  - Project detection using git root or current directory
  - Exports `GRAPHITI_GROUP_ID` based on project name
  - Uses FalkorDBLite (embedded, no Docker needed)
- **Global scope**: Use `--global-scope` flag for cross-project memory

## Architecture Decisions

### Why Shims Instead of Aliases?
- **Aliases**: Only work in interactive shells, don't affect IDE/script usage
- **Shell Scripts**: Limited by shell-specific features, PATH complexities
- **Shims**: Universal interception, work everywhere `claude` is called

### Why Pipeline Stages vs Direct Chaining?
- **Direct Chaining Problems**: Each wrapper needs to know about next wrapper, complex PATH manipulation
- **Pipeline Benefits**: Clean separation, easy composition, graceful degradation

### PATH Ordering (Critical!)
The shims directory MUST appear BEFORE the real binary in PATH. Common mistake: adding `~/.local/bin` to PATH AFTER the shims export pushes it to the front, bypassing shims entirely.

**Correct order in ~/.zshrc**:
```bash
export PATH="$HOME/.local/bin:$PATH"      # Real binary location
export PATH="$HOME/.config/claude/shims:$PATH"  # MUST be last (ends up first)
```

**Verify with**: `which -a claude | head -2` - shims directory should be first.