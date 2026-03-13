const std = @import("std");
const Db = @import("../db/db.zig").Db;
const Stmt = @import("../db/stmt.zig").Stmt;
const types = @import("../core/types.zig");
const engine = @import("engine.zig");

const meta = @import("../core/meta.zig");
const errors = @import("../core/errors.zig");

/// Result tag returned by upsert.
pub const UpsertResult = enum {
    inserted,
    updated,
};

/// Optional clauses for findMany queries.
pub const FindManyOptions = engine.sql.FindManyOptions;

fn pkFieldType(comptime T: type, comptime m: meta.Meta) type {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("pkFieldType expects a struct type");

    inline for (ti.@"struct".fields) |f| {
        if (comptime meta.isPk(f.name, m.primary_key)) return f.type;
    }
    @compileError("Type " ++ @typeName(T) ++ " missing primary key field: " ++ m.primary_key);
}

fn pkFieldValue(comptime T: type, entity: T, comptime m: meta.Meta) pkFieldType(T, m) {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("pkFieldValue expects a struct type");

    inline for (ti.@"struct".fields) |f| {
        if (comptime meta.isPk(f.name, m.primary_key)) {
            return @field(entity, f.name);
        }
    }
    @compileError("Type " ++ @typeName(T) ++ " missing primary key field: " ++ m.primary_key);
}

fn existsById(comptime T: type, db: *Db, id: pkFieldType(T, meta.getMeta(T))) errors.ZiteError!bool {
    if (@typeInfo(T) != .@"struct") @compileError("existsById expects a struct type");

    const m = comptime meta.getMeta(T);
    comptime {
        if (meta.isSkipped(m.primary_key, m)) {
            @compileError("Primary key field is marked as skipped: " ++ m.primary_key);
        }
    }
    const sql = try engine.sql.buildExistsByIdSql(T, db);
    var st = try engine.sql.prepareOwnedSql(db, sql);
    defer st.deinit();
    try st.bindOne(1, id);
    return engine.exec.stepIsRow(&st);
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
            errdefer engine.row.freeOwnedRow(T, self.allocator, &out);

            const ti = @typeInfo(T);
            const fields = ti.@"struct".fields;

            comptime var col: usize = 0;
            inline for (fields) |f| {
                if (comptime meta.isSkipped(f.name, m)) continue;
                const v = try engine.row.readValue(f.type, &self.st, self.allocator, @as(i32, @intCast(col)));
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

    const sql = try engine.sql.buildInsertSql(T, db);
    var st = try engine.sql.prepareOwnedSql(db, sql);
    defer st.deinit();
    try engine.exec.bindInsertValues(T, &st, entity);
    try engine.exec.stepExpectDone(&st, error.UnexpectedRowOnInsert);

    return db.lastInsertRowId();
}

/// Inserts many records and returns the number of inserted rows.
/// Reuses one prepared statement for efficiency.
/// The caller is responsible for freeing any owned fields in `entities`.
pub fn insertMany(comptime T: type, db: *Db, entities: []const T) errors.ZiteError!usize {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("insertMany expects a struct type");
    if (entities.len == 0) return 0;

    const m = comptime meta.getMeta(T);
    comptime {
        if (meta.isSkipped(m.primary_key, m)) {
            @compileError("Primary key field is marked as skipped: " ++ m.primary_key);
        }
    }
    const ncols = comptime meta.insertableCount(T, m);
    if (ncols == 0) return error.NoInsertableFields;

    const sql = try engine.sql.buildInsertSql(T, db);
    var st = try engine.sql.prepareOwnedSql(db, sql);
    defer st.deinit();
    for (entities, 0..) |entity, i| {
        try engine.exec.resetForReuse(&st, i);
        try engine.exec.bindInsertValues(T, &st, entity);
        try engine.exec.stepExpectDone(&st, error.UnexpectedRowOnInsert);
    }

    return entities.len;
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

    const sql = try engine.sql.buildUpdateSql(T, db);
    var st = try engine.sql.prepareOwnedSql(db, sql);
    defer st.deinit();
    try engine.exec.bindUpdateValues(T, &st, entity);
    try engine.exec.stepExpectDone(&st, error.UnexpectedRowOnUpdate);

    return db.changes();
}

/// Upserts a record by primary key.
/// If a row with the same PK exists, updates it; otherwise inserts a new row.
/// The caller is responsible for freeing any owned fields in `entity`.
pub fn upsert(comptime T: type, db: *Db, entity: T) errors.ZiteError!UpsertResult {
    if (@typeInfo(T) != .@"struct") @compileError("upsert expects a struct type");
    const m = comptime meta.getMeta(T);
    const pk_value = pkFieldValue(T, entity, m);

    if (try existsById(T, db, pk_value)) {
        _ = try update(T, db, entity);
        return .updated;
    }

    _ = try insert(T, db, entity);
    return .inserted;
}

/// Deletes a record by primary key; returns number of rows changed.
pub fn deleteById(comptime T: type, db: *Db, id: pkFieldType(T, meta.getMeta(T))) errors.ZiteError!i32 {
    if (@typeInfo(T) != .@"struct") @compileError("deleteById expects a struct type");

    const m = comptime meta.getMeta(T);
    comptime {
        if (meta.isSkipped(m.primary_key, m)) {
            @compileError("Primary key field is marked as skipped: " ++ m.primary_key);
        }
    }

    const sql = try engine.sql.buildDeleteByIdSql(T, db);
    var st = try engine.sql.prepareOwnedSql(db, sql);
    defer st.deinit();

    try st.bindOne(1, id);
    try engine.exec.stepExpectDone(&st, error.UnexpectedRowOnDelete);

    return db.changes();
}

/// Deletes records matching a WHERE clause; returns number of rows changed.
/// where_clause is provided by caller (excluding "WHERE" prefix).
/// params is a tuple/struct (e.g., .{ 123, "alice" }), bound to ?1..?N.
pub fn deleteWhere(comptime T: type, comptime P: type, db: *Db, where_clause: []const u8, params: P) errors.ZiteError!i32 {
    if (@typeInfo(T) != .@"struct") @compileError("deleteWhere expects a struct type");
    const trimmed = std.mem.trim(u8, where_clause, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyWhereClause;

    const sql = try engine.sql.buildDeleteWhereSql(T, db, where_clause);
    var st = try engine.sql.prepareOwnedSql(db, sql);
    defer st.deinit();

    try st.bindAll(params);
    try engine.exec.stepExpectDone(&st, error.UnexpectedRowOnDelete);

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
    const sql = try engine.sql.buildFindByIdSql(T, db);
    var st = try engine.sql.prepareOwnedSql(db, sql);
    defer st.deinit();

    try st.bindOne(1, id);

    const r = try st.step();
    if (r == .done) return null;

    var out = try engine.row.readStruct(T, &st, allocator);

    const r2 = try st.step();
    if (r2 != .done) {
        engine.row.freeOwnedRow(T, allocator, &out);
        return error.UnexpectedExtraRows;
    }

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

    const sql = try engine.sql.buildFindOneSql(T, db, where_clause);
    var st = try engine.sql.prepareOwnedSql(db, sql);
    defer st.deinit();

    try st.bindAll(params);

    const r = try st.step();
    if (r == .done) return null;

    var out = try engine.row.readStruct(T, &st, allocator);

    const r2 = try st.step();
    if (r2 != .done) {
        engine.row.freeOwnedRow(T, allocator, &out);
        return error.UnexpectedExtraRows;
    }

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
            engine.row.freeOwnedRow(T, self.allocator, &self.value);
        }
    };
}

fn wrapOwnedRow(comptime T: type, allocator: std.mem.Allocator, v: T) OwnedRow(T) {
    return .{ .allocator = allocator, .value = v };
}

/// Frees owned TEXT/BLOB fields for a value.
pub fn freeOwnedRow(comptime T: type, allocator: std.mem.Allocator, value: *T) void {
    engine.row.freeOwnedRow(T, allocator, value);
}

/// Executes a WHERE query and returns an iterator over rows.
/// Rows must be freed with `freeOwnedRow` when they contain owned fields.
pub fn findMany(comptime T: type, comptime P: type, db: *Db, allocator: std.mem.Allocator, where_clause: []const u8, params: P) errors.ZiteError!Rows(T) {
    return findManyWithOptions(T, P, db, allocator, where_clause, params, .{});
}

/// Executes a WHERE query and returns an iterator over rows with optional
/// ORDER BY / LIMIT / OFFSET clauses.
/// Rows must be freed with `freeOwnedRow` when they contain owned fields.
pub fn findManyWithOptions(
    comptime T: type,
    comptime P: type,
    db: *Db,
    allocator: std.mem.Allocator,
    where_clause: []const u8,
    params: P,
    opts: FindManyOptions,
) errors.ZiteError!Rows(T) {
    const ti = @typeInfo(T);
    if (ti != .@"struct")
        @compileError("findMany expects a struct type");

    const m = comptime meta.getMeta(T);
    comptime {
        if (meta.isSkipped(m.primary_key, m)) {
            @compileError("Primary key field is marked as skipped: " ++ m.primary_key);
        }
    }

    const sql = try engine.sql.buildFindManySql(T, db, where_clause, opts);
    var st = try engine.sql.prepareOwnedSql(db, sql);
    errdefer st.deinit();

    try st.bindAll(params);

    return Rows(T){
        .st = st,
        .allocator = allocator,
        .done = false,
    };
}

test "mapper: freeOwnedRow frees owned fields and optionals" {
    const Row = struct {
        name: types.OwnedText,
        data: ?types.OwnedBlob,
        count: i64,
    };

    const a = std.testing.allocator;
    const name = try types.OwnedText.fromConst(a, "alice");
    const blob = try types.OwnedBlob.fromConst(a, &[_]u8{ 1, 2, 3 });

    var row = Row{
        .name = name,
        .data = blob,
        .count = 1,
    };
    freeOwnedRow(Row, a, &row);
    try std.testing.expectEqual(@as(usize, 0), row.name.value.len);
    try std.testing.expectEqual(@as(usize, 0), row.data.?.value.len);
}

test "mapper: OwnedRow deinit frees inner owned fields" {
    const Row = struct {
        name: types.OwnedText,
        data: ?types.OwnedBlob,
    };

    const a = std.testing.allocator;
    const name = try types.OwnedText.fromConst(a, "bob");
    const row = Row{
        .name = name,
        .data = null,
    };

    var owned = OwnedRow(Row){ .allocator = a, .value = row };
    owned.deinit();
    try std.testing.expectEqual(@as(usize, 0), owned.value.name.value.len);
    try std.testing.expect(owned.value.data == null);
}

test "mapper: Rows deinit finalizes early" {
    const Row = struct {
        id: i64,
        name: types.OwnedText,

        pub const Meta = .{
            .table = "users",
            .primary_key = "id",
            .skip_primary_key_on_insert = true,
        };
    };

    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec(
        \\CREATE TABLE users(
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL
        \\);
    );

    var name = try types.OwnedText.fromConst(a, "alice");
    defer name.deinit(a);
    _ = try insert(Row, &db, .{ .id = 0, .name = name });

    const P = @TypeOf(.{@as(i64, 0)});
    var rows = try findMany(Row, P, &db, a, "\"id\">?1", .{@as(i64, 0)});
    rows.deinit();
}

test "mapper: insert propagates OutOfMemory from SQL building" {
    const Row = struct {
        id: i64,
        name: types.OwnedText,

        pub const Meta = .{
            .table = "users",
            .primary_key = "id",
            .skip_primary_key_on_insert = true,
        };
    };

    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec(
        \\CREATE TABLE users(
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL
        \\);
    );

    var name = try types.OwnedText.fromConst(a, "alice");
    defer name.deinit(a);

    var failing_state = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    db.allocator = failing_state.allocator();

    try std.testing.expectError(error.OutOfMemory, insert(Row, &db, .{
        .id = 0,
        .name = name,
    }));
}

test "mapper: findMany propagates OutOfMemory from SQL building" {
    const Row = struct {
        id: i64,
        name: types.OwnedText,

        pub const Meta = .{
            .table = "users",
            .primary_key = "id",
            .skip_primary_key_on_insert = true,
        };
    };

    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec(
        \\CREATE TABLE users(
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL
        \\);
    );

    var name = try types.OwnedText.fromConst(a, "alice");
    defer name.deinit(a);
    _ = try insert(Row, &db, .{ .id = 0, .name = name });

    var failing_state = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    db.allocator = failing_state.allocator();

    const P = @TypeOf(.{@as(i64, 0)});
    try std.testing.expectError(
        error.OutOfMemory,
        findMany(Row, P, &db, a, "\"id\">?1", .{@as(i64, 0)}),
    );
}

test "mapper: update propagates OutOfMemory from SQL building" {
    const Row = struct {
        id: i64,
        name: types.OwnedText,

        pub const Meta = .{
            .table = "users",
            .primary_key = "id",
            .skip_primary_key_on_insert = true,
        };
    };

    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec(
        \\CREATE TABLE users(
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL
        \\);
    );

    var name1 = try types.OwnedText.fromConst(a, "alice");
    defer name1.deinit(a);
    const id = try insert(Row, &db, .{ .id = 0, .name = name1 });

    var name2 = try types.OwnedText.fromConst(a, "alice2");
    defer name2.deinit(a);

    var failing_state = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    db.allocator = failing_state.allocator();

    try std.testing.expectError(error.OutOfMemory, update(Row, &db, .{
        .id = id,
        .name = name2,
    }));
}

test "mapper: deleteById propagates OutOfMemory from SQL building" {
    const Row = struct {
        id: i64,
        name: types.OwnedText,

        pub const Meta = .{
            .table = "users",
            .primary_key = "id",
            .skip_primary_key_on_insert = true,
        };
    };

    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec(
        \\CREATE TABLE users(
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL
        \\);
    );

    var name = try types.OwnedText.fromConst(a, "alice");
    defer name.deinit(a);
    const id = try insert(Row, &db, .{ .id = 0, .name = name });

    var failing_state = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    db.allocator = failing_state.allocator();

    try std.testing.expectError(error.OutOfMemory, deleteById(Row, &db, id));
}

test "mapper: deleteWhere propagates OutOfMemory from SQL building" {
    const Row = struct {
        id: i64,
        name: types.OwnedText,

        pub const Meta = .{
            .table = "users",
            .primary_key = "id",
            .skip_primary_key_on_insert = true,
        };
    };

    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec(
        \\CREATE TABLE users(
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL
        \\);
    );

    var name = try types.OwnedText.fromConst(a, "alice");
    defer name.deinit(a);
    _ = try insert(Row, &db, .{ .id = 0, .name = name });

    var failing_state = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    db.allocator = failing_state.allocator();

    try std.testing.expectError(
        error.OutOfMemory,
        deleteWhere(Row, @TypeOf(.{@as(i64, 0)}), &db, "\"id\">?1", .{@as(i64, 0)}),
    );
}

/// Executes a WHERE query and returns an iterator of OwnedRow(T) rows.
pub fn findManyOwned(comptime T: type, comptime P: type, db: *Db, allocator: std.mem.Allocator, where_clause: []const u8, params: P) errors.ZiteError!RowsOwned(T) {
    const r = try findMany(T, P, db, allocator, where_clause, params);
    return .{ .rows = r };
}
