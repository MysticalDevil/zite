const std = @import("std");
const meta = @import("../core/meta.zig");
const sqlutil = @import("../core/sqlutil.zig");
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");

/// Options that control CREATE TABLE generation.
pub const CreateTableOptions = struct {
    /// Table name used in CREATE TABLE.
    table_name: []const u8,
    /// Adds IF NOT EXISTS to CREATE TABLE.
    if_not_exists: bool = true,

    /// Primary key column name (null to disable).
    primary_key: ?[]const u8 = "id",

    /// Adds AUTOINCREMENT to integer primary keys.
    autoincrement: bool = true,

    /// Adds NOT NULL to non-optional fields.
    not_null_by_default: bool = true,
};

fn isOptional(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

fn unwrapOptionalType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .optional => |o| o.child,
        else => T,
    };
}

/// MVP Type Mapper:
/// - int/uint/isize/usize/bool/enum => INTEGER
/// - float => REAL
/// - []u8 / []const u8 =? TEXT
/// - [N]u8 => BLOB
fn sqliteDeclaredType(comptime T_in: type) []const u8 {
    const T = unwrapOptionalType(T_in);

    if (T == types.EpochMillis) return "INTEGER";
    if (T == types.OwnedText) return "TEXT";
    if (T == types.OwnedBlob) return "BLOB";

    return switch (@typeInfo(T)) {
        .int, .comptime_int => "INTEGER",
        .float, .comptime_float => "REAL",
        .bool => "INTEGER",
        .@"enum" => "INTEGER",

        else => @compileError("Unsupported field type for SQLite schema: " ++ @typeName(T)),
    };
}

fn isPrimaryKeyField(comptime field_name: []const u8, opts: CreateTableOptions) bool {
    if (opts.primary_key) |pk| {
        return std.mem.eql(u8, field_name, pk);
    }
    return false;
}

/// Builds a CREATE TABLE statement for the given struct type.
pub fn createTableSql(allocator: std.mem.Allocator, comptime T: type, opts: CreateTableOptions) errors.ZiteError![]u8 {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("createTableSql expects a struct type");

    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    var b = sqlutil.SqlBuilder.init(&list, allocator);
    try b.reserve(sqlutil.estCreateTableLen(T, opts.table_name));

    try b.lit("CREATE TABLE ");
    if (opts.if_not_exists) try b.lit("IF NOT EXISTS ");

    try b.ident(opts.table_name);

    try b.lit(" (\n");

    const fields = info.@"struct".fields;

    inline for (fields, 0..) |f, i| {
        try b.lit("  ");
        try b.ident(f.name);
        try b.byte(' ');
        try b.lit(sqliteDeclaredType(f.type));

        const pk = isPrimaryKeyField(f.name, opts);
        if (pk) {
            try b.lit(" PRIMARY KEY");

            const base = unwrapOptionalType(f.type);
            const is_int = switch (@typeInfo(base)) {
                .int, .comptime_int => true,
                else => false,
            };
            if (opts.autoincrement and is_int) {
                try b.lit(" AUTOINCREMENT");
            }
        } else if (opts.not_null_by_default and !isOptional(f.type)) {
            try b.lit(" NOT NULL");
        }

        if (i + 1 != fields.len) {
            try b.lit(",\n");
        } else {
            try b.byte('\n');
        }
    }

    try b.lit(");");

    return try list.toOwnedSlice(allocator);
}

/// Builds a CREATE TABLE statement using T.Meta.
pub fn createTableSqlFromMeta(allocator: std.mem.Allocator, comptime T: type) errors.ZiteError![]u8 {
    const m = comptime meta.getMeta(T);
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("createTableSqlFromMeta expects a struct type");

    comptime {
        if (meta.isSkipped(m.primary_key, m)) {
            @compileError("Primary key field is marked as skipped: " ++ m.primary_key);
        }
    }

    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    var b = sqlutil.SqlBuilder.init(&list, allocator);
    try b.reserve(sqlutil.estCreateTableLen(T, m.table));

    try b.lit("CREATE TABLE IF NOT EXISTS ");
    try b.ident(m.table);
    try b.lit(" (\n");

    const fields = info.@"struct".fields;
    comptime var emitted_fields: usize = 0;

    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) continue;

        if (emitted_fields != 0) try b.lit(",\n");

        try b.lit("  ");
        try b.ident(meta.columnName(f.name, m));
        try b.byte(' ');
        try b.lit(sqliteDeclaredType(f.type));

        const pk = meta.isPk(f.name, m.primary_key);
        if (pk) {
            try b.lit(" PRIMARY KEY");

            const base = unwrapOptionalType(f.type);
            const is_int = switch (@typeInfo(base)) {
                .int, .comptime_int => true,
                else => false,
            };
            if (is_int and m.skip_primary_key_on_insert) {
                try b.lit(" AUTOINCREMENT");
            }
        } else if (!isOptional(f.type)) {
            try b.lit(" NOT NULL");
        }

        emitted_fields += 1;
    }

    inline for (m.unique) |u| {
        if (u.len == 0) continue;
        try b.lit(",\n  UNIQUE (");
        comptime var ui: usize = 0;
        inline for (u) |field_name| {
            if (!fieldExists(T, field_name)) {
                @compileError("Unique constraint references unknown field: " ++ field_name);
            }
            if (comptime meta.isSkipped(field_name, m)) {
                @compileError("Unique constraint references skipped field: " ++ field_name);
            }
            if (ui != 0) try b.lit(", ");
            try b.ident(meta.columnName(field_name, m));
            ui += 1;
        }
        try b.lit(")");
    }

    try b.lit("\n);");

    return try list.toOwnedSlice(allocator);
}

fn fieldExists(comptime T: type, comptime name: []const u8) bool {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("fieldExists expects a struct type");
    inline for (ti.@"struct".fields) |f| {
        if (comptime std.mem.eql(u8, f.name, name)) return true;
    }
    return false;
}

test "createTableSql: basic struct -> CREATE TABLE with NOT NULL and PK" {
    const a = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,
        age: ?u32,
        created_at: i64,
    };

    const sql = try createTableSql(a, User, .{ .table_name = "users" });
    defer a.free(sql);

    const expected =
        \\CREATE TABLE IF NOT EXISTS "users" (
        \\  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  "name" TEXT NOT NULL,
        \\  "age" INTEGER,
        \\  "created_at" INTEGER NOT NULL
        \\);
    ;
    try std.testing.expectEqualStrings(expected, sql);
}

test "createTableSql: optional field should be nullable (no NOT NULL)" {
    const a = std.testing.allocator;

    const M = struct {
        id: i64,
        nick: ?[]const u8,
    };

    const sql = try createTableSql(a, M, .{ .table_name = "m" });
    defer a.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "\"nick\" TEXT NOT NULL") == null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "\"nick\" TEXT") != null);
}

test "createTableSql: if_not_exists false" {
    const a = std.testing.allocator;

    const T = struct { id: i64 };

    const sql = try createTableSql(a, T, .{ .table_name = "T", .if_not_exists = false });
    defer a.free(sql);

    try std.testing.expect(std.mem.startsWith(u8, sql, "CREATE TABLE \"T\""));
    try std.testing.expect(std.mem.indexOf(u8, sql, "IF NOT EXISTS") == null);
}

test "createTableSql: autoincrement only when PK is integer" {
    const a = std.testing.allocator;

    const NonIntPk = struct {
        id: []const u8,
        name: []const u8,
    };

    const sql = try createTableSql(a, NonIntPk, .{ .table_name = "x" });
    defer a.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "AUTOINCREMENT") == null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "\"id\" TEXT PRIMARY KEY") != null);
}

test "createTableSql: custom primary key file name" {
    const a = std.testing.allocator;

    const Doc = struct {
        doc_id: i64,
        title: []const u8,
    };

    const sql = try createTableSql(a, Doc, .{
        .table_name = "docs",
        .primary_key = "doc_id",
    });
    defer a.free(sql);
    try std.testing.expect(std.mem.indexOf(u8, sql, "\"doc_id\" INTEGER PRIMARY KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "\"title\" TEXT NOT NULL") != null);
}

test "createTableSqlFromMeta: rename, skip, unique" {
    const a = std.testing.allocator;

    const User = struct {
        id: i64,
        name: types.OwnedText,
        temp: i32,

        pub const Meta = .{
            .table = "users",
            .primary_key = "id",
            .skip = .{"temp"},
            .rename = .{.{ .field = "name", .column = "full_name" }},
            .unique = .{.{"name"}},
        };
    };

    const sql = try createTableSqlFromMeta(a, User);
    defer a.free(sql);

    const expected =
        \\CREATE TABLE IF NOT EXISTS "users" (
        \\  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  "full_name" TEXT NOT NULL,
        \\  UNIQUE ("full_name")
        \\);
    ;
    try std.testing.expectEqualStrings(expected, sql);
}

test "createTableSqlFromMeta: no autoincrement when Meta keeps PK on insert" {
    const a = std.testing.allocator;

    const User = struct {
        id: i64,
        name: types.OwnedText,

        pub const Meta = .{
            .table = "users",
            .primary_key = "id",
            .skip_primary_key_on_insert = false,
        };
    };

    const sql = try createTableSqlFromMeta(a, User);
    defer a.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "AUTOINCREMENT") == null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "\"id\" INTEGER PRIMARY KEY") != null);
}
