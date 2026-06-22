const std = @import("std");
const orm_root = @import("../root.zig");
const Driver = @import("../../driver/sqlite3.zig");
const Db = @import("../../db/db.zig").Db(Driver);
const Stmt = @import("../../db/stmt.zig").Stmt(Driver);
const meta = @import("../../core/meta.zig");
const sqlutil = @import("../../core/sqlutil.zig");
const errors = @import("../../core/errors.zig");
const reflect = @import("../../core/reflect.zig");
const FindManyOptions = orm_root.FindManyOptions;

fn appendSelectColumns(
    comptime T: type,
    comptime m: meta.Meta,
    b: *sqlutil.SqlBuilder,
) errors.AllocError!void {
    const ti = @typeInfo(T);
    if (ti != .@"struct") {
        @compileError("appendSelectColumns expects a struct type");
    }

    const fields = comptime reflect.structFields(T);
    comptime var i: usize = 0;
    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) {
            continue;
        }
        if (i != 0) {
            try b.lit(", ");
        }
        try b.ident(meta.columnName(f.name, m));
        i += 1;
    }
}

fn toOwnedSql(
    db: *Db,
    buf: *std.ArrayList(u8),
) errors.AllocError![]u8 {
    return try buf.toOwnedSlice(db.allocator);
}

pub fn buildExistsByIdSql(comptime T: type, db: *Db) errors.AllocError![]u8 {
    if (@typeInfo(T) != .@"struct") {
        @compileError("buildExistsByIdSql expects a struct type");
    }
    const m = comptime meta.getMeta(T);

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve("SELECT 1 FROM ".len + m.table.len + " WHERE ".len + m.primary_key.len + "=?1 LIMIT 1;".len);

    try b.lit("SELECT 1 FROM ");
    try b.ident(m.table);
    try b.lit(" WHERE ");
    try b.ident(meta.pkColumnName(m));
    try b.lit("=?1 LIMIT 1;");
    return toOwnedSql(db, &buf);
}

pub fn buildInsertSql(comptime T: type, db: *Db) errors.AllocError![]u8 {
    const m = comptime meta.getMeta(T);
    const ncols = comptime meta.insertableCount(T, m);

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve(sqlutil.estInsertLen(T, m));

    try b.lit("INSERT INTO ");
    try b.ident(m.table);
    try b.lit(" (");
    try b.insertColumnList(T, m);
    try b.lit(") VALUES (");
    try b.placeholders(ncols);
    try b.lit(");");
    return toOwnedSql(db, &buf);
}

pub fn buildUpdateSql(comptime T: type, db: *Db) errors.AllocError![]u8 {
    const m = comptime meta.getMeta(T);
    const set_count = comptime meta.updateSetCount(T, m);

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve(sqlutil.estUpdateLen(T, m));

    try b.lit("UPDATE ");
    try b.ident(m.table);
    try b.lit(" SET ");
    try b.updateSetClause(T, m);
    try b.lit(" WHERE ");
    try b.ident(meta.pkColumnName(m));
    try b.lit("=?");
    try b.print("{}", .{set_count + 1});
    try b.lit(";");
    return toOwnedSql(db, &buf);
}

pub fn buildDeleteByIdSql(comptime T: type, db: *Db) errors.AllocError![]u8 {
    if (@typeInfo(T) != .@"struct") {
        @compileError("buildDeleteByIdSql expects a struct type");
    }
    const m = comptime meta.getMeta(T);

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve("DELETE FROM ".len + m.table.len + " WHERE ".len + m.primary_key.len + 2 + "=?1;".len);

    try b.lit("DELETE FROM ");
    try b.ident(m.table);
    try b.lit(" WHERE ");
    try b.ident(meta.pkColumnName(m));
    try b.lit("=?1;");
    return toOwnedSql(db, &buf);
}

pub fn buildDeleteWhereSql(comptime T: type, db: *Db, where_clause: []const u8) errors.SqlBuildError![]u8 {
    if (@typeInfo(T) != .@"struct") {
        @compileError("buildDeleteWhereSql expects a struct type");
    }
    const m = comptime meta.getMeta(T);
    const trimmed = std.mem.trim(u8, where_clause, " \t\r\n");
    if (trimmed.len == 0) {
        return error.EmptyWhereClause;
    }

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve("DELETE FROM ".len + m.table.len + " WHERE ".len + trimmed.len + ";".len);

    try b.lit("DELETE FROM ");
    try b.ident(m.table);
    try b.lit(" WHERE ");
    try b.lit(trimmed);
    try b.lit(";");
    return toOwnedSql(db, &buf);
}

pub fn buildFindByIdSql(comptime T: type, db: *Db) errors.AllocError![]u8 {
    if (@typeInfo(T) != .@"struct") {
        @compileError("buildFindByIdSql expects a struct type");
    }
    const m = comptime meta.getMeta(T);

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve(sqlutil.estSelectLen(T, m, 0, true));

    try b.lit("SELECT ");
    try appendSelectColumns(T, m, &b);
    try b.lit(" FROM ");
    try b.ident(m.table);
    try b.lit(" WHERE ");
    try b.ident(meta.pkColumnName(m));
    try b.lit("=?1 LIMIT 1;");
    return toOwnedSql(db, &buf);
}

pub fn buildFindOneSql(comptime T: type, db: *Db, where_clause: []const u8) errors.AllocError![]u8 {
    if (@typeInfo(T) != .@"struct") {
        @compileError("buildFindOneSql expects a struct type");
    }
    const m = comptime meta.getMeta(T);
    const trimmed = std.mem.trim(u8, where_clause, " \t\r\n");

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve(sqlutil.estSelectLen(T, m, trimmed.len, true));

    try b.lit("SELECT ");
    try appendSelectColumns(T, m, &b);
    try b.lit(" FROM ");
    try b.ident(m.table);
    if (trimmed.len != 0) {
        try b.lit(" WHERE ");
        try b.lit(trimmed);
    }
    try b.lit(" LIMIT 1;");
    return toOwnedSql(db, &buf);
}

pub fn buildFindManySql(
    comptime T: type,
    db: *Db,
    where_clause: []const u8,
    opts: FindManyOptions,
) errors.AllocError![]u8 {
    if (@typeInfo(T) != .@"struct") {
        @compileError("buildFindManySql expects a struct type");
    }
    const m = comptime meta.getMeta(T);
    const trimmed = std.mem.trim(u8, where_clause, " \t\r\n");
    const default_order = std.mem.trim(u8, m.order_by, " \t\r\n");
    const trimmed_order = if (opts.order_by) |v| std.mem.trim(u8, v, " \t\r\n") else default_order;

    const order_extra: usize = if (trimmed_order.len != 0) " ORDER BY ".len + trimmed_order.len else 0;
    const limit_extra: usize = if (opts.limit != null) " LIMIT ".len + 20 else 0;
    const offset_extra: usize = if (opts.offset != null)
        if (opts.limit != null) " OFFSET ".len + 20 else " LIMIT -1 OFFSET ".len + 20
    else
        0;

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve(sqlutil.estSelectLen(T, m, trimmed.len, false) + order_extra + limit_extra + offset_extra);

    try b.lit("SELECT ");
    try appendSelectColumns(T, m, &b);
    try b.lit(" FROM ");
    try b.ident(m.table);
    if (trimmed.len != 0) {
        try b.lit(" WHERE ");
        try b.lit(trimmed);
    }
    if (trimmed_order.len != 0) {
        try b.lit(" ORDER BY ");
        try b.lit(trimmed_order);
    }
    if (opts.limit) |limit| {
        try b.lit(" LIMIT ");
        try b.print("{}", .{limit});
    }
    if (opts.offset) |offset| {
        if (opts.limit == null) {
            try b.lit(" LIMIT -1");
        }
        try b.lit(" OFFSET ");
        try b.print("{}", .{offset});
    }
    try b.lit(";");
    return toOwnedSql(db, &buf);
}

pub fn prepareOwnedSql(db: *Db, sql: []const u8) errors.StmtError!Stmt {
    defer db.allocator.free(sql);
    return try Stmt.init(db, sql);
}

test "engine.sql: buildDeleteWhereSql rejects empty clause" {
    const Row = struct {
        id: i64,

        pub const Meta = .{
            .table = "users",
            .primary_key = "id",
        };
    };

    var db = try Db.open(std.testing.allocator, ":memory:");
    defer db.deinit();

    try std.testing.expectError(error.EmptyWhereClause, buildDeleteWhereSql(Row, &db, " \t "));
}
