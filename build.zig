const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const diag_enable_in_tests =
        b.option(bool, "diag_enable_in_tests", "Enable sqlite diagnostics output during tests") orelse false;

    const opts = b.addOptions();
    opts.addOption(bool, "diag_enable_in_tests", diag_enable_in_tests);
    const options_mod = opts.createModule();

    const orm = b.addModule("zite", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    orm.linkSystemLibrary("sqlite3", .{ .needed = true });
    orm.addImport("build_options", options_mod);

    const unit_tests = b.addTest(.{ .root_module = orm, .use_llvm = true });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

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
    it_mod.addImport("build_options", options_mod);

    const itests = b.addTest(.{ .root_module = it_mod, .use_llvm = true });
    const run_itests = b.addRunArtifact(itests);

    const itest_step = b.step("itest", "Run integration tests");
    itest_step.dependOn(&run_itests.step);
}
