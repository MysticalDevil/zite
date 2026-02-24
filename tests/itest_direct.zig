const std = @import("std");
const zite = @import("zite");

pub const std_options: std.Options = .{
    .log_level = .err,
};

comptime {
    _ = zite;
    _ = @import("itest.zig");
}
