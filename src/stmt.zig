const std = @import("std");
const db_mod = @import("db.zig");

pub const c = db_mod.c;
pub const Db = db_mod.Db;
const db_ok = c.SQLITE_OK;

pub const StepResult = enum { row, done };

/// sqlite3_bind_text/blob destructor parameters:
/// SQLITE_TRANSIENT == (sqlite3_destructor_type)-1 => SQLite will copy the data
const SQLITE_TRANSIENT: c.sqlite3_destructor_type = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

pub const Stmt = struct {
    db: *Db,
    stmt: *c.sqlite3_stmt,

    const Self = @This();

    pub fn init(db: *Db, sql: []const u8) !Self {
        var stmt_opt: ?*c.sqlite3_stmt = null;

        const n: c_int = @intCast(sql.len);
        const rc = c.sqlite3_prepare_v2(
            db.handle,
            sql.ptr,
            n,
            &stmt_opt,
            null,
        );
        if (rc != db_ok or stmt_opt == null)
            return error.SqlitePrepareFailed;

        return .{ .db = db, .stmt = stmt_opt.? };
    }

    pub fn finalize(self: *Self) void {
        _ = c.sqlite3_finalize(self.stmt);
    }

    pub fn deinit(self: *Self) void {
        self.finalize();
    }

    pub fn reset(self: *Self) !void {
        const rc = c.sqlite3_reset(self.stmt);
        if (rc != db_ok)
            return error.SqliteResetFailed;
    }

    pub fn clearbindings(self: *Self) !void {
        const rc = c.sqlite3_clear_bindings(self.stmt);
        if (rc != db_ok)
            return error.SqliteClearBindingsFailed;
    }

    pub fn step(self: *Stmt) !StepResult {
        const rc = c.sqlite3_step(self.stmt);
        return switch (rc) {
            c.SQLITE_ROW => .row,
            c.SQLITE_DONE => .done,
            else => error.SqliteStepFailed,
        };
    }

    // ---------- bind (1-based index) ----------
    pub fn bindNull(self: *Self, idx: c_int) !void {
        const rc = c.sqlite3_bind_null(self.stmt, idx);
        if (rc != db_ok)
            return error.SqliteBindFailed;
    }

    pub fn bindInt(self: *Self, idx: c_int, value: i64) !void {
        const rc = c.sqlite3_bind_int64(self.stmt, idx, value);
        if (rc != db_ok)
            return error.SqliteBindFailed;
    }

    pub fn bindBool(self: *Self, idx: c_int, value: bool) !void {
        const rc = c.sqlite3_bind_int(self.stmt, idx, if (value) 1 else 0);
        if (rc != db_ok)
            return error.SqliteBindFailed;
    }

    pub fn bindText(self: *Self, idx: c_int, value: []const u8) !void {
        const n: c_int = @intCast(value.len);
        const rc = c.sqlite3_bind_text(self.stmt, idx, value.ptr, n, SQLITE_TRANSIENT);
        if (rc != db_ok)
            return error.SqliteBindFailed;
    }

    pub fn bindBlob(self: *Self, idx: c_int, value: []const u8) !void {
        const n: c_int = @intCast(value.len);
        const rc = c.sqlite3_bind_blob(self.stmt, idx, value.ptr, n, SQLITE_TRANSIENT);
        if (rc != db_ok)
            return error.SqliteBindFailed;
    }

    // --------- column (0-based index, valid when setp()==.row) ----------
    pub fn colInt(self: *Self, col: c_int) i64 {
        return c.sqlite3_column_int64(self.stmt, col);
    }

    pub fn colBool(self: *Self, col: c_int) bool {
        return c.sqlite3_column_int(self.stmt, col) != 0;
    }

    /// NOTE: The returned slice points to an internal SQLite buffer; it may become invalid after the next step/reset/finalize operation.
    pub fn colText(self: *Self, col: c_int) ?[]const u8 {
        const p = c.sqlite3_column_text(self.stmt, col);
        if (p == null)
            return null;
        const n = c.sqlite3_column_bytes(self.stmt, col);
        const len: usize = @intCast(n);
        const bytes: [*]const u8 = @ptrCast(p);
        return bytes[0..len];
    }

    pub fn colBlob(self: *Self, col: c_int) ?[]const u8 {
        const p = c.sqlite3_column_blob(self.stmt, col);
        if (p == null)
            return null;
        const n = c.sqlite3_column_bytes(self.stmt, col);
        const len: usize = @intCast(n);
        const bytes: [*]const u8 = @ptrCast(p);
        return bytes[0..len];
    }
};
