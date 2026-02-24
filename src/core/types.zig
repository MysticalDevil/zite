const std = @import("std");

/// Unix timestamp in milliseconds.
pub const UnixMillis = struct {
    /// Milliseconds since Unix epoch.
    value: i64,
};

/// Owned UTF-8 text wrapper.
pub const Text = struct {
    /// Owned UTF-8 text buffer. Caller owns and must free `value`.
    value: []u8,

    /// Allocate an owned Text from a const slice.
    pub fn fromConst(a: std.mem.Allocator, s: []const u8) !Text {
        const out = try a.dupe(u8, s);
        return .{ .value = out };
    }
};

/// Owned binary blob wrapper.
pub const Blob = struct {
    /// Owned binary buffer. Caller owns and must free `value`.
    value: []u8,

    /// Allocate an owned Blob from a const slice.
    pub fn fromConst(a: std.mem.Allocator, s: []const u8) !Blob {
        const out = try a.dupe(u8, s);
        return .{ .value = out };
    }
};
