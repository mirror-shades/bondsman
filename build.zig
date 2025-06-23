const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "bondsman",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Add test step
    //     const test_exe = b.addTest(.{
    //         .name = "test",
    //         .root_source_file = b.path("test/test.zig"),
    //     });
    //     const run_test = b.addRunArtifact(test_exe);
    //     const test_step = b.step("test", "Run the tests");
    //     test_step.dependOn(&run_test.step);
}
