const std = @import("std");
const Db = @import("../db/db.zig").Db;
const Stmt = @import("../db/stmt.zig").Stmt;
const types = @import("../core/types.zig");

const meta = @import("../core/meta.zig");
const sqlutil = @import("../core/sqlutil.zig");
const errors = @import("../core/errors.zig");

fn pkFieldType(comptime T: type, comptime m: meta.Meta) type {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("pkFieldType expects a struct type");

    inline for (ti.@"struct".fields) |f| {
        if (comptime meta.isPk(f.name, m.primary_key)) return f.type;
    }
    @compileError("Type " ++ @typeName(T) ++ " missing primary key field: " + m.primary_key);
}

fn readValue(comptime FieldT: type, st: *Stmt, allocator: std.mem.Allocator, col: i32) errors.ZiteError!FieldT {
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

/// Iterator over query results, with optional owned field allocation.
/// Caller must `deinit()` if iteration is not completed.
pub fn Rows(comptime T: type) type {
    return struct {
        st: Stmt,
        allocator: std.mem.Allocator,
        done: bool = false,

        const Self = @This();
        const m = meta.getMeta(T);

        /// Finalizes the underlying statement if iteration is not complete.
        pub fn deinit(self: *Self) void {
            if (!self.done) {
                self.st.deinit();
                self.done = true;
            }
        }

        /// Returns the next row or null when complete. On error, finalizes
        /// the statement to avoid leaks. Returned rows must be freed with
        /// `freeOwnedRow` when they contain owned fields.
        pub fn next(self: *Self) errors.ZiteError!?T {
            if (self.done) return null;

            errdefer {
                self.st.deinit();
                self.done = true;
            }

            const r = try self.st.step();
            if (r == .done) {
                self.st.deinit();
                self.done = true;
                return null;
            }

            var out: T = std.mem.zeroes(T);
            errdefer freeOwnedRow(T, self.allocator, &out);

            const ti = @typeInfo(T);
            const fields = ti.@"struct".fields;

            comptime var col: usize = 0;
            inline for (fields) |f| {
                if (comptime meta.isSkipped(f.name, m)) continue;
                const v = try readValue(f.type, &self.st, self.allocator, @as(i32, @intCast(col)));
                @field(out, f.name) = v;
                col += 1;
            }

            return out;
        }
    };
}

/// Iterator returning OwnedRow(T), which frees TEXT/BLOB on deinit.
pub fn RowsOwned(comptime T: type) type {
    return struct {
        rows: Rows(T),

        const Self = @This();

        /// Finalizes the underlying statement if iteration is not complete.
        pub fn deinit(self: *Self) void {
            self.rows.deinit();
        }

        /// Returns the next owned row or null when complete.
        pub fn next(self: *Self) errors.ZiteError!?OwnedRow(T) {
            if (try self.rows.next()) |v| {
                return wrapOwnedRow(T, self.rows.allocator, v);
            }
            return null;
        }
    };
}

/// Inserts a record and returns the last insert rowid.
/// The caller is responsible for freeing any owned fields in `entity`.
pub fn insert(comptime T: type, db: *Db, entity: T) errors.ZiteError!i64 {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("insert expects a struct type");

    const m = comptime meta.getMeta(T);
    comptime {
        if (meta.isSkipped(m.primary_key, m)) {
            @compileError("Primary key field is marked as skipped: " ++ m.primary_key);
        }
    }
    const ncols = comptime meta.insertableCount(T, m);
    if (ncols == 0) return error.NoInsertableFields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve(sqlutil.estInsertLen(T, m));

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
        if (comptime meta.isSkipped(f.name, m)) continue;
        const skip = comptime (m.skip_primary_key_on_insert and meta.isPk(f.name, m.primary_key));
        if (skip) continue;

        try st.bindOne(bind_i, @field(entity, f.name));
        bind_i += 1;
    }

    const r = try st.step();
    if (r != .done) return error.UnexpectedRowOnInsert;

    return db.lastInsertRowId();
}

/// Updates a record by primary key; returns number of rows changed.
/// The caller is responsible for freeing any owned fields in `entity`.
pub fn update(comptime T: type, db: *Db, entity: T) errors.ZiteError!i32 {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("update expects a struct type");

    const m = comptime meta.getMeta(T);
    comptime {
        if (meta.isSkipped(m.primary_key, m)) {
            @compileError("Primary key field is marked as skipped: " ++ m.primary_key);
        }
    }

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

    const sql = try buf.toOwnedSlice(db.allocator);
    defer db.allocator.free(sql);

    var st = try Stmt.init(db, sql);
    defer st.deinit();

    const fields = ti.@"struct".fields;
    var bind_i: i32 = 1;

    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) continue;
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

/// Fetches a record by primary key, allocating TEXT/BLOB fields.
/// Returned rows must be freed with `freeOwnedRow` when they contain owned fields.
pub fn findById(comptime T: type, db: *Db, allocator: std.mem.Allocator, id: pkFieldType(T, meta.getMeta(T))) errors.ZiteError!?T {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("findById expects a struct type");

    const m = comptime meta.getMeta(T);
    comptime {
        if (meta.isSkipped(m.primary_key, m)) {
            @compileError("Primary key field is marked as skipped: " ++ m.primary_key);
        }
    }
    const fields = ti.@"struct".fields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    try b.reserve(sqlutil.estSelectLen(T, m, 0, true));

    try b.lit("SELECT ");

    comptime var i: usize = 0;
    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) continue;
        if (i != 0) try b.lit(", ");
        try b.ident(meta.columnName(f.name, m));
        i += 1;
    }

    try b.lit(" FROM ");
    try b.ident(m.table);
    try b.lit(" WHERE ");
    try b.ident(meta.pkColumnName(m));
    try b.lit("=?1 LIMIT 1;");

    const sql = try buf.toOwnedSlice(db.allocator);
    defer db.allocator.free(sql);

    var st = try Stmt.init(db, sql);
    defer st.deinit();

    try st.bindOne(1, id);

    const r = try st.step();
    if (r == .done) return null;

    var out: T = std.mem.zeroes(T);
    errdefer freeOwnedRow(T, allocator, &out);

    comptime var col: usize = 0;
    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) continue;
        const v = try readValue(f.type, &st, allocator, @as(i32, @intCast(col)));
        @field(out, f.name) = v;
        col += 1;
    }

    const r2 = try st.step();
    if (r2 != .done) return error.UnexpectedExtraRows;

    return out;
}

/// Fetches a record by primary key into OwnedRow(T).
/// Returned row owns any TEXT/BLOB and must be deinitialized.
pub fn findByIdOwned(comptime T: type, db: *Db, allocator: std.mem.Allocator, id: pkFieldType(T, meta.getMeta(T))) errors.ZiteError!?OwnedRow(T) {
    if (try findById(T, db, allocator, id)) |v| {
        return wrapOwnedRow(T, allocator, v);
    }
    return null;
}

/// Executes a WHERE query and returns at most one row.
/// where_clause is provided by caller (excluding "WHERE" prefix).
/// params is a tuple/struct (e.g., .{ 123, "alice" }), bound to ?1..?N.
/// Returned rows must be freed with `freeOwnedRow` when they contain owned fields.
pub fn findOne(comptime T: type, comptime P: type, db: *Db, allocator: std.mem.Allocator, where_clause: []const u8, params: P) errors.ZiteError!?T {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("findOne expects a struct type");

    const m = comptime meta.getMeta(T);
    comptime {
        if (meta.isSkipped(m.primary_key, m)) {
            @compileError("Primary key field is marked as skipped: " ++ m.primary_key);
        }
    }
    const fields = ti.@"struct".fields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    const trimmed = std.mem.trim(u8, where_clause, " \t\r\n");
    try b.reserve(sqlutil.estSelectLen(T, m, trimmed.len, true));

    try b.lit("SELECT ");

    comptime var i: usize = 0;
    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) continue;
        if (i != 0) try b.lit(", ");
        try b.ident(meta.columnName(f.name, m));
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
    errdefer freeOwnedRow(T, allocator, &out);

    comptime var col: usize = 0;
    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) continue;
        const v = try readValue(f.type, &st, allocator, @as(i32, @intCast(col)));
        @field(out, f.name) = v;
        col += 1;
    }

    const r2 = try st.step();
    if (r2 != .done) return error.UnexpectedExtraRows;

    return out;
}

/// Wrapper that frees owned TEXT/BLOB fields via deinit().
pub fn OwnedRow(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        value: T,

        const Self = @This();

        /// Frees owned TEXT/BLOB fields for the row.
        pub fn deinit(self: *Self) void {
            freeOwnedRow(T, self.allocator, &self.value);
        }
    };
}

fn wrapOwnedRow(comptime T: type, allocator: std.mem.Allocator, v: T) OwnedRow(T) {
    return .{ .allocator = allocator, .value = v };
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

/// Executes a WHERE query and returns an iterator over rows.
/// Rows must be freed with `freeOwnedRow` when they contain owned fields.
pub fn findMany(comptime T: type, comptime P: type, db: *Db, allocator: std.mem.Allocator, where_clause: []const u8, params: P) errors.ZiteError!Rows(T) {
    const ti = @typeInfo(T);
    if (ti != .@"struct")
        @compileError("findMany expects a struct type");

    const m = comptime meta.getMeta(T);
    comptime {
        if (meta.isSkipped(m.primary_key, m)) {
            @compileError("Primary key field is marked as skipped: " ++ m.primary_key);
        }
    }
    const fields = ti.@"struct".fields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    var b = sqlutil.SqlBuilder.init(&buf, db.allocator);
    const trimmed = std.mem.trim(u8, where_clause, " \t\r\n");
    try b.reserve(sqlutil.estSelectLen(T, m, trimmed.len, false));

    try b.lit("SELECT ");

    comptime var i: usize = 0;
    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) continue;
        if (i != 0)
            try b.lit(", ");
        try b.ident(meta.columnName(f.name, m));
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

/// Executes a WHERE query and returns an iterator of OwnedRow(T) rows.
pub fn findManyOwned(comptime T: type, comptime P: type, db: *Db, allocator: std.mem.Allocator, where_clause: []const u8, params: P) errors.ZiteError!RowsOwned(T) {
    const r = try findMany(T, P, db, allocator, where_clause, params);
    return .{ .rows = r };
}
