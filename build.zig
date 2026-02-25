const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const orm = b.addModule("zite", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    orm.linkSystemLibrary("sqlite3", .{ .needed = true });

    const unit_tests = b.addTest(.{ .root_module = orm, .use_llvm = true });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    // Aggregated unit tests for core modules.
    const unit_file_mod = b.createModule(.{
        .root_source_file = b.path("src/unit_tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    unit_file_mod.linkSystemLibrary("sqlite3", .{ .needed = true });

    const unit_file_tests = b.addTest(.{ .root_module = unit_file_mod, .use_llvm = true });
    const run_unit_file_tests = b.addRunArtifact(unit_file_tests);
    test_step.dependOn(&run_unit_file_tests.step);

    // Integration tests: a dedicated root that imports the library.
    const it_mod = b.createModule(.{
        .root_source_file = b.path("tests/itest.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "zite", .module = orm },
        },
    });
    it_mod.linkSystemLibrary("sqlite3", .{ .needed = true });

    const itests = b.addTest(.{ .root_module = it_mod, .use_llvm = true });
    const run_itests = b.addRunArtifact(itests);

    const itest_step = b.step("itest", "Run integration tests");
    itest_step.dependOn(&run_itests.step);
}
