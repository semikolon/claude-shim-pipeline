#!/bin/bash
#
# Claude Shim Pipeline Installer
# Beautiful TUI installer for Claude Code extensions using Charm's Gum
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_CONFIG_DIR="$HOME/.config/claude"
LIBEXEC_DIR="$CLAUDE_CONFIG_DIR/libexec"

# Check if gum is available
if ! command -v gum >/dev/null 2>&1; then
    echo "🎀 This installer uses Charm's Gum for a beautiful experience!"
    echo "📦 Install it with: brew install gum"
    echo "🌐 Or visit: https://github.com/charmbracelet/gum"
    echo ""
    echo "Continuing with basic installer..."
    FALLBACK_MODE=true
else
    FALLBACK_MODE=false
fi

# Gum wrappers with fallbacks
gum_style() {
    if [[ "$FALLBACK_MODE" == "true" ]]; then
        echo "$*"
    else
        gum style "$@"
    fi
}

gum_confirm() {
    if [[ "$FALLBACK_MODE" == "true" ]]; then
        read -p "$1 (y/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]]
    else
        gum confirm "$1"
    fi
}

gum_choose() {
    if [[ "$FALLBACK_MODE" == "true" ]]; then
        local prompt="$1"
        shift
        echo "$prompt"
        select opt in "$@"; do
            echo "$opt"
            break
        done
    else
        local prompt="$1"
        shift
        gum choose --header="$prompt" "$@"
    fi
}

gum_spin() {
    if [[ "$FALLBACK_MODE" == "true" ]]; then
        echo "⏳ $2..."
        eval "$1"
    else
        gum spin --spinner dot --title "$2" -- "$1"
    fi
}

# Show welcome screen
show_welcome() {
    gum_style \
        --foreground 212 --border-foreground 212 --border double \
        --align center --width 60 --margin "1 2" --padding "2 4" \
        'Claude Shim Pipeline' '' \
        'A composable architecture for extending Claude Code' \
        'with multiple tool integrations (CCR, Serena, Graphiti)' ''

    gum_style --foreground 246 "✨ Transparent PATH interception"
    gum_style --foreground 246 "🔄 Composable wrapper system" 
    gum_style --foreground 246 "🎯 Zero per-project configuration"
    echo
}

# Check prerequisites
check_prerequisites() {
    gum_spin "sleep 0.5" "Checking system requirements"
    
    local missing_deps=()
    local warnings=()
    
    # Check for real Claude binary
    if ! command -v claude >/dev/null 2>&1; then
        missing_deps+=("claude")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        gum_style --foreground 196 "❌ Missing required dependencies: ${missing_deps[*]}"
        gum_style --foreground 246 "Please install Claude Code first:"
        gum_style --foreground 33 "  npm install -g @anthropic-ai/claude-code"
        exit 1
    fi
    
    gum_style --foreground 46 "✅ Claude Code found"
}

# Show wrapper selection interface
select_wrappers() {
    gum_style --foreground 212 --bold "🎯 Choose Your Integrations"
    echo
    
    local wrappers=()
    
    # CCR Selection
    gum_style --foreground 33 --bold "Claude Code Router (CCR)"
    gum_style --foreground 246 "  • Routes requests to different models/providers"
    gum_style --foreground 246 "  • Intelligent model selection and cost optimization"
    gum_style --foreground 246 "  • Setup: https://github.com/paul-gauthier/claude-code-router"
    
    if gum_confirm "Install CCR wrapper?"; then
        wrappers+=("ccr")
        # Check if CCR is actually installed
        if ! command -v ccr >/dev/null 2>&1; then
            gum_style --foreground 208 "⚠️  CCR not installed yet - wrapper will be installed but won't work until CCR is set up"
        fi
    fi
    echo
    
    # Serena Selection  
    gum_style --foreground 33 --bold "Serena MCP Server"
    gum_style --foreground 246 "  • Semantic code analysis and search"
    gum_style --foreground 246 "  • Project-specific knowledge graphs"
    gum_style --foreground 246 "  • Setup: https://github.com/oraios/serena"
    
    if gum_confirm "Install Serena wrapper?"; then
        wrappers+=("serena")
        # Check if uvx is available (needed for Serena)
        if ! command -v uvx >/dev/null 2>&1; then
            gum_style --foreground 208 "⚠️  uvx not installed - install with: pip install uvx"
        fi
    fi
    echo
    
    # Future: Graphiti
    gum_style --foreground 33 --bold "Graphiti Memory (Coming Soon)"
    gum_style --foreground 246 "  • Advanced knowledge graph memory system"
    gum_style --foreground 246 "  • Persistent conversation context"
    gum_style --foreground 246 "  • Setup: https://github.com/getzep/graphiti"
    gum_style --foreground 100 "  • Will be available in future release"
    echo
    
    export SELECTED_WRAPPERS=("${wrappers[@]}")
    
    if [[ ${#wrappers[@]} -eq 0 ]]; then
        gum_style --foreground 208 "Installing core pipeline only (no wrappers)"
    else
        local wrapper_list=$(IFS=', '; echo "${wrappers[*]}")
        gum_style --foreground 46 "Selected wrappers: $wrapper_list"
    fi
    echo
}

# Create directory structure
setup_directories() {
    gum_spin "mkdir -p '$CLAUDE_CONFIG_DIR'/{shims,libexec,wrappers.d/{ccr,serena,graphiti}}" "Creating directory structure"
    gum_style --foreground 46 "✅ Directory structure ready"
}

# Install core pipeline
install_core_pipeline() {
    gum_style --foreground 212 --bold "🏗️  Installing Core Pipeline"
    echo
    
    # Install dispatcher
    local install_dispatcher="true"
    if [[ -f "$LIBEXEC_DIR/claude-dispatcher" ]]; then
        if gum_confirm "Dispatcher exists. Overwrite?"; then
            install_dispatcher="true"
        else
            install_dispatcher="false"
            gum_style --foreground 100 "Using existing dispatcher"
        fi
    fi
    
    if [[ "$install_dispatcher" == "true" ]]; then
        # If we're running from the repo, copy the existing dispatcher  
        if [[ -f "$SCRIPT_DIR/libexec/claude-dispatcher" ]]; then
            gum_spin "cp '$SCRIPT_DIR/libexec/claude-dispatcher' '$LIBEXEC_DIR/'" "Installing dispatcher"
        else
            # Create dispatcher from template (for fresh installs)
            gum_spin "create_dispatcher_template" "Creating dispatcher template"
        fi
        gum_style --foreground 46 "✅ Dispatcher installed"
    fi
    
    # Install shims
    gum_spin "install_shims_files" "Installing shim system"
    gum_style --foreground 46 "✅ Shim system ready"
}

create_dispatcher_template() {
    cat > "$LIBEXEC_DIR/claude-dispatcher" << 'EOF'
#!/usr/bin/env bash
#
# Claude Dispatcher - Shim-based architecture
# Called by shim: ~/bin/claude-dispatcher "claude" [args...]
#
# Provides consistent execution path: shim → dispatcher → wrapper → real binary
# Supports --native flag to bypass CCR wrapper

set -euo pipefail

# First argument is the command name from the shim
CMD_NAME="$1"
shift

# Configuration
WRAPPER_BASE_DIR="$HOME/.config/claude/wrappers.d"
WRAPPER_ORDER=("ccr" "serena")  # ccr first, then serena

# Check for --native flag and remove it from arguments
ARGS=()
USE_NATIVE=false

for arg in "$@"; do
    if [[ "$arg" == "--native" ]]; then
        USE_NATIVE=true
    else
        ARGS+=("$arg")
    fi
done

# Find the real claude binary (excluding shims and wrappers)
# Create a clean PATH without our managed directories
CLEAN_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v -E "(claude/shims|claude/wrappers)" | tr '\n' ':' | sed 's/:$//')
REAL_CLAUDE=$(PATH="$CLEAN_PATH" command -v claude)

if [[ -z "$REAL_CLAUDE" ]]; then
    echo "❌ DISPATCHER: Error: Real claude binary not found in system PATH" >&2
    exit 1
fi

# Export real claude location for wrappers to use directly
export CLAUDE_REAL_BINARY="$REAL_CLAUDE"

# Build list of active shims
ACTIVE_SHIMS=()
if [[ "$USE_NATIVE" == "true" ]]; then
    # In native mode, only serena runs
    if [[ -x "$WRAPPER_BASE_DIR/serena/$CMD_NAME" ]]; then
        ACTIVE_SHIMS+=("serena")
    fi
    # CCR is skipped in native mode
    if [[ -x "$WRAPPER_BASE_DIR/ccr/$CMD_NAME" ]]; then
        ACTIVE_SHIMS+=("ccr (skipping in --native mode)")
    fi
    # Add future shims here with appropriate native mode handling
else
    # In standard mode, check all available wrappers
    for wrapper in "${WRAPPER_ORDER[@]}"; do
        if [[ -x "$WRAPPER_BASE_DIR/$wrapper/$CMD_NAME" ]]; then
            ACTIVE_SHIMS+=("$wrapper")
        fi
    done
fi

# Display the clean summary line
if [[ ${#ACTIVE_SHIMS[@]} -gt 0 ]]; then
    shim_list=$(IFS=', '; echo "${ACTIVE_SHIMS[*]}")
    echo "✨ Claude Code shims active: $shim_list" >&2
fi

# Find the first available wrapper based on mode and order
WRAPPER_TO_USE=""

if [[ "$USE_NATIVE" == "true" ]]; then
    if [[ -x "$WRAPPER_BASE_DIR/serena/$CMD_NAME" ]]; then
        WRAPPER_TO_USE="$WRAPPER_BASE_DIR/serena/$CMD_NAME"
    fi
else
    # Initialize pipeline stage if not set (starts at 0)
    PIPELINE_STAGE="${CLAUDE_PIPELINE_STAGE:-0}"
    
    # Check if we're still within the wrapper pipeline
    if (( PIPELINE_STAGE < ${#WRAPPER_ORDER[@]} )); then
        # Get current wrapper name from array (generic!)
        WRAPPER_NAME="${WRAPPER_ORDER[PIPELINE_STAGE]}"
        WRAPPER_PATH="$WRAPPER_BASE_DIR/$WRAPPER_NAME/$CMD_NAME"
        
        if [[ -x "$WRAPPER_PATH" ]]; then
            # Execute wrapper with incremented stage for next iteration
            export CLAUDE_PIPELINE_STAGE=$((PIPELINE_STAGE + 1))
            WRAPPER_TO_USE="$WRAPPER_PATH"
        else
            # Skip missing wrapper by incrementing stage and re-dispatching
            export CLAUDE_PIPELINE_STAGE=$((PIPELINE_STAGE + 1))
            exec "$0" "$CMD_NAME" "$@"
        fi
    else
        # End of pipeline - all wrappers have run, use real Claude
        WRAPPER_TO_USE=""
    fi
fi

# Execute the chosen wrapper or fall back to real binary
if [[ -n "$WRAPPER_TO_USE" ]]; then
    exec "$WRAPPER_TO_USE" "${ARGS[@]}"
else
    exec "$REAL_CLAUDE" "${ARGS[@]}"
fi
EOF
    chmod +x "$LIBEXEC_DIR/claude-dispatcher"
}

install_shims_files() {
    # Create the generic shim
    cat > "$CLAUDE_CONFIG_DIR/libexec/claude-shim" << 'EOF'
#!/bin/sh
# Get the command name (e.g., "claude") from how this script was invoked
CMD_NAME=$(basename "$0")
# Execute the main dispatcher with absolute path to avoid recursion
exec "$HOME/.config/claude/libexec/claude-dispatcher" "$CMD_NAME" "$@"
EOF
    chmod +x "$CLAUDE_CONFIG_DIR/libexec/claude-shim"
    # Create the claude-specific shim
    cp "$CLAUDE_CONFIG_DIR/libexec/claude-shim" "$CLAUDE_CONFIG_DIR/shims/claude"
}

# Install selected wrappers
install_selected_wrappers() {
    if [[ ${#SELECTED_WRAPPERS[@]} -eq 0 ]]; then
        gum_style --foreground 100 "No wrappers selected - core pipeline only"
        return
    fi
    
    gum_style --foreground 212 --bold "🔧 Installing Wrappers"
    echo
    
    for wrapper in "${SELECTED_WRAPPERS[@]}"; do
        if [[ -f "$SCRIPT_DIR/wrappers.d/$wrapper/claude" ]]; then
            gum_spin "cp '$SCRIPT_DIR/wrappers.d/$wrapper/claude' '$CLAUDE_CONFIG_DIR/wrappers.d/$wrapper/' && chmod +x '$CLAUDE_CONFIG_DIR/wrappers.d/$wrapper/claude'" "Installing $wrapper wrapper"
            gum_style --foreground 46 "✅ $wrapper wrapper installed"
        else
            gum_style --foreground 208 "⚠️  $wrapper wrapper not found in repository"
        fi
    done
}

# Update PATH
update_path() {
    local path_entry="$CLAUDE_CONFIG_DIR/shims"
    
    # Check if already in PATH
    if echo "$PATH" | grep -q "$path_entry"; then
        gum_style --foreground 100 "Shims already in PATH"
        return
    fi
    
    gum_style --foreground 212 --bold "🔧 Configuring PATH"
    
    # Detect shell and update appropriate config file
    local shell_config=""
    if [[ "$SHELL" == */zsh ]]; then
        shell_config="$HOME/.zshrc"
    elif [[ "$SHELL" == */bash ]]; then
        shell_config="$HOME/.bash_profile"
        [[ ! -f "$shell_config" ]] && shell_config="$HOME/.bashrc"
    else
        gum_style --foreground 208 "Unknown shell: $SHELL"
        gum_style --foreground 246 "Please manually add $path_entry to your PATH"
        return
    fi
    
    gum_spin "echo '' >> '$shell_config' && echo '# Claude Shim Pipeline' >> '$shell_config' && echo 'export PATH=\"$path_entry:\$PATH\"' >> '$shell_config'" "Updating shell configuration"
    gum_style --foreground 46 "✅ PATH configured in $shell_config"
}

# Final verification and celebration
finish_installation() {
    gum_style --foreground 212 --bold "🎉 Installation Complete!"
    echo
    
    # Test installation
    export PATH="$CLAUDE_CONFIG_DIR/shims:$PATH"
    
    if command -v claude >/dev/null 2>&1; then
        gum_style --foreground 46 "✅ Claude shim is accessible"
        
        # Show next steps
        gum_style \
            --foreground 33 --border-foreground 33 --border rounded \
            --align left --width 50 --margin "1 2" --padding "1 2" \
            "Next Steps:" \
            "" \
            "1. Restart terminal or source shell config" \
            "2. Test: claude --version" \
            "3. Should show: ✨ Claude Code shims active"
            
        if [[ ${#SELECTED_WRAPPERS[@]} -gt 0 ]]; then
            echo
            gum_style --foreground 246 "Don't forget to install wrapper dependencies:"
            for wrapper in "${SELECTED_WRAPPERS[@]}"; do
                case "$wrapper" in
                    "ccr")
                        gum_style --foreground 246 "  • CCR: https://github.com/paul-gauthier/claude-code-router"
                        ;;
                    "serena")  
                        gum_style --foreground 246 "  • Serena: pip install uvx"
                        ;;
                esac
            done
        fi
    else
        gum_style --foreground 208 "⚠️  Manual PATH update required"
    fi
    
    echo
    gum_style --foreground 212 "🚀 Happy coding with your enhanced Claude setup!"
}

# Main installation flow
main() {
    clear
    show_welcome
    check_prerequisites
    echo
    select_wrappers
    setup_directories
    install_core_pipeline  
    install_selected_wrappers
    update_path
    finish_installation
}

# Run installer
main "$@"