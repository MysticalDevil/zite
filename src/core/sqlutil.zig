const std = @import("std");
const meta = @import("meta.zig");
const errors = @import("errors.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList(u8);

pub fn writeIdent(list: *ArrayList, gpa: Allocator, name: []const u8) errors.ZiteError!void {
    try list.append(gpa, '"');
    for (name) |ch| {
        if (ch == '"') {
            try list.appendSlice(gpa, "\"\"");
        } else {
            try list.append(gpa, ch);
        }
    }
    try list.append(gpa, '"');
}

pub fn writePlaceholders(list: *ArrayList, gpa: Allocator, comptime count: usize) errors.ZiteError!void {
    comptime var i: usize = 1;
    inline while (i <= count) : (i += 1) {
        if (i != 1) try list.appendSlice(gpa, ", ");
        try list.append(gpa, '?');
        try list.print(gpa, "{}", .{i});
    }
}

pub fn writeInsertColumnList(list: *ArrayList, gpa: Allocator, comptime T: type, comptime m: meta.Meta) errors.ZiteError!void {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("writeInsertColumnList expects a struct type");
    const fields = ti.@"struct".fields;

    comptime var col_i: usize = 0;
    inline for (fields) |f| {
        const skip = comptime (m.skip_primary_key_on_insert and meta.isPk(f.name, m.primary_key));
        if (skip) continue;

        if (col_i != 0) try list.appendSlice(gpa, ", ");
        try writeIdent(list, gpa, f.name);
        col_i += 1;
    }
}

pub fn writeUpdateSetClause(list: *ArrayList, gpa: Allocator, comptime T: type, comptime m: meta.Meta) errors.ZiteError!void {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("writeUpdateSetClause expects a struct type");
    const fields = ti.@"struct".fields;

    comptime var set_i: usize = 0;
    inline for (fields) |f| {
        if (comptime meta.isPk(f.name, m.primary_key)) continue;

        if (set_i != 0) try list.appendSlice(gpa, ", ");
        try writeIdent(list, gpa, f.name);
        try list.appendSlice(gpa, "=?");
        try list.print(gpa, "{}", .{set_i + 1});
        set_i += 1;
    }
}
