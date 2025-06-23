const std = @import("std");
const json = std.json;
const ChildProcess = std.process.Child;
const windows = std.os.windows;
const report = @import("reporting.zig");

// Enable ANSI support for Windows console
fn enableAnsiConsole() !void {
    if (@import("builtin").os.tag == .windows) {
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001); // UTF-8
        const handle = try windows.GetStdHandle(windows.STD_OUTPUT_HANDLE);
        var mode: windows.DWORD = undefined;
        if (windows.kernel32.GetConsoleMode(handle, &mode) != 0) {
            _ = windows.kernel32.SetConsoleMode(handle, mode | windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        }
    }
}

// ANSI Color codes
const ANSI = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
    const cyan = "\x1b[36m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const blue = "\x1b[34m";
    const magenta = "\x1b[35m";
    const red = "\x1b[31m";
    const gray = "\x1b[90m";
    const white = "\x1b[97m";
};

// Box drawing characters (ASCII)
const BOX = struct {
    const top_left = "+";
    const top_right = "+";
    const horizontal = "-";
    const vertical = "|";
    const bottom_left = "+";
    const bottom_right = "+";
};

// Helper function to format text with ANSI colors
fn colorize(allocator: std.mem.Allocator, color: []const u8, text: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ color, text, ANSI.reset });
}

const InputMode = enum {
    Command,
    Chat,
};

const SystemContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    os_name: []const u8,
    shell_path: []const u8,
    arch: []const u8,
    cpu_count: usize,
    hostname: []const u8,
    username: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var env = try std.process.getEnvMap(allocator);
        defer env.deinit();

        // Get shell path from env
        const shell_path = if (env.get("SHELL")) |sh|
            try allocator.dupe(u8, sh)
        else if (env.get("COMSPEC")) |sh|
            try allocator.dupe(u8, sh)
        else
            try allocator.dupe(u8, "unknown");

        // Get OS and architecture information
        const os_name = switch (@import("builtin").os.tag) {
            .windows => try allocator.dupe(u8, "windows"),
            .linux => try allocator.dupe(u8, "linux"),
            .macos => try allocator.dupe(u8, "macos"),
            else => try allocator.dupe(u8, "unknown"),
        };

        const arch = switch (@import("builtin").cpu.arch) {
            .x86_64 => try allocator.dupe(u8, "x86_64"),
            .aarch64 => try allocator.dupe(u8, "aarch64"),
            .arm => try allocator.dupe(u8, "arm"),
            else => try allocator.dupe(u8, "unknown"),
        };

        // Get CPU count
        const cpu_count = try std.Thread.getCpuCount();

        // Get hostname using environment variable first, fallback to computername
        const hostname = if (env.get("COMPUTERNAME")) |name|
            try allocator.dupe(u8, name)
        else
            try allocator.dupe(u8, "unknown");

        // Get username from environment
        const username = if (env.get("USERNAME")) |user|
            try allocator.dupe(u8, user)
        else if (env.get("USER")) |user|
            try allocator.dupe(u8, user)
        else
            try allocator.dupe(u8, "unknown");

        return Self{
            .allocator = allocator,
            .os_name = os_name,
            .shell_path = shell_path,
            .arch = arch,
            .cpu_count = cpu_count,
            .hostname = hostname,
            .username = username,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.os_name);
        self.allocator.free(self.shell_path);
        self.allocator.free(self.arch);
        self.allocator.free(self.hostname);
        self.allocator.free(self.username);
    }

    pub fn formatContext(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(
            allocator,
            \\System Information:
            \\OS: {s}
            \\Architecture: {s}
            \\Shell: {s}
            \\CPU Count: {d}
            \\Hostname: {s}
            \\Username: {s}
            \\
        ,
            .{
                self.os_name,
                self.arch,
                self.shell_path,
                self.cpu_count,
                self.hostname,
                self.username,
            },
        );
    }
};

const CommandContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    cwd: []const u8,
    last_command: ?[]const u8,
    last_status: ?u8,
    env: std.process.EnvMap,

    pub fn init(allocator: std.mem.Allocator) !Self {
        // Get current working directory
        var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = try std.process.getCwd(&cwd_buf);
        const cwd_owned = try allocator.dupe(u8, cwd);

        // Get environment variables
        const env = try std.process.getEnvMap(allocator);

        return Self{
            .allocator = allocator,
            .cwd = cwd_owned,
            .last_command = null,
            .last_status = null,
            .env = env,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.cwd);
        if (self.last_command) |cmd| {
            self.allocator.free(cmd);
        }
        self.env.deinit();
    }

    pub fn formatContext(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(
            allocator,
            \\Session Information:
            \\Current directory: {s}
            \\Last command: {s}
            \\Status: {?d}
            \\
        ,
            .{
                self.cwd,
                self.last_command orelse "none",
                self.last_status,
            },
        );
    }

    pub fn getPrompt(self: *const Self) ![]const u8 {
        const basename = std.fs.path.basename(self.cwd);
        const status_indicator = if (self.last_status) |status|
            if (status == 0)
                try colorize(self.allocator, ANSI.green, "> ")
            else
                try colorize(self.allocator, ANSI.red, "! ")
        else
            try self.allocator.dupe(u8, "");
        defer if (status_indicator.len > 0) self.allocator.free(status_indicator);

        const colored_basename = try colorize(self.allocator, ANSI.blue, basename);
        defer self.allocator.free(colored_basename);

        return try std.fmt.allocPrint(
            self.allocator,
            "\n{s}ᗹ {s} {s}{s}$ {s}",
            .{
                status_indicator,
                colored_basename,
                ANSI.white,
                ANSI.bold,
                ANSI.reset,
            },
        );
    }

    pub fn updateCommand(self: *Self, command: []const u8, status: u8) !void {
        if (self.last_command) |cmd| {
            self.allocator.free(cmd);
        }
        self.last_command = try self.allocator.dupe(u8, command);
        self.last_status = status;
    }

    pub fn changeCwd(self: *Self, new_dir: []const u8) !void {
        // Try to change directory
        try std.process.changeCurDir(new_dir);

        // If successful, update stored cwd
        const old_cwd = self.cwd;
        var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = try std.process.getCwd(&cwd_buf);
        self.cwd = try self.allocator.dupe(u8, cwd);
        self.allocator.free(old_cwd);
    }
};

const CommandResult = struct {
    output: []const u8,
    status: u8,
    err_msg: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, output: []const u8, status: u8, err_msg: ?[]const u8) !CommandResult {
        return CommandResult{
            .output = try allocator.dupe(u8, output),
            .status = status,
            .err_msg = if (err_msg) |err| try allocator.dupe(u8, err) else null,
        };
    }

    pub fn deinit(self: *const CommandResult, allocator: std.mem.Allocator) void {
        allocator.free(self.output);
        if (self.err_msg) |err| {
            allocator.free(err);
        }
    }
};

const InputHandler = struct {
    const Self = @This();

    input: []const u8,
    mode: InputMode,

    pub fn parse(input: []const u8) Self {
        if (std.mem.startsWith(u8, input, ";")) {
            return .{
                .input = std.mem.trim(u8, input[1..], " "),
                .mode = .Chat,
            };
        } else {
            return .{
                .input = input,
                .mode = .Command,
            };
        }
    }
};

const ResponseChunk = struct {
    model: []const u8,
    created_at: []const u8,
    response: []const u8,
    done: bool,
    done_reason: ?[]const u8 = null,
    context: ?[]const u64 = null,
    total_duration: ?u64 = null,
    load_duration: ?u64 = null,
    prompt_eval_count: ?u64 = null,
    prompt_eval_duration: ?u64 = null,
    eval_count: ?u64 = null,
    eval_duration: ?u64 = null,
};

const HistoryEntry = struct {
    command: []const u8,
    frequency: u64,
    last_used: i64,
    hash: u64,

    pub fn init(allocator: std.mem.Allocator, command: []const u8) !HistoryEntry {
        const cmd_copy = try allocator.dupe(u8, command);
        return .{
            .command = cmd_copy,
            .frequency = 1,
            .last_used = std.time.timestamp(),
            .hash = std.hash.Wyhash.hash(0, command),
        };
    }
};

const CommandHistory = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    entries: std.ArrayList(HistoryEntry),
    lookup: std.AutoHashMap(u64, usize),
    history_path: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Self {
        // Get config directory
        const config_dir = try std.fs.path.join(allocator, &[_][]const u8{
            try std.fs.getAppDataDir(allocator, "bondsman"),
            "history",
        });

        // Create config directory if it doesn't exist
        try std.fs.cwd().makePath(config_dir);

        const history_path = try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "history.json" });

        return Self{
            .allocator = allocator,
            .entries = std.ArrayList(HistoryEntry).init(allocator),
            .lookup = std.AutoHashMap(u64, usize).init(allocator),
            .history_path = history_path,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all command strings
        for (self.entries.items) |entry| {
            self.allocator.free(entry.command);
        }
        self.entries.deinit();
        self.lookup.deinit();
        self.allocator.free(self.history_path);
    }

    pub fn addCommand(self: *Self, command: []const u8) !void {
        const hash = std.hash.Wyhash.hash(0, command);

        // Update existing command
        if (self.lookup.get(hash)) |index| {
            var entry = &self.entries.items[index];
            entry.frequency += 1;
            entry.last_used = std.time.timestamp();
            try self.save();
            return;
        }

        // Add new command
        const entry = try HistoryEntry.init(self.allocator, command);
        const index = self.entries.items.len;
        try self.entries.append(entry);
        try self.lookup.put(hash, index);

        // Maintain size limit
        if (self.entries.items.len > 100) {
            const removed = self.entries.orderedRemove(0);
            self.allocator.free(removed.command);
            // Rebuild lookup table
            self.lookup.clearRetainingCapacity();
            for (self.entries.items, 0..) |item, i| {
                try self.lookup.put(item.hash, i);
            }
        }

        try self.save();
    }

    pub fn searchCommands(self: Self, prefix: []const u8) ![]const []const u8 {
        var results = std.ArrayList([]const u8).init(self.allocator);
        errdefer results.deinit();

        for (self.entries.items) |entry| {
            if (std.mem.startsWith(u8, entry.command, prefix)) {
                try results.append(entry.command);
            }
        }

        return results.toOwnedSlice();
    }

    fn save(self: Self) !void {
        const file = try std.fs.createFileAbsolute(self.history_path, .{});
        defer file.close();

        try std.json.stringify(self.entries.items, .{}, file.writer());
    }

    fn load(self: *Self) !void {
        const file = std.fs.openFileAbsolute(self.history_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        var parsed = try std.json.parseFromSlice([]HistoryEntry, self.allocator, content, .{});
        defer parsed.deinit();

        // Clear existing entries
        for (self.entries.items) |entry| {
            self.allocator.free(entry.command);
        }
        self.entries.clearRetainingCapacity();
        self.lookup.clearRetainingCapacity();

        // Add loaded entries
        for (parsed.value) |entry| {
            try self.addCommand(entry.command);
        }
    }
};

fn printHeader(text: []const u8) void {
    std.debug.print("\n{s}{s}=== {s} ==={s}\n\n", .{
        ANSI.cyan,
        ANSI.bold,
        text,
        ANSI.reset,
    });
}

fn printResponse(text: []const u8) void {
    // Print the response prefix once at the start
    std.debug.print("{s}{s}>{s} ", .{
        ANSI.cyan,
        ANSI.dim,
        ANSI.reset,
    });

    // Print the actual response text
    std.debug.print("{s}", .{text});
}

fn printError(text: []const u8) void {
    std.debug.print("{s}{s}error:{s} {s}\n", .{
        ANSI.red,
        ANSI.bold,
        ANSI.reset,
        text,
    });
}

fn printWelcome() void {
    std.debug.print("run `;;help` for more info", .{});
}

fn handleChat(client: *std.http.Client, allocator: std.mem.Allocator, prompt: []const u8, context: *const CommandContext, sys_context: *const SystemContext) !void {
    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();

    const sys_info = try sys_context.formatContext(allocator);
    defer allocator.free(sys_info);

    const session_info = try context.formatContext(allocator);
    defer allocator.free(session_info);

    const system_prompt =
        \\You are a friendly command-line assistant. Keep your responses conversational and concise.
        \\Use the provided system information (OS, shell, etc.) and session context (current directory, last command) 
        \\to give more relevant and accurate responses. Adapt your suggestions to the user's environment.
        \\Don't use bullet points or lists unless specifically asked.
        \\Only show example commands if they would be immediately useful.
        \\Focus on being helpful while keeping responses brief and to the point.
        \\
        \\
    ;

    const context_prompt = try std.fmt.allocPrint(
        allocator,
        \\{s}
        \\{s}
        \\{s}
        \\User: {s}
        \\Assistant: 
    ,
        .{
            system_prompt,
            sys_info,
            session_info,
            prompt,
        },
    );
    defer allocator.free(context_prompt);

    try std.json.stringify(.{
        .model = "qwen2.5-coder:1.5b",
        .prompt = context_prompt,
    }, .{}, json_string.writer());

    // Parse the URI for Ollama's API endpoint
    const uri = try std.Uri.parse("http://localhost:11434/api/generate");

    // Set up the headers
    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    // Allocate a buffer for server headers
    var buf: [4096]u8 = undefined;

    // Make the connection to the server
    var request = try client.open(.POST, uri, .{
        .server_header_buffer = &buf,
        .extra_headers = headers,
    });
    defer request.deinit();

    // Set up transfer encoding for sending data
    request.transfer_encoding = .{ .content_length = json_string.items.len };

    // Send the request headers and body
    try request.send();
    try request.writer().writeAll(json_string.items);
    try request.finish();

    // Wait for the server to send us a response
    try request.wait();

    // Print the header
    printHeader("AI Assistant");

    // Process response
    const reader = request.reader();
    var response_buf: [4096]u8 = undefined;
    var line_buf = std.ArrayList(u8).init(allocator);
    defer line_buf.deinit();

    var first_response = true;

    while (true) {
        const bytes_read = try reader.read(&response_buf);
        if (bytes_read == 0) break;

        // Process the chunk of response
        const chunk = response_buf[0..bytes_read];
        try line_buf.appendSlice(chunk);

        // Process any complete lines
        while (std.mem.indexOf(u8, line_buf.items, "\n")) |newline_pos| {
            const line = line_buf.items[0..newline_pos];

            // Parse the JSON response
            var parsed = try json.parseFromSlice(ResponseChunk, allocator, line, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();

            // Print the response text
            if (parsed.value.response.len > 0) {
                if (first_response) {
                    printResponse(parsed.value.response);
                    first_response = false;
                } else {
                    std.debug.print("{s}", .{parsed.value.response});
                }
            }

            // Remove the processed line from the buffer
            try line_buf.replaceRange(0, newline_pos + 1, &[_]u8{});
        }
    }

    std.debug.print("\n\n", .{});
}

fn handleCommand(allocator: std.mem.Allocator, context: *CommandContext, sys_context: *const SystemContext, command: []const u8) !void {
    // Handle built-in commands
    if (std.mem.eql(u8, command, "help")) {
        printWelcome();
        return;
    }

    // Execute the command
    var result = try executeCommand(allocator, context, sys_context, command);
    defer result.deinit(allocator);

    // Update context with command result
    try context.updateCommand(command, result.status);

    // Print output and any errors
    if (result.output.len > 0) {
        if (result.output[result.output.len - 1] != '\n') {
            std.debug.print("{s}\n", .{result.output});
        } else {
            std.debug.print("{s}", .{result.output});
        }
    }
    if (result.err_msg) |err| {
        printError(err);
    }
}

const OllamaService = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    process: ?ChildProcess,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .process = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.process) |*proc| {
            _ = proc.kill() catch {};
        }
    }

    pub fn isRunning(self: Self) bool {
        // Try to connect to Ollama health endpoint
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = std.Uri.parse("http://localhost:11434/api/tags") catch return false;

        var buf: [1024]u8 = undefined;
        var request = client.open(.GET, uri, .{
            .server_header_buffer = &buf,
        }) catch return false;
        defer request.deinit();

        request.send() catch return false;
        request.finish() catch return false;
        request.wait() catch return false;

        return request.response.status == .ok;
    }

    pub fn start(self: *Self) !void {
        if (self.isRunning()) {
            return; // Already running
        }

        std.debug.print("{s}{s}Starting Ollama server...{s} ", .{
            ANSI.yellow,
            ANSI.bold,
            ANSI.reset,
        });

        // Try to start Ollama
        const argv = &[_][]const u8{ "ollama", "serve" };
        var child = ChildProcess.init(argv, self.allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        child.spawn() catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("\r{s}{s}Error: Ollama not found in PATH{s}\n", .{
                    ANSI.red,
                    ANSI.bold,
                    ANSI.reset,
                });
                std.debug.print("Please install Ollama: https://ollama.ai/\n", .{});
                return err;
            },
            else => return err,
        };

        self.process = child;

        // Wait for server to be ready (with timeout)
        var attempts: u32 = 0;
        const max_attempts = 30; // 30 seconds total

        while (attempts < max_attempts) {
            std.time.sleep(1_000_000_000); // 1 second
            attempts += 1;

            if (self.isRunning()) {
                std.debug.print("\r{s}{s}Ollama server started!{s}    \n", .{
                    ANSI.green,
                    ANSI.bold,
                    ANSI.reset,
                });
                return;
            }

            // Show progress with animated dots
            const dots_patterns = [_][]const u8{ "", ".", "..", "..." };
            const dots = dots_patterns[attempts % 4];
            std.debug.print("\r{s}{s}Starting Ollama server{s}{s} ", .{
                ANSI.yellow,
                ANSI.bold,
                dots,
                ANSI.reset,
            });
        }

        std.debug.print("\r{s}{s}Error: Ollama server failed to start{s}\n", .{
            ANSI.red,
            ANSI.bold,
            ANSI.reset,
        });
        return error.OllamaStartupTimeout;
    }

    pub fn ensureModelExists(self: Self, model_name: []const u8) !void {
        // Check if model exists by trying to use it
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var json_string = std.ArrayList(u8).init(self.allocator);
        defer json_string.deinit();

        try std.json.stringify(.{
            .name = model_name,
        }, .{}, json_string.writer());

        const uri = try std.Uri.parse("http://localhost:11434/api/show");
        const headers = &[_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };

        var buf: [4096]u8 = undefined;
        var request = client.open(.POST, uri, .{
            .server_header_buffer = &buf,
            .extra_headers = headers,
        }) catch return error.NetworkError;
        defer request.deinit();

        request.transfer_encoding = .{ .content_length = json_string.items.len };
        request.send() catch return error.NetworkError;
        request.writer().writeAll(json_string.items) catch return error.NetworkError;
        request.finish() catch return error.NetworkError;
        request.wait() catch return error.NetworkError;

        if (request.response.status != .ok) {
            std.debug.print("{s}{s}Model '{s}' not found. Downloading...{s}\n", .{
                ANSI.yellow,
                ANSI.bold,
                model_name,
                ANSI.reset,
            });

            // Pull the model
            const pull_argv = &[_][]const u8{ "ollama", "pull", model_name };
            var pull_child = ChildProcess.init(pull_argv, self.allocator);
            pull_child.stdin_behavior = .Ignore;
            pull_child.stdout_behavior = .Inherit;
            pull_child.stderr_behavior = .Inherit;

            try pull_child.spawn();
            const term = try pull_child.wait();

            switch (term) {
                .Exited => |code| {
                    if (code != 0) {
                        return error.ModelDownloadFailed;
                    }
                },
                else => return error.ModelDownloadFailed,
            }

            std.debug.print("{s}{s}Model '{s}' downloaded successfully!{s}\n", .{
                ANSI.green,
                ANSI.bold,
                model_name,
                ANSI.reset,
            });
        }
    }
};

fn preloadModel(client: *std.http.Client, allocator: std.mem.Allocator, reporter: *const report.Reporter) !void {
    reporter.logDebug("{s}{s}Initializing Bondsman...{s} ", .{
        ANSI.yellow,
        ANSI.bold,
        ANSI.reset,
    });

    // Create the JSON request body - use a simple prompt
    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();

    try std.json.stringify(.{
        .model = "qwen2.5-coder:1.5b",
        .prompt = "You are a command-line assistant. You help users understand and fix command-line issues. Keep responses concise and focused on command-line usage.",
    }, .{}, json_string.writer());

    // Parse the URI for Ollama's API endpoint
    const uri = try std.Uri.parse("http://localhost:11434/api/generate");

    // Set up the headers
    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    // Allocate a buffer for server headers
    var buf: [4096]u8 = undefined;

    // Make the connection to the server
    var request = try client.open(.POST, uri, .{
        .server_header_buffer = &buf,
        .extra_headers = headers,
    });
    defer request.deinit();

    // Set up transfer encoding for sending data
    request.transfer_encoding = .{ .content_length = json_string.items.len };

    // Send the request headers and body
    try request.send();
    try request.writer().writeAll(json_string.items);
    try request.finish();

    // Wait for the server to send us a response
    try request.wait();

    // Read and discard the response, but track when we're done
    const reader = request.reader();
    var response_buf: [4096]u8 = undefined;
    var line_buf = std.ArrayList(u8).init(allocator);
    defer line_buf.deinit();

    var is_loaded = false;

    while (true) {
        const bytes_read = try reader.read(&response_buf);
        if (bytes_read == 0) break;

        // Process the chunk of response
        const chunk = response_buf[0..bytes_read];
        try line_buf.appendSlice(chunk);

        // Process any complete lines
        while (std.mem.indexOf(u8, line_buf.items, "\n")) |newline_pos| {
            const line = line_buf.items[0..newline_pos];

            // Parse the JSON response just to check done status
            var parsed = try json.parseFromSlice(ResponseChunk, allocator, line, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();

            if (!is_loaded) {
                reporter.logDebug("\r{s}{s}Bondsman is ready!{s}              \n\n", .{
                    ANSI.green,
                    ANSI.bold,
                    ANSI.reset,
                });
                is_loaded = true;
            }

            // Remove the processed line from the buffer
            try line_buf.replaceRange(0, newline_pos + 1, &[_]u8{});
        }
    }
}

fn executeCommand(allocator: std.mem.Allocator, context: *CommandContext, sys_context: *const SystemContext, command: []const u8) !CommandResult {
    // Handle built-in commands first
    if (std.mem.startsWith(u8, command, "cd ")) {
        const dir = std.mem.trim(u8, command[3..], " ");
        try context.changeCwd(dir);
        return CommandResult.init(allocator, "", 0, null);
    }

    // Create shell-appropriate command array
    const argv = if (std.mem.indexOf(u8, sys_context.shell_path, "powershell")) |_|
        [_][]const u8{ sys_context.shell_path, "-Command", command }
    else if (std.mem.indexOf(u8, sys_context.shell_path, "cmd")) |_|
        [_][]const u8{ sys_context.shell_path, "/c", command }
    else
        [_][]const u8{ sys_context.shell_path, "-c", command }; // Default to Unix-style

    var child = ChildProcess.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.cwd = context.cwd;
    child.env_map = &context.env;

    try child.spawn();

    // Read output
    const output = try child.stdout.?.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    const stderr_output = try child.stderr.?.reader().readAllAlloc(allocator, std.math.maxInt(usize));

    // Wait for completion
    const term = try child.wait();

    // Get status
    const status: u8 = switch (term) {
        .Exited => |code| @truncate(code),
        else => 1,
    };

    // Clean up child process - ignore the result since we already have the status
    _ = child.kill() catch term;

    // If there's stderr output, treat it as an error
    const error_msg = if (stderr_output.len > 0) stderr_output else null;

    return CommandResult.init(allocator, output, status, error_msg);
}

pub fn main() !void {
    // Enable ANSI support for Windows console
    try enableAnsiConsole();

    var debug_enabled = false;

    // Create an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var auto_start = true;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--no-auto-start")) {
            auto_start = false;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print(
                \\Bondsman - Local AI Shell Assistant
                \\
                \\Usage: bondsman [options]
                \\
                \\Options:
                \\  --no-auto-start    Don't automatically start Ollama server
                \\  --help, -h         Show this help message
                \\
            , .{});
            return;
        }
        if (std.mem.eql(u8, arg, "--debug")) {
            debug_enabled = true;
        }
    }

    // Initialize reporter
    var reporter = report.Reporter.init(debug_enabled);

    // Initialize system context
    var sys_context = try SystemContext.init(allocator);
    defer sys_context.deinit();

    // Initialize Ollama service manager
    var ollama = OllamaService.init(allocator);
    defer ollama.deinit();

    // Start Ollama if needed and ensure model exists
    if (auto_start) {
        try ollama.start();
        try ollama.ensureModelExists("qwen2.5-coder:1.5b");
    } else {
        // Just check if it's running
        if (!ollama.isRunning()) {
            std.debug.print("{s}{s}Warning: Ollama server not running. Start it with: ollama serve{s}\n", .{
                ANSI.yellow,
                ANSI.bold,
                ANSI.reset,
            });
        }
    }

    // Create an HTTP client that we'll reuse
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Initialize command history
    var history = try CommandHistory.init(allocator);
    defer history.deinit();
    try history.load();

    // Initialize command context
    var context = try CommandContext.init(allocator);
    defer context.deinit();

    // Preload the model
    try preloadModel(&client, allocator, &reporter);

    // Show welcome message
    printWelcome();

    // Create a buffer for reading user input
    var input_buffer: [4096]u8 = undefined;

    while (true) {
        // Print context-aware prompt
        const prompt = try context.getPrompt();
        defer allocator.free(prompt);
        std.debug.print("{s}", .{prompt});

        // Read a line of input
        const stdin = std.io.getStdIn();
        if (try stdin.reader().readUntilDelimiterOrEof(&input_buffer, '\n')) |user_input| {
            const trimmed_input = std.mem.trim(u8, user_input, " \t\r\n");
            if (trimmed_input.len == 0) continue;

            // Check for quit command
            if (std.mem.eql(u8, trimmed_input, "quit") or std.mem.eql(u8, trimmed_input, "exit")) {
                std.debug.print("\n{s}{s}Goodbye!{s}\n", .{
                    ANSI.green,
                    ANSI.bold,
                    ANSI.reset,
                });
                break;
            }

            // Parse input mode
            const handler = InputHandler.parse(trimmed_input);

            switch (handler.mode) {
                .Chat => {
                    try handleChat(&client, allocator, handler.input, &context, &sys_context);
                },
                .Command => {
                    try history.addCommand(handler.input);
                    try handleCommand(allocator, &context, &sys_context, handler.input);
                },
            }
        } else {
            // EOF reached (e.g., Ctrl+D)
            std.debug.print("\n{s}{s}Goodbye!{s}\n", .{
                ANSI.green,
                ANSI.bold,
                ANSI.reset,
            });
            break;
        }
    }
}
