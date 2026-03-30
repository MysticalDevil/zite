const std = @import("std");

const SqliteBackend = enum {
    system,
    pure,
};

pub fn build(b: *std.Build) void {
    // Standard CLI options.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sqlite_backend = b.option(SqliteBackend, "sqlite_backend", "SQLite backend: system (libsqlite3) or pure (pure-Zig driver)") orelse .system;

    const build_options = b.addOptions();
    build_options.addOption(SqliteBackend, "sqlite_backend", sqlite_backend);
    const build_options_mod = build_options.createModule();

    // Library module.
    const zite_mod = b.addModule("zite", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "build_options", .module = build_options_mod },
        },
    });
    if (sqlite_backend == .system) {
        zite_mod.linkSystemLibrary("sqlite3", .{ .needed = true });
    }

    // Unit tests for library module.
    const unit_tests = b.addTest(.{
        .root_module = zite_mod,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Aggregated unit tests for core modules.
    const unit_file_mod = b.createModule(.{
        .root_source_file = b.path("src/unit_tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "build_options", .module = build_options_mod },
        },
    });
    if (sqlite_backend == .system) {
        unit_file_mod.linkSystemLibrary("sqlite3", .{ .needed = true });
    }

    const unit_file_tests = b.addTest(.{
        .root_module = unit_file_mod,
    });
    const run_unit_file_tests = b.addRunArtifact(unit_file_tests);
    test_step.dependOn(&run_unit_file_tests.step);

    // Integration tests: a dedicated root that imports the library.
    const it_mod = b.createModule(.{
        .root_source_file = b.path("tests/itest.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "zite", .module = zite_mod },
            .{ .name = "build_options", .module = build_options_mod },
        },
    });
    if (sqlite_backend == .system) {
        it_mod.linkSystemLibrary("sqlite3", .{ .needed = true });
    }

    const itests = b.addTest(.{
        .root_module = it_mod,
    });
    const run_itests = b.addRunArtifact(itests);

    const itest_step = b.step("itest", "Run integration tests");
    itest_step.dependOn(&run_itests.step);
}
