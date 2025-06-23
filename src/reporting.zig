const std = @import("std");

pub const Reporter = struct {
    debug_enabled: bool,

    pub fn init(debug_enabled: bool) Reporter {
        return Reporter{ .debug_enabled = debug_enabled };
    }

    pub fn logDebug(self: *const Reporter, comptime format: []const u8, args: anytype) void {
        if (!self.debug_enabled) {
            return;
        }
        logOutWithPrefix("[DEBUG] ", format, args);
    }
};

pub fn throwError(comptime format: []const u8, args: anytype) void {
    logErrWithPrefix("error: ", format, args);
    std.process.exit(1);
}

pub fn throwWarning(comptime format: []const u8, args: anytype) void {
    logErrWithPrefix("warning: ", format, args);
}

pub fn log(comptime format: []const u8, args: anytype) void {
    logOutWithPrefix("", format, args);
}

// internal functions
fn write(
    writer: anytype,
    comptime prefix: []const u8,
    comptime format: []const u8,
    args: anytype,
    comptime stream: []const u8,
) void {
    nosuspend {
        writer.print(prefix ++ format, args) catch |e| {
            std.debug.print("Failed to write {s}: {}\n", .{ stream, e });
            return;
        };
        writer.context.flush() catch |e| {
            std.debug.print("Failed to flush {s} buffer: {}\n", .{ stream, e });
            return;
        };
    }
}

fn logOutWithPrefix(comptime actual_prefix: []const u8, comptime format: []const u8, args: anytype) void {
    const writer = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(writer);
    const buffered_writer = bw.writer();

    write(buffered_writer, actual_prefix, format, args, "stdout");
}

fn logErrWithPrefix(comptime actual_prefix: []const u8, comptime format: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    write(writer, actual_prefix, format, args, "stderr");
}
