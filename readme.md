# Bondsman

A command-line AI assistant with which runs off local AI models using Ollama. Absolutely NO internet connectivity is built into this tool. All API calls are done via Ollama's local serve.

## Features

- Chat with the AI assistant using the `;` prefix
- Execute shell commands directly
- Command history
- Error handling and status indicators
- ANSI color support

## Usage

```bash
# Build the project
zig build

# Run the assistant
./zig-out/bin/bondsman

# Inside the assistant:
;hello                 # Chat with the AI
;;help                 # enter with bondsman
```

## Requirements

- Zig compiler
- Ollama

## Proposed context

The following information

### Global context

- last 500 unique commands
- persists between sessions

### System context

- Determined each time program launches
- OS, arch, shell, etc.

### Session context

- doesn't last between launches
- last 100? unique commands
- can be saved with ;;remember <label> and recalled with ;;recall <label>

## Todo

- ;; to write bondsman commands
- autocomplete
- fuzzy find recent commands
- complete context info
- session saving, recalling, forgeting, etc.

## License

OpenGPL 2.0
