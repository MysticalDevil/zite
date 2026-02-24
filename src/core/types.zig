const std = @import("std");

pub const UnixMillis = struct {
    value: i64,
};

pub const Text = struct {
    value: []u8,

    pub fn fromConst(a: std.mem.Allocator, s: []const u8) !Text {
        const out = try a.dupe(u8, s);
        return .{ .value = out };
    }
};

pub const Blob = struct {
    value: []u8,

    pub fn fromConst(a: std.mem.Allocator, s: []const u8) !Blob {
        const out = try a.dupe(u8, s);
        return .{ .value = out };
    }
};
