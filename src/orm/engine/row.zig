const std = @import("std");
const Stmt = @import("../../db/stmt.zig").Stmt;
const types = @import("../../core/types.zig");
const meta = @import("../../core/meta.zig");
const errors = @import("../../core/errors.zig");

pub fn readValue(comptime FieldT: type, st: *Stmt, allocator: std.mem.Allocator, col: i32) errors.ZiteError!FieldT {
    if (FieldT == types.EpochMillis) {
        return .{ .value = st.colInt(col) };
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
            if (st.colIsNull(col)) return null;
            const Child = o.child;
            const v = try readValue(Child, st, allocator, col);
            return @as(FieldT, v);
        },
        .bool => return st.colBool(col),
        .int, .comptime_int => {
            const v = st.colInt(col);
            return @as(FieldT, @intCast(v));
        },
        .float, .comptime_float => {
            const v = st.colDouble(col);
            return @as(FieldT, @floatCast(v));
        },
        .@"enum" => {
            const v = st.colInt(col);
            const tag_ty = @typeInfo(FieldT).@"enum".tag_type;
            return @enumFromInt(@as(tag_ty, @intCast(v)));
        },
        .pointer => return error.UnsupportedColumnType,
        else => return error.UnsupportedColumnType,
    }
}

pub fn readStruct(comptime T: type, st: *Stmt, allocator: std.mem.Allocator) errors.ZiteError!T {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("readStruct expects a struct type");
    const m = comptime meta.getMeta(T);

    var out: T = std.mem.zeroes(T);
    errdefer freeOwnedRow(T, allocator, &out);

    const fields = ti.@"struct".fields;
    comptime var col: usize = 0;
    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) continue;
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

    inline for (ti.@"struct".fields) |f| {
        freeField(f.type, allocator, &@field(value, f.name));
    }
}

fn freeField(comptime FieldT: type, allocator: std.mem.Allocator, field_ptr: anytype) void {
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
