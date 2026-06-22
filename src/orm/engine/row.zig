const std = @import("std");
const Driver = @import("../../driver/sqlite3.zig");
const Db = @import("../../db/db.zig").Db(Driver);
const Stmt = @import("../../db/stmt.zig").Stmt(Driver);
const types = @import("../../core/types.zig");
const meta = @import("../../core/meta.zig");
const errors = @import("../../core/errors.zig");
const reflect = @import("../../core/reflect.zig");

pub fn readValue(comptime FieldT: type, st: *Stmt, allocator: std.mem.Allocator, col: i32) errors.RowReadError!FieldT {
    if (FieldT == types.EpochMillis) {
        return .{ .value = try st.colInt(col) };
    }
    if (FieldT == types.OwnedText) {
        const owned = (try st.colTextOwned(allocator, col)) orelse return error.UnexpectedNull;
        return .{ .value = owned };
    }
    if (FieldT == types.OwnedBlob) {
        const owned = (try st.colBlobOwned(allocator, col)) orelse return error.UnexpectedNull;
        return .{ .value = owned };
    }

    switch (@typeInfo(FieldT)) {
        .optional => |o| {
            if (try st.colIsNull(col)) {
                return null;
            }
            const Child = o.child;
            const v = try readValue(Child, st, allocator, col);
            return @as(FieldT, v);
        },
        .bool => return try st.colBool(col),
        .int => {
            const v = try st.colInt(col);
            return std.math.cast(FieldT, v) orelse error.UnexpectedColumnType;
        },
        .float => {
            const v = try st.colDouble(col);
            return @as(FieldT, @floatCast(v));
        },
        .@"enum" => {
            const v = try st.colInt(col);
            return try intToEnumChecked(FieldT, v);
        },
        .pointer => return error.UnsupportedColumnType,
        else => return error.UnsupportedColumnType,
    }
}

pub fn ViewFieldType(comptime FieldT: type) type {
    if (FieldT == types.OwnedText) {
        return []const u8;
    }
    if (FieldT == types.OwnedBlob) {
        return []const u8;
    }
    if (FieldT == types.EpochMillis) {
        return types.EpochMillis;
    }

    return switch (@typeInfo(FieldT)) {
        .optional => |o| ?ViewFieldType(o.child),
        else => FieldT,
    };
}

pub fn readValueView(comptime FieldT: type, st: *Stmt, col: i32) errors.RowReadError!ViewFieldType(FieldT) {
    if (FieldT == types.EpochMillis) {
        return .{ .value = try st.colInt(col) };
    }
    if (FieldT == types.OwnedText) {
        return (try st.colTextBorrowed(col)) orelse return error.UnexpectedNull;
    }
    if (FieldT == types.OwnedBlob) {
        return (try st.colBlobBorrowed(col)) orelse return error.UnexpectedNull;
    }

    switch (@typeInfo(FieldT)) {
        .optional => |o| {
            if (try st.colIsNull(col)) {
                return null;
            }
            const Child = o.child;
            return try readValueView(Child, st, col);
        },
        .bool => return try st.colBool(col),
        .int => {
            const v = try st.colInt(col);
            return std.math.cast(FieldT, v) orelse error.UnexpectedColumnType;
        },
        .float => {
            const v = try st.colDouble(col);
            return @as(FieldT, @floatCast(v));
        },
        .@"enum" => {
            const v = try st.colInt(col);
            return try intToEnumChecked(FieldT, v);
        },
        .pointer => return error.UnsupportedColumnType,
        else => return error.UnsupportedColumnType,
    }
}

fn intToEnumChecked(comptime E: type, v: i64) errors.RowReadError!E {
    const einfo = @typeInfo(E).@"enum";
    const Tag = einfo.tag_type;
    const tag_value = std.math.cast(Tag, v) orelse return error.UnexpectedColumnType;

    if (einfo.mode == .nonexhaustive) {
        return @enumFromInt(tag_value);
    }

    inline for (einfo.field_names, einfo.field_values) |_, value| {
        if (value == tag_value) {
            return @enumFromInt(tag_value);
        }
    }
    return error.UnexpectedColumnType;
}

pub fn readStruct(comptime T: type, st: *Stmt, allocator: std.mem.Allocator) errors.RowReadError!T {
    const ti = @typeInfo(T);
    if (ti != .@"struct") {
        @compileError("readStruct expects a struct type");
    }
    const m = comptime meta.getMeta(T);

    var out: T = std.mem.zeroes(T);
    errdefer freeOwnedRow(T, allocator, &out);

    const fields = comptime reflect.structFields(T);
    comptime var col: usize = 0;
    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) {
            continue;
        }
        const v = try readValue(f.type, st, allocator, @as(i32, @intCast(col)));
        @field(out, f.name) = v;
        col += 1;
    }
    return out;
}

/// Frees owned TEXT/BLOB fields for a value.
pub fn freeOwnedRow(comptime T: type, allocator: std.mem.Allocator, value: *T) void {
    const ti = @typeInfo(T);
    if (ti != .@"struct")
        @compileError("freeOwnedRow expects a struct type");

    inline for (comptime reflect.structFields(T)) |f| {
        freeField(f.type, allocator, &@field(value, f.name));
    }
}

fn freeField(comptime FieldT: type, allocator: std.mem.Allocator, field_ptr: *FieldT) void {
    if (FieldT == types.OwnedText) {
        field_ptr.deinit(allocator);
        return;
    }
    if (FieldT == types.OwnedBlob) {
        field_ptr.deinit(allocator);
        return;
    }
    switch (@typeInfo(FieldT)) {
        .optional => |o| {
            if (field_ptr.*) |*v| {
                freeField(o.child, allocator, v);
            }
        },
        else => {},
    }
}

test "row: int narrowing overflow returns UnexpectedColumnType" {
    var db = try Db.open(std.testing.allocator, ":memory:");
    defer db.deinit();

    var st = try Stmt.init(&db, "SELECT 200;");
    defer st.deinit();
    try std.testing.expectEqual(.row, try st.step());

    try std.testing.expectError(
        error.UnexpectedColumnType,
        readValue(i8, &st, std.testing.allocator, 0),
    );
}

test "row: exhaustive enum conversion rejects invalid tags" {
    const E = enum(i8) { a = 1, b = 2 };

    var db = try Db.open(std.testing.allocator, ":memory:");
    defer db.deinit();

    var st = try Stmt.init(&db, "SELECT 3;");
    defer st.deinit();
    try std.testing.expectEqual(.row, try st.step());

    try std.testing.expectError(
        error.UnexpectedColumnType,
        readValue(E, &st, std.testing.allocator, 0),
    );
}
