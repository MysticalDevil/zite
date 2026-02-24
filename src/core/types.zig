const std = @import("std");

pub const UnixMillis = struct {
    /// Milliseconds since Unix epoch.
    value: i64,
};

pub const Text = struct {
    /// Owned UTF-8 text buffer. Caller owns and must free `value`.
    value: []u8,

    /// Allocate an owned Text from a const slice.
    pub fn fromConst(a: std.mem.Allocator, s: []const u8) !Text {
        const out = try a.dupe(u8, s);
        return .{ .value = out };
    }
};

pub const Blob = struct {
    /// Owned binary buffer. Caller owns and must free `value`.
    value: []u8,

    /// Allocate an owned Blob from a const slice.
    pub fn fromConst(a: std.mem.Allocator, s: []const u8) !Blob {
        const out = try a.dupe(u8, s);
        return .{ .value = out };
    }
};
