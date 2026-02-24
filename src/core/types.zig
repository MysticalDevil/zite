const std = @import("std");

/// Unix timestamp in milliseconds.
pub const EpochMillis = struct {
    /// Milliseconds since Unix epoch.
    value: i64,
};

/// Owned UTF-8 text wrapper.
pub const OwnedText = struct {
    /// Owned UTF-8 text buffer. Caller owns and must free `value`.
    value: []u8,

    /// Allocate an OwnedText from a const slice.
    pub fn fromConst(a: std.mem.Allocator, s: []const u8) !OwnedText {
        const out = try a.dupe(u8, s);
        return .{ .value = out };
    }

    /// Frees the owned buffer.
    pub fn deinit(self: *OwnedText, a: std.mem.Allocator) void {
        if (self.value.len != 0) a.free(self.value);
        self.value = &[_]u8{};
    }
};

/// Owned binary blob wrapper.
pub const OwnedBlob = struct {
    /// Owned binary buffer. Caller owns and must free `value`.
    value: []u8,

    /// Allocate an OwnedBlob from a const slice.
    pub fn fromConst(a: std.mem.Allocator, s: []const u8) !OwnedBlob {
        const out = try a.dupe(u8, s);
        return .{ .value = out };
    }

    /// Frees the owned buffer.
    pub fn deinit(self: *OwnedBlob, a: std.mem.Allocator) void {
        if (self.value.len != 0) a.free(self.value);
        self.value = &[_]u8{};
    }
};
