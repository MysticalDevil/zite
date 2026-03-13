const std = @import("std");
const builtin = @import("builtin");

const testing = std.testing;

pub const std_options: std.Options = .{
    .log_level = .warn,
};

pub fn main(init: std.process.Init.Minimal) !void {
    var it = std.process.Args.Iterator.init(init.args);
    defer it.deinit();
    _ = it.skip(); // skip argv[0]

    while (it.next()) |arg_z| {
        const arg: []const u8 = arg_z;
        if (std.mem.startsWith(u8, arg, "--seed=")) {
            testing.random_seed = std.fmt.parseUnsigned(u32, arg["--seed=".len..], 0) catch 0;
        }
    }

    var passed: u64 = 0;
    var skipped: u64 = 0;
    var failed: u64 = 0;

    for (builtin.test_functions) |test_fn| {
        std.debug.print("{s}... ", .{test_fn.name});
        if (test_fn.func()) |_| {
            passed += 1;
            std.debug.print("OK\n", .{});
        } else |err| {
            if (err == error.SkipZigTest) {
                skipped += 1;
                std.debug.print("SKIP\n", .{});
            } else {
                failed += 1;
                std.debug.print("FAIL ({s})\n", .{@errorName(err)});
            }
        }
    }

    std.debug.print("{} passed, {} skipped, {} failed\n", .{ passed, skipped, failed });
    if (failed != 0) return error.TestFailure;
}
