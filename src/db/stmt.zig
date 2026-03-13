const std = @import("std");
const raw = @import("../raw/mod.zig");
const types = @import("../core/types.zig");
const diag = @import("diag.zig");
const errors = @import("../core/errors.zig");
const sqlite_errors = @import("sqlite_errors.zig");

const Db = @import("db.zig").Db;
const db_ok = raw.SQLITE_OK;

/// Result of stepping a statement.
pub const StepResult = enum {
    /// A row is available to read.
    row,
    /// No more rows are available.
    done,
};

/// Prepared statement wrapper for sqlite3_stmt.
pub const Stmt = struct {
    /// Back-reference to the owning Db (for diagnostics and tracking).
    db: *Db,
    /// Opaque sqlite3 statement handle.
    stmt: raw.StmtHandle,
    /// Prevents double-finalize and enables Db tracking.
    finalized: bool = false,

    const Self = @This();

    /// Prepares a SQL statement. Must be finalized when no longer used.
    /// Caller owns the statement and must call `deinit()`.
    pub fn init(db: *Db, sql: []const u8) errors.ZiteError!Self {
        var stmt_opt: ?raw.StmtHandle = null;

        const n: i32 = @intCast(sql.len);
        const rc = raw.stmt.prepare(
            db.handle,
            sql.ptr,
            n,
            &stmt_opt,
        );
        if (rc != db_ok or stmt_opt == null) {
            diag.logSqlite(db, rc, "sqlite3_prepare_v2", sql);
            return sqlite_errors.mapSqliteRc(rc, error.SqlitePrepareFailed);
        }

        db.registerStmt();
        return .{ .db = db, .stmt = stmt_opt.? };
    }

    /// Finalizes the underlying SQLite statement (idempotent).
    pub fn finalize(self: *Self) void {
        if (self.finalized) return;
        _ = raw.stmt.finalize(self.stmt);
        self.finalized = true;
        self.db.unregisterStmt();
    }

    /// Alias for finalize() to match deinit patterns.
    pub fn deinit(self: *Self) void {
        self.finalize();
    }

    /// Resets the statement so it can be re-executed.
    pub fn reset(self: *Self) errors.ZiteError!void {
        const rc = raw.stmt.reset(self.stmt);
        if (rc != db_ok) {
            diag.logSqlite(self.db, rc, "sqlite3_reset", null);
            return sqlite_errors.mapSqliteRc(rc, error.SqliteResetFailed);
        }
    }

    /// Steps the statement. Returns .row for a row, .done when complete.
    /// The caller must read columns before stepping again.
    pub fn step(self: *Stmt) errors.ZiteError!StepResult {
        const rc = raw.stmt.step(self.stmt);
        return switch (rc) {
            raw.SQLITE_ROW => .row,
            raw.SQLITE_DONE => .done,
            else => blk: {
                diag.logSqlite(self.db, rc, "sqlite3_step", null);
                break :blk sqlite_errors.mapSqliteRc(rc, error.SqliteStepFailed);
            },
        };
    }

    // ---------- bind (1-based index) ----------
    /// Binds NULL to a 1-based parameter index.
    pub fn bindNull(self: *Self, idx: i32) errors.ZiteError!void {
        const rc = raw.stmt.bindNull(self.stmt, idx);
        if (rc != db_ok) {
            diag.logSqlite(self.db, rc, "sqlite3_bind_null", null);
            diag.logBind("null", idx);
            return sqlite_errors.mapSqliteRc(rc, error.SqliteBindFailed);
        }
    }

    /// Binds an integer to a 1-based parameter index.
    pub fn bindInt(self: *Self, idx: i32, value: i64) errors.ZiteError!void {
        const rc = raw.stmt.bindInt64(self.stmt, idx, value);
        if (rc != db_ok) {
            diag.logSqlite(self.db, rc, "sqlite3_bind_int64", null);
            diag.logBind("int64", idx);
            return sqlite_errors.mapSqliteRc(rc, error.SqliteBindFailed);
        }
    }

    /// Binds a double to a 1-based parameter index.
    pub fn bindFloat(self: *Self, idx: i32, value: f64) errors.ZiteError!void {
        const rc = raw.stmt.bindDouble(self.stmt, idx, @as(f64, @floatCast(value)));
        if (rc != db_ok) {
            diag.logSqlite(self.db, rc, "sqlite3_bind_double", null);
            diag.logBind("double", idx);
            return sqlite_errors.mapSqliteRc(rc, error.SqliteBindFailed);
        }
    }

    /// Binds a boolean to a 1-based parameter index.
    pub fn bindBool(self: *Self, idx: i32, value: bool) errors.ZiteError!void {
        const rc = raw.stmt.bindInt(self.stmt, idx, if (value) 1 else 0);
        if (rc != db_ok) {
            diag.logSqlite(self.db, rc, "sqlite3_bind_int", null);
            diag.logBind("int", idx);
            return sqlite_errors.mapSqliteRc(rc, error.SqliteBindFailed);
        }
    }

    /// Binds a UTF-8 string to a 1-based parameter index.
    pub fn bindText(self: *Self, idx: i32, value: []const u8) errors.ZiteError!void {
        const n: i32 = @intCast(value.len);
        const rc = raw.stmt.bindText(self.stmt, idx, value.ptr, n);
        if (rc != db_ok) {
            diag.logSqlite(self.db, rc, "sqlite3_bind_text", null);
            diag.logBind("text", idx);
            return sqlite_errors.mapSqliteRc(rc, error.SqliteBindFailed);
        }
    }

    /// Binds a blob to a 1-based parameter index.
    pub fn bindBlob(self: *Self, idx: i32, value: []const u8) errors.ZiteError!void {
        const n: i32 = @intCast(value.len);
        const rc = raw.stmt.bindBlob(self.stmt, idx, value.ptr, n);
        if (rc != db_ok) {
            diag.logSqlite(self.db, rc, "sqlite3_bind_blob", null);
            diag.logBind("blob", idx);
            return sqlite_errors.mapSqliteRc(rc, error.SqliteBindFailed);
        }
    }

    /// General Binding: Supports int/uint/bool/float/enum/optional(?T)
    /// plus types.OwnedText/types.OwnedBlob and types.EpochMillis.
    /// For TEXT/BLOB, use Owned* types (borrowed slices are not accepted).
    pub fn bindOne(self: *Self, idx: i32, value: anytype) errors.ZiteError!void {
        const T = @TypeOf(value);

        if (T == types.EpochMillis) {
            return self.bindInt(idx, value.value);
        }
        if (T == types.OwnedText) {
            return self.bindText(idx, value.value);
        }
        if (T == types.OwnedBlob) {
            return self.bindBlob(idx, value.value);
        }

        switch (@typeInfo(T)) {
            .optional => {
                if (value == null)
                    return self.bindNull(idx);
                return self.bindOne(idx, value.?);
            },
            .bool => return self.bindBool(idx, value),
            .int, .comptime_int => return self.bindInt(idx, value),
            .float, .comptime_float => return self.bindFloat(idx, value),
            .@"enum" => return self.bindInt(idx, @as(i64, @intCast(@intFromEnum(value)))),
            .pointer, .array => return error.UnsupportedBindType,
            else => return error.UnsupportedBindType,
        }
    }

    /// Bind multiple parameters at once: params should be passed as a tuple (anonymous struct): .{ a, b, c }
    /// Rules:
    /// - Parameter indices start at 1 (SQLite convention)
    /// - Supports tuples / regular structs (field order matters)
    pub fn bindAll(self: *Self, params: anytype) errors.ZiteError!void {
        const P = @TypeOf(params);
        const ti = @typeInfo(P);

        if (ti != .@"struct")
            return error.BindAllExpectedStructOrTuple;

        const s = ti.@"struct";
        inline for (s.fields, 0..) |f, i| {
            const v = @field(params, f.name);
            try self.bindOne(@as(i32, @intCast(i + 1)), v);
        }
    }

    // --------- column (0-based index, valid when step()==.row) ----------
    /// Reads an integer column value.
    pub fn colInt(self: *Self, col: i32) i64 {
        return raw.stmt.columnInt64(self.stmt, col);
    }

    /// Reads a boolean column value (0/1).
    pub fn colBool(self: *Self, col: i32) bool {
        return raw.stmt.columnInt(self.stmt, col) != 0;
    }

    /// Reads a double column value.
    pub fn colDouble(self: *Stmt, col: i32) f64 {
        return raw.stmt.columnDouble(self.stmt, col);
    }

    /// Returns true if the column is NULL.
    pub fn colIsNull(self: *Self, col: i32) bool {
        return raw.stmt.columnType(self.stmt, col) == raw.SQLITE_NULL;
    }

    /// Returns an owned copy of TEXT data (caller frees with allocator).
    pub fn colTextOwned(self: *Self, a: std.mem.Allocator, col: i32) errors.ZiteError!?[]u8 {
        const p = raw.stmt.columnText(self.stmt, col);
        if (p == null) return null;

        const n = raw.stmt.columnBytes(self.stmt, col);
        const len: usize = @intCast(n);

        const src: [*]const u8 = @ptrCast(p);
        const out = try a.alloc(u8, len);
        if (len != 0) std.mem.copyForwards(u8, out, src[0..len]);
        return out;
    }

    /// Returns an owned copy of BLOB data (caller frees with allocator).
    pub fn colBlobOwned(self: *Self, a: std.mem.Allocator, col: i32) errors.ZiteError!?[]u8 {
        const p = raw.stmt.columnBlob(self.stmt, col);
        if (p == null) return null;

        const n = raw.stmt.columnBytes(self.stmt, col);
        const len: usize = @intCast(n);

        const src: [*]const u8 = @ptrCast(p);
        const out = try a.alloc(u8, len);
        if (len != 0) std.mem.copyForwards(u8, out, src[0..len]);
        return out;
    }
};

test "stmt: bindInt and reset" {
    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    var st = try Stmt.init(&db, "SELECT ?1;");
    defer st.deinit();

    try st.bindInt(1, 1);
    try std.testing.expectEqual(StepResult.row, try st.step());
    try std.testing.expect(st.colBool(0));
    try std.testing.expectEqual(StepResult.done, try st.step());

    try st.reset();
    try st.bindInt(1, 0);
    try std.testing.expectEqual(StepResult.row, try st.step());
    try std.testing.expect(!st.colBool(0));
    try std.testing.expectEqual(StepResult.done, try st.step());
}

test "stmt: bindAll requires struct/tuple" {
    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    var st = try Stmt.init(&db, "SELECT ?1;");
    defer st.deinit();

    try std.testing.expectError(error.BindAllExpectedStructOrTuple, st.bindAll(@as(i64, 1)));
}

test "stmt: bindOne supports OwnedText/OwnedBlob/EpochMillis/optional" {
    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    var st = try Stmt.init(&db, "SELECT ?1, ?2, ?3, ?4;");
    defer st.deinit();

    var text = try types.OwnedText.fromConst(a, "zig");
    defer text.deinit(a);
    var blob = try types.OwnedBlob.fromConst(a, &[_]u8{ 1, 2 });
    defer blob.deinit(a);

    try st.bindOne(1, text);
    try st.bindOne(2, blob);
    try st.bindOne(3, types.EpochMillis{ .value = 123 });
    try st.bindOne(4, @as(?i64, null));

    try std.testing.expectEqual(StepResult.row, try st.step());
    const got_text = (try st.colTextOwned(a, 0)).?;
    defer a.free(got_text);
    try std.testing.expectEqualStrings("zig", got_text);

    const got_blob = (try st.colBlobOwned(a, 1)).?;
    defer a.free(got_blob);
    try std.testing.expect(std.mem.eql(u8, &[_]u8{ 1, 2 }, got_blob));

    try std.testing.expectEqual(@as(i64, 123), st.colInt(2));
    try std.testing.expect(st.colIsNull(3));
    try std.testing.expectEqual(StepResult.done, try st.step());
}

test "stmt: bindText/blob and colTextOwned/colBlobOwned on empty" {
    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    var st = try Stmt.init(&db, "SELECT ?1, ?2;");
    defer st.deinit();

    try st.bindText(1, "");
    try st.bindBlob(2, &.{});

    try std.testing.expectEqual(StepResult.row, try st.step());
    const t = (try st.colTextOwned(a, 0)).?;
    defer a.free(t);
    try std.testing.expectEqual(@as(usize, 0), t.len);

    const b_opt = try st.colBlobOwned(a, 1);
    if (b_opt) |b| {
        defer a.free(b);
        try std.testing.expectEqual(@as(usize, 0), b.len);
    }
    try std.testing.expectEqual(StepResult.done, try st.step());
}
