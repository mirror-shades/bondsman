# Bondsman

A command-line AI assistant that runs entirely on local AI models using Ollama. Absolutely NO internet connectivity is built into this tool - all AI interactions happen locally on your machine, ensuring complete privacy and offline functionality.

## Features

- **Local AI Chat**: Interact with AI models using the `;` prefix
- **Direct Shell Execution**: Run commands directly in your current environment
- **Intelligent Context Management**: AI remembers your command history and system info
- **Command History**: Built-in history with search capabilities
- **Session Management**: Save and recall conversation contexts
- **Error Handling**: Clear status indicators and error messages
- **ANSI Color Support**: Syntax highlighting and visual feedback

## Quick Start

### Prerequisites

- Zig compiler (latest)
- Ollama installed and running

### Installation

1. **Install Ollama** (if not already installed):

   ```bash
   # On macOS
   brew install ollama

   # On Linux
   curl -fsSL https://ollama.ai/install.sh | sh
   ```

2. **Pull the default model**:

   ```bash
   ollama pull qwen2.5-coder:1.5b
   ```

3. **Build Bondsman**:

   ```bash
   zig build
   ```

4. **Run**:
   ```bash
   ./zig-out/bin/bondsman
   ```

## Usage

### Basic Commands

```bash
# Chat with the AI assistant
;explain this error: permission denied

# Ask for command suggestions
;how do I find large files in /var/log?

# Get help with shell scripting
;write a bash script to backup my home directory

# Execute shell commands directly
ls -la
grep -r "TODO" src/

# Bondsman meta-commands
;;help                    # Show bondsman-specific help
;;remember work-session   # Save current session context
;;recall work-session     # Restore a saved session
;;status                  # Show current model and context info
```

### Example Interaction

```
$ ./zig-out/bin/bondsman
Bondsman v0.1.0 - Local AI Shell Assistant
Model: qwen2.5-coder:1.5b | Context: 347 commands loaded

bondsman> ;I'm getting a "command not found" error for a script I just wrote
AI: This usually means one of three things:
1. The script isn't in your PATH
2. The script doesn't have execute permissions
3. You're not running it with the correct path

Try: `chmod +x your-script.sh` then `./your-script.sh`

bondsman> chmod +x deploy.sh
bondsman> ./deploy.sh
Starting deployment...
✓ Deployment complete

bondsman> ;great! now how do I make this script available system-wide?
AI: To make it available system-wide, you can:
1. Move it to `/usr/local/bin/`: `sudo mv deploy.sh /usr/local/bin/deploy`
2. Or add your current directory to PATH: `export PATH=$PATH:$(pwd)`
3. Or create a symlink: `sudo ln -s $(pwd)/deploy.sh /usr/local/bin/deploy`

Option 1 is most common for permanent installation.
```

## Context Management

Bondsman maintains context within and across sessions:

- **Global**: Last 500 commands across all sessions
- **Session**: Last 100 commands in current session
- **System**: OS, shell, and available tools
- **Current**: Working dir, current i/o, error/pass

## Default Model

Uses **qwen2.5-coder:1.5b** by default - a small model (1gb memory and ram) optimized for:

- Shell command help
- Code debugging
- System administration
- Technical Q&A

## Requirements

- Zig compiler (0.14.0)
- Ollama with qwen2.5-coder:1.5b model
- hardware to run chosen the AI model

## Todo

- [ ] `;;` prefix for bondsman-specific commands
- [ ] Tab completion for commands and file paths
- [ ] Fuzzy search through recent command history
- [ ] Model switching (`;;model qwen2.5-coder:7b`, `;;model codellama`)
- [ ] Complete context information display
- [ ] Session management: saving, recalling, forgetting contexts
- [ ] Configuration file support

## License

GPL 2.0
