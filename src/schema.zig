const std = @import("std");
const meta = @import("meta.zig");
const sqlutil = @import("sqlutil.zig");

pub const CreateTableOptions = struct {
    table_name: []const u8,
    if_not_exists: bool = true,

    primary_key: ?[]const u8 = "id",

    autoincrement: bool = true,

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

    return switch (@typeInfo(T)) {
        .int, .comptime_int => "INTEGER",
        .float, .comptime_float => "REAL",
        .bool => "INTEGER",
        .@"enum" => "INTEGER",

        .pointer => |p| blk: {
            if (p.size == .slice and p.child == u8) break :blk "TEXT";
            break :blk "BLOB";
        },

        .array => |a| blk: {
            if (a.child == u8) break :blk "BLOB";
            break :blk "BLOB";
        },

        else => @compileError("Unsupported field type for SQLite schema: " ++ @typeName(T)),
    };
}

fn isPrimaryKeyField(comptime field_name: []const u8, opts: CreateTableOptions) bool {
    if (opts.primary_key) |pk| {
        return std.mem.eql(u8, field_name, pk);
    }
    return false;
}

pub fn createTableSql(allocator: std.mem.Allocator, comptime T: type, opts: CreateTableOptions) ![]u8 {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("createTableSql expects a struct type");

    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    const w0 = list.writer(allocator);
    const w = w0.any();

    try w.writeAll("CREATE TABLE ");
    if (opts.if_not_exists) try w.writeAll("IF NOT EXISTS ");

    try sqlutil.writeIdent(w, opts.table_name);

    try w.writeAll(" (\n");

    const fields = info.@"struct".fields;

    inline for (fields, 0..) |f, i| {
        try w.writeAll("  ");
        try sqlutil.writeIdent(w, f.name);
        try w.writeByte(' ');
        try w.writeAll(sqliteDeclaredType(f.type));

        const pk = isPrimaryKeyField(f.name, opts);
        if (pk) {
            try w.writeAll(" PRIMARY KEY");

            const base = unwrapOptionalType(f.type);
            const is_int = switch (@typeInfo(base)) {
                .int, .comptime_int => true,
                else => false,
            };
            if (opts.autoincrement and is_int) {
                try w.writeAll(" AUTOINCREMENT");
            }
        } else if (opts.not_null_by_default and !isOptional(f.type)) {
            try w.writeAll(" NOT NULL");
        }

        if (i + 1 != fields.len) {
            try w.writeAll(",\n");
        } else {
            try w.writeByte('\n');
        }
    }

    try w.writeAll(");");

    return try list.toOwnedSlice(allocator);
}

pub fn createTableSqlFromMeta(allocator: std.mem.Allocator, comptime T: type) ![]u8 {
    const m = comptime meta.getMeta(T);
    return createTableSql(allocator, T, .{
        .table_name = m.table,
        .primary_key = m.primary_key,
        .autoincrement = true,
        .if_not_exists = true,
    });
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
