const std = @import("std");

/// Declarative metadata for ORM mapping.
/// Declarative metadata for ORM mapping.
pub const Meta = struct {
    /// Table name.
    table: []const u8,
    /// Primary key column name.
    primary_key: []const u8 = "id",
    /// When true, omit PK from INSERTs (for AUTOINCREMENT).
    skip_primary_key_on_insert: bool = true,
};

/// Returns true when the field name matches the primary key.
pub fn isPk(comptime name: []const u8, comptime pk: []const u8) bool {
    return std.mem.eql(u8, name, pk);
}

/// Reads Meta from a struct type, with defaults.
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

/// True if the type defines a field matching the primary key.
pub fn hasPrimaryKeyField(comptime T: type, comptime m: Meta) bool {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("hasPrimaryKeyField expects a struct type");
    const fields = ti.@"struct".fields;

    inline for (fields) |f| {
        if (comptime isPk(f.name, m.primary_key)) return true;
    }
    return false;
}

/// Number of fields insertable for the given Meta.
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

/// Number of fields included in UPDATE SET clause.
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
