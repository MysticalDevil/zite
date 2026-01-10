const std = @import("std");

pub const Meta = struct {
    table: []const u8,
    primary_key: []const u8 = "id",
    skip_primary_key_on_insert: bool = true,
};

pub fn isPk(comptime name: []const u8, comptime pk: []const u8) bool {
    return std.mem.eql(u8, name, pk);
}

pub fn getMeta(comptime T: type) Meta {
    if (!@hasDecl(T, "Meta")) {
        @compileError("Type" ++ @typeName(T) ++ " must declar `pub const Meta = .{ .table = \"...\"}`");
    }

    const m = T.Meta;
    const MT = @TypeOf(m);

    if (!@hasField(MT, "table")) {
        @compileError("Type" ++ @typeName(T) ++ " Meta must contain field `.table`");
    }

    const table: []const u8 = m.table;
    const pk: []const u8 = if (@hasField(MT, "primary_key")) m.primary_key else "id";
    const skip_pk: bool = if (@hasField(MT, "skip_primary_key_on_insert")) m.skip_primary_key_on_insert else true;

    return .{
        .table = table,
        .primary_key = pk,
        .skip_primary_key_on_insert = skip_pk,
    };
}

pub fn hasPrimaryKeyField(comptime T: type, comptime m: Meta) bool {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("hasPrimaryKeyField expects a struct type");
    const fields = ti.@"struct".fields;

    inline for (fields) |f| {
        if (comptime isPk(f.name, m.primary_key)) return true;
    }
    return false;
}

pub fn insertableCount(comptime T: type, comptime m: Meta) usize {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("insertableCount expects a struct type");
    const fields = ti.@"struct".fields;

    comptime var n: usize = 0;
    inline for (fields) |f| {
        const skip = comptime (m.skip_primary_key_on_insert and isPk(f.name, m.primary_key));
        if (!skip) n += 1;
    }
    return n;
}

pub fn updateSetCount(comptime T: type, comptime m: Meta) usize {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("updateSetCount expects a struct type");
    const fields = ti.@"struct".fields;

    comptime var n: usize = 0;
    inline for (fields) |f| {
        if (comptime isPk(f.name, m.primary_key)) continue;
        n += 1;
    }
    return n;
}
