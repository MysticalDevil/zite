const std = @import("std");
const internal = @import("../internal.zig");

const Db = internal.Db;
const Stmt = internal.Stmt;
const types = internal.types;

const meta = internal.meta;
const sqlutil = internal.sqlutil;
const errors = internal.errors;

fn pkFieldType(comptime T: type, comptime m: meta.Meta) type {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("pkFieldType expects a struct type");

    inline for (ti.@"struct".fields) |f| {
        if (comptime meta.isPk(f.name, m.primary_key)) return f.type;
    }
    @compileError("Type " ++ @typeName(T) ++ " missing primary key field: " + m.primary_key);
}

fn readValue(comptime FieldT: type, st: *Stmt, allocator: std.mem.Allocator, col: i32) errors.ZiteError!FieldT {
    if (FieldT == types.UnixMillis) {
        return .{ .value = st.colInt(col) };
    }
    if (FieldT == types.Text) {
        const owned = (try st.colTextOwned(allocator, col)) orelse return error.UnexpectedNull;
        return .{ .value = owned };
    }
    if (FieldT == types.Blob) {
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
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) {
                const owned = (try st.colTextOwned(allocator, col)) orelse return error.UnexpectedNull;
                return owned;
            }
            return error.UnexpectedColumnType;
        },

        else => return error.UnsupportedColumnType,
    }
}

pub fn Rows(comptime T: type) type {
    return struct {
        st: Stmt,
        allocator: std.mem.Allocator,
        done: bool = false,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            if (!self.done) {
                self.st.deinit();
                self.done = true;
            }
        }

        pub fn next(self: *Self) errors.ZiteError!?T {
            if (self.done) return null;

            const r = try self.st.step();
            if (r == .done) {
                self.st.deinit();
                self.done = true;
                return null;
            }

            var out: T = std.mem.zeroes(T);
            errdefer freeOwned(T, self.allocator, &out);

            const ti = @typeInfo(T);
            const fields = ti.@"struct".fields;

            comptime var col: usize = 0;
            inline for (fields) |f| {
                const v = try readValue(f.type, &self.st, self.allocator, @as(i32, @intCast(col)));
                @field(out, f.name) = v;
                col += 1;
            }

            return out;
        }
    };
}

pub fn RowsOwned(comptime T: type) type {
    return struct {
        rows: Rows(T),

        const Self = @This();

        pub fn deinit(self: *Self) void {
            self.rows.deinit();
        }

        pub fn next(self: *Self) errors.ZiteError!?Owned(T) {
            if (try self.rows.next()) |v| {
                return wrapOwned(T, self.rows.allocator, v);
            }
            return null;
        }
    };
}

pub fn insert(comptime T: type, db: *Db, entity: T) errors.ZiteError!i64 {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("insert expects a struct type");

    const m = comptime meta.getMeta(T);
    const ncols = comptime meta.insertableCount(T, m);
    if (ncols == 0) return error.NoInsertableFields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve(sqlutil.estimateInsertLen(T, m));

    try b.lit("INSERT INTO ");
    try b.ident(m.table);
    try b.lit(" (");
    try b.insertColumnList(T, m);
    try b.lit(") VALUES (");
    try b.placeholders(ncols);
    try b.lit(");");

    const sql = try buf.toOwnedSlice(db.allocator);
    defer db.allocator.free(sql);

    var st = try Stmt.init(db, sql);
    defer st.deinit();

    const fields = ti.@"struct".fields;
    var bind_i: i32 = 1;

    inline for (fields) |f| {
        const skip = comptime (m.skip_primary_key_on_insert and meta.isPk(f.name, m.primary_key));
        if (skip) continue;

        try st.bindOne(bind_i, @field(entity, f.name));
        bind_i += 1;
    }

    const r = try st.step();
    if (r != .done) return error.UnexpectedRowOnInsert;

    return db.lastInsertRowId();
}

pub fn update(comptime T: type, db: *Db, entity: T) errors.ZiteError!i32 {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("update expects a struct type");

    const m = comptime meta.getMeta(T);

    comptime {
        if (!meta.hasPrimaryKeyField(T, m)) {
            @compileError("Type " ++ @typeName(T) ++ " does not contain primary key field: " ++ m.primary_key);
        }
    }

    const set_count = comptime meta.updateSetCount(T, m);
    if (set_count == 0) return error.NoUpdatableFields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve(sqlutil.estimateUpdateLen(T, m));

    try b.lit("UPDATE ");
    try b.ident(m.table);
    try b.lit(" SET ");
    try b.updateSetClause(T, m);

    try b.lit(" WHERE ");
    try b.ident(m.primary_key);
    try b.lit("=?");
    try b.print("{}", .{set_count + 1});
    try b.lit(";");

    const sql = try buf.toOwnedSlice(db.allocator);
    defer db.allocator.free(sql);

    var st = try Stmt.init(db, sql);
    defer st.deinit();

    const fields = ti.@"struct".fields;
    var bind_i: i32 = 1;

    inline for (fields) |f| {
        if (comptime meta.isPk(f.name, m.primary_key)) continue;
        try st.bindOne(bind_i, @field(entity, f.name));
        bind_i += 1;
    }

    inline for (fields) |f| {
        if (comptime meta.isPk(f.name, m.primary_key)) {
            try st.bindOne(bind_i, @field(entity, f.name));
            break;
        }
    }

    const r = try st.step();
    if (r != .done) return error.UnexpectedRowOnUpdate;

    return db.changes();
}

/// SELECT *by pk*, return ?T; if it contains TEXT slice fields, they will be allocated
/// on the allocator, and the caller is responsible for freeing them.
pub fn getById(comptime T: type, db: *Db, allocator: std.mem.Allocator, id: pkFieldType(T, meta.getMeta(T))) errors.ZiteError!?T {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("getById expects a struct type");

    const m = comptime meta.getMeta(T);
    const fields = ti.@"struct".fields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve(sqlutil.estimateSelectLen(T, m, 0, true));

    try b.lit("SELECT ");

    comptime var i: usize = 0;
    inline for (fields) |f| {
        if (i != 0) try b.lit(", ");
        try b.ident(f.name);
        i += 1;
    }

    try b.lit(" FROM ");
    try b.ident(m.table);
    try b.lit(" WHERE ");
    try b.ident(m.primary_key);
    try b.lit("=?1 LIMIT 1;");

    const sql = try buf.toOwnedSlice(db.allocator);
    defer db.allocator.free(sql);

    var st = try Stmt.init(db, sql);
    defer st.deinit();

    try st.bindOne(1, id);

    const r = try st.step();
    if (r == .done) return null;

    var out: T = std.mem.zeroes(T);
    errdefer freeOwned(T, allocator, &out);

    comptime var col: usize = 0;
    inline for (fields) |f| {
        const v = try readValue(f.type, &st, allocator, @as(i32, @intCast(col)));
        @field(out, f.name) = v;
        col += 1;
    }

    const r2 = try st.step();
    if (r2 != .done) return error.UnexpectedExtraRows;

    return out;
}

pub fn getByIdOwned(comptime T: type, db: *Db, allocator: std.mem.Allocator, id: pkFieldType(T, meta.getMeta(T))) errors.ZiteError!?Owned(T) {
    if (try getById(T, db, allocator, id)) |v| {
        return wrapOwned(T, allocator, v);
    }
    return null;
}

/// Generic query: where_clause provided by caller (excluding “WHERE” prefix)
/// params is a tuple/struct (e.g., .{ 123, “alice” }), bound sequentially to ?1..?N
///
/// Returns ?T: null if no match is found; one record if found (TEXT slice fields allocate owned memory on the allocator)
pub fn findOne(comptime T: type, comptime P: type, db: *Db, allocator: std.mem.Allocator, where_clause: []const u8, params: P) errors.ZiteError!?T {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("findOne expects a struct type");

    const m = comptime meta.getMeta(T);
    const fields = ti.@"struct".fields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    const trimmed = std.mem.trim(u8, where_clause, " \t\r\n");
    try b.reserve(sqlutil.estimateSelectLen(T, m, trimmed.len, true));

    try b.lit("SELECT ");

    comptime var i: usize = 0;
    inline for (fields) |f| {
        if (i != 0) try b.lit(", ");
        try b.ident(f.name);
        i += 1;
    }

    try b.lit(" FROM ");
    try b.ident(m.table);

    if (trimmed.len != 0) {
        try b.lit(" WHERE ");
        try b.lit(trimmed);
    }

    try b.lit(" LIMIT 1;");

    const sql = try buf.toOwnedSlice(db.allocator);
    defer db.allocator.free(sql);

    var st = try Stmt.init(db, sql);
    defer st.deinit();

    try st.bindAll(params);

    const r = try st.step();
    if (r == .done) return null;

    var out: T = std.mem.zeroes(T);
    errdefer freeOwned(T, allocator, &out);

    comptime var col: usize = 0;
    inline for (fields) |f| {
        const v = try readValue(f.type, &st, allocator, @as(i32, @intCast(col)));
        @field(out, f.name) = v;
        col += 1;
    }

    const r2 = try st.step();
    if (r2 != .done) return error.UnexpectedExtraRows;

    return out;
}

pub fn findOneOwned(comptime T: type, comptime P: type, db: *Db, allocator: std.mem.Allocator, where_clause: []const u8, params: P) errors.ZiteError!?Owned(T) {
    if (try findOne(T, P, db, allocator, where_clause, params)) |v| {
        return wrapOwned(T, allocator, v);
    }
    return null;
}

pub fn Owned(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        value: T,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            freeOwned(T, self.allocator, &self.value);
        }
    };
}

fn wrapOwned(comptime T: type, allocator: std.mem.Allocator, v: T) Owned(T) {
    return .{ .allocator = allocator, .value = v };
}

pub fn freeOwned(comptime T: type, allocator: std.mem.Allocator, value: *T) void {
    const ti = @typeInfo(T);
    if (ti != .@"struct")
        @compileError("freeOwned expects a struct type");

    inline for (ti.@"struct".fields) |f| {
        freeField(f.type, allocator, &@field(value, f.name));
    }
}

fn freeField(comptime FieldT: type, allocator: std.mem.Allocator, field_ptr: anytype) void {
    if (FieldT == types.Text) {
        const s = field_ptr.value;
        if (s.len != 0) allocator.free(s);
        return;
    }
    if (FieldT == types.Blob) {
        const s = field_ptr.value;
        if (s.len != 0) allocator.free(s);
        return;
    }
    switch (@typeInfo(FieldT)) {
        .optional => |o| {
            if (field_ptr.*) |*v| {
                freeField(o.child, allocator, v);
            }
        },
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) {
                const s = field_ptr.*;
                if (s.len != 0) allocator.free(@constCast(s));
            }
        },
        else => {},
    }
}

pub fn findMany(comptime T: type, comptime P: type, db: *Db, allocator: std.mem.Allocator, where_clause: []const u8, params: P) errors.ZiteError!Rows(T) {
    const ti = @typeInfo(T);
    if (ti != .@"struct")
        @compileError("findMany expects a struct type");

    const m = comptime meta.getMeta(T);
    const fields = ti.@"struct".fields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    const trimmed = std.mem.trim(u8, where_clause, " \t\r\n");
    try b.reserve(sqlutil.estimateSelectLen(T, m, trimmed.len, false));

    try b.lit("SELECT ");

    comptime var i: usize = 0;
    inline for (fields) |f| {
        if (i != 0)
            try b.lit(", ");
        try b.ident(f.name);
        i += 1;
    }

    try b.lit(" FROM ");
    try b.ident(m.table);

    if (trimmed.len != 0) {
        try b.lit(" WHERE ");
        try b.lit(trimmed);
    }

    try b.lit(";");

    const sql = try buf.toOwnedSlice(db.allocator);
    defer db.allocator.free(sql);

    var st = try Stmt.init(db, sql);
    errdefer st.deinit();

    try st.bindAll(params);

    return Rows(T){
        .st = st,
        .allocator = allocator,
        .done = false,
    };
}

pub fn findManyOwned(comptime T: type, comptime P: type, db: *Db, allocator: std.mem.Allocator, where_clause: []const u8, params: P) errors.ZiteError!RowsOwned(T) {
    const r = try findMany(T, P, db, allocator, where_clause, params);
    return .{ .rows = r };
}
