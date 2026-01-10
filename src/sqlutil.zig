const std = @import("std");
const meta = @import("meta.zig");

pub fn writeIdent(w: std.io.AnyWriter, name: []const u8) !void {
    try w.writeByte('"');
    try w.writeAll(name);
    try w.writeByte('"');
}

pub fn writePlaceholders(w: std.io.AnyWriter, comptime count: usize) !void {
    comptime var i: usize = 1;
    inline while (i <= count) : (i += 1) {
        if (i != 1) try w.writeAll(", ");
        try w.writeByte('?');
        try w.print("{}", .{i});
    }
}

pub fn writeInsertColumnList(w: std.io.AnyWriter, comptime T: type, comptime m: meta.Meta) !void {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("writeInsertColumnList expects a struct type");
    const fields = ti.@"struct".fields;

    comptime var col_i: usize = 0;
    inline for (fields) |f| {
        const skip = comptime (m.skip_primary_key_on_insert and meta.isPk(f.name, m.primary_key));
        if (skip) continue;

        if (col_i != 0) try w.writeAll(", ");
        try writeIdent(w, f.name);
        col_i += 1;
    }
}

pub fn writeUpdateSetClause(w: std.io.AnyWriter, comptime T: type, comptime m: meta.Meta) !void {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("writeUpdateSetClause expects a struct type");
    const fields = ti.@"struct".fields;

    comptime var set_i: usize = 0;
    inline for (fields) |f| {
        if (comptime meta.isPk(f.name, m.primary_key)) continue;

        if (set_i != 0) try w.writeAll(", ");
        try writeIdent(w, f.name);
        try w.writeAll("=?");
        try w.print("{}", .{set_i + 1});
        set_i += 1;
    }
}
