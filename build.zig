const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("Ziggy-Kanren-Language", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    const coverage = b.option(bool, "test-coverage", "Generate test coverage") orelse false;
    const tests = b.addTest("src/test_fives_and_sixes.zig");
    tests.setBuildMode(mode);

    if (coverage) {
        tests.setExecCmd(&[_]?[]const u8{
            "kcov",
            "kcov-output",
            null,
        });
    }

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests.step);
}
