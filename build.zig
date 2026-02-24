const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard CLI options.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build-time options.
    const diag_enable_in_tests =
        b.option(bool, "diag_enable_in_tests", "Enable sqlite diagnostics output during tests") orelse false;

    // Options module imported by runtime code.
    const opts = b.addOptions();
    opts.addOption(bool, "diag_enable_in_tests", diag_enable_in_tests);
    const options_mod = opts.createModule();

    // Library module.
    const zite_mod = b.addModule("zite", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    zite_mod.linkSystemLibrary("sqlite3", .{ .needed = true });
    zite_mod.addImport("build_options", options_mod);

    // Unit tests for library module.
    const unit_tests = b.addTest(.{ .root_module = zite_mod });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Integration tests: a dedicated root that imports the library.
    const it_mod = b.createModule(.{
        .root_source_file = b.path("tests/itest.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "zite", .module = zite_mod },
        },
    });
    it_mod.linkSystemLibrary("sqlite3", .{ .needed = true });
    it_mod.addImport("build_options", options_mod);

    const itests = b.addTest(.{ .root_module = it_mod });
    const run_itests = b.addRunArtifact(itests);

    const itest_step = b.step("itest", "Run integration tests");
    itest_step.dependOn(&run_itests.step);
}
