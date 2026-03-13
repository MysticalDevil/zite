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

test "types: OwnedText fromConst copies and deinit clears" {
    const a = std.testing.allocator;
    const src = "hello";
    var t = try OwnedText.fromConst(a, src);
    defer t.deinit(a);

    try std.testing.expectEqualStrings(src, t.value);
    // Ensure it is a separate allocation.
    try std.testing.expect(t.value.ptr != src.ptr);

    t.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), t.value.len);
}

test "types: OwnedText empty deinit is safe" {
    const a = std.testing.allocator;
    var t = try OwnedText.fromConst(a, "");
    t.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), t.value.len);
}

test "types: OwnedBlob fromConst copies and deinit clears" {
    const a = std.testing.allocator;
    const src = [_]u8{ 1, 2, 3 };
    var b = try OwnedBlob.fromConst(a, src[0..]);
    defer b.deinit(a);

    try std.testing.expect(std.mem.eql(u8, src[0..], b.value));
    try std.testing.expect(b.value.ptr != src[0..].ptr);

    b.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), b.value.len);
}

test "types: OwnedBlob empty deinit is safe" {
    const a = std.testing.allocator;
    var b = try OwnedBlob.fromConst(a, &.{});
    b.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), b.value.len);
}

test "types: OwnedText fromConst propagates OutOfMemory" {
    var failing_state = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    const failing = failing_state.allocator();

    try std.testing.expectError(error.OutOfMemory, OwnedText.fromConst(failing, "oom"));
}

test "types: OwnedBlob fromConst propagates OutOfMemory" {
    var failing_state = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    const failing = failing_state.allocator();

    try std.testing.expectError(error.OutOfMemory, OwnedBlob.fromConst(failing, &[_]u8{ 1, 2, 3 }));
}
