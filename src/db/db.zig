const std = @import("std");
const raw = @import("../raw/mod.zig");
const diag = @import("diag.zig");
const errors = @import("../core/errors.zig");
const sqlite_errors = @import("sqlite_errors.zig");

/// Database connection wrapper around sqlite3.
pub const Db = struct {
    /// Allocator used for SQL strings and owned data.
    allocator: std.mem.Allocator,
    /// Opaque sqlite3 handle.
    handle: raw.DbHandle,
    /// Tracks active statements created from this Db to warn on close.
    active_stmts: i32 = 0,

    const Self = @This();

    pub const TxMode = enum {
        deferred,
        immediate,
        exclusive,
    };

    pub const Tx = struct {
        db: *Self,
        finished: bool = false,

        const TxSelf = @This();

        pub fn commit(self: *TxSelf) errors.ZiteError!void {
            if (self.finished) return;
            try self.db.exec("COMMIT;");
            self.finished = true;
        }

        pub fn rollback(self: *TxSelf) errors.ZiteError!void {
            if (self.finished) return;
            try self.db.exec("ROLLBACK;");
            self.finished = true;
        }

        /// Rolls back unfinished transactions. Ignores rollback errors in cleanup paths.
        pub fn deinit(self: *TxSelf) void {
            if (self.finished) return;
            _ = self.db.exec("ROLLBACK;") catch {};
            self.finished = true;
        }
    };

    /// Opens a SQLite database at the provided path.
    /// Caller must `deinit()` when finished.
    pub fn open(allocator: std.mem.Allocator, path: []const u8) errors.ZiteError!Self {
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        var db_handle: ?raw.DbHandle = null;
        const rc = raw.db.open(path_z.ptr, &db_handle);
        if (rc != raw.SQLITE_OK or db_handle == null) {
            if (db_handle) |h| {
                var tmp = Db{ .allocator = allocator, .handle = h };
                diag.logSqlite(&tmp, rc, "sqlite3_open", null);
                _ = raw.db.closeImmediate(h);
            } else {
                std.log.warn("sqlite failure what=sqlite3_open rc={} msg=handle_null", .{rc});
            }
            return sqlite_errors.mapSqliteRc(rc, error.SqliteOpenFailed);
        }

        return .{ .allocator = allocator, .handle = db_handle.? };
    }

    /// Closes the database connection. Warns if statements are still active.
    /// Uses sqlite3_close_v2 so the connection will eventually close once all
    /// statements are finalized.
    pub fn close(self: *Self) void {
        if (self.active_stmts != 0) {
            std.log.warn("sqlite warning what=close_with_active_statements count={}", .{self.active_stmts});
        }
        const rc = raw.db.closeDeferred(self.handle);
        if (rc != raw.SQLITE_OK) {
            diag.logSqlite(self, rc, "sqlite3_close_v2", null);
        }
    }

    /// Alias for close() to match deinit patterns.
    pub fn deinit(self: *Self) void {
        self.close();
    }

    /// Executes a SQL statement without returning rows.
    /// The SQL string is copied into a temporary null-terminated buffer.
    pub fn exec(self: *Self, sql: []const u8) errors.ZiteError!void {
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        const rc = raw.db.exec(self.handle, sql_z.ptr);

        if (rc != raw.SQLITE_OK) {
            diag.logSqlite(self, rc, "sqlite3_exec", sql);
            return sqlite_errors.mapSqliteRc(rc, error.SqliteExecFailed);
        }
    }

    pub fn beginTx(self: *Self, mode: TxMode) errors.ZiteError!Tx {
        switch (mode) {
            .deferred => try self.exec("BEGIN;"),
            .immediate => try self.exec("BEGIN IMMEDIATE;"),
            .exclusive => try self.exec("BEGIN EXCLUSIVE;"),
        }
        return .{ .db = self };
    }

    /// Returns the last SQLite error message for this connection.
    /// The returned slice is only valid until the next sqlite call.
    pub fn errmsg(self: *Db) []const u8 {
        const p = raw.db.errmsg(self.handle);
        if (p == null) return "";
        return std.mem.span(p.?);
    }

    /// Returns the rowid of the most recent successful INSERT.
    pub fn lastInsertRowId(self: *Self) i64 {
        return raw.db.lastInsertRowId(self.handle);
    }

    /// Returns the number of rows changed by the last operation.
    pub fn changes(self: *Self) i32 {
        return raw.db.changes(self.handle);
    }

    /// Records that a new statement has been prepared.
    pub fn registerStmt(self: *Self) void {
        self.active_stmts += 1;
    }

    /// Records that a statement has been finalized.
    pub fn unregisterStmt(self: *Self) void {
        if (self.active_stmts > 0) {
            self.active_stmts -= 1;
        }
    }
};

test "db: exec, changes, lastInsertRowId" {
    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec(
        \\CREATE TABLE users(
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL
        \\);
    );
    try db.exec("INSERT INTO users(name) VALUES ('alice');");
    try std.testing.expectEqual(@as(i64, 1), db.lastInsertRowId());
    try std.testing.expectEqual(@as(i32, 1), db.changes());
}

test "db: exec invalid SQL returns error and errmsg" {
    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    try std.testing.expectError(error.SqliteExecFailed, db.exec("THIS IS NOT SQL;"));
    const msg = db.errmsg();
    try std.testing.expect(msg.len != 0);
}

test "db: register/unregister clamp underflow" {
    var db = try Db.open(std.testing.allocator, ":memory:");
    defer db.deinit();

    db.registerStmt();
    db.unregisterStmt();
    db.unregisterStmt();
    try std.testing.expectEqual(@as(i32, 0), db.active_stmts);
}

test "db: transaction commit persists changes" {
    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec(
        \\CREATE TABLE t(
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL
        \\);
    );

    var tx = try db.beginTx(.deferred);
    defer tx.deinit();
    try db.exec("INSERT INTO t(name) VALUES('alice');");
    try tx.commit();

    var st = try @import("stmt.zig").Stmt.init(&db, "SELECT COUNT(*) FROM t;");
    defer st.deinit();
    try std.testing.expectEqual(@import("stmt.zig").StepResult.row, try st.step());
    try std.testing.expectEqual(@as(i64, 1), st.colInt(0));
}

test "db: transaction deinit rolls back unfinished work" {
    const a = std.testing.allocator;
    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec(
        \\CREATE TABLE t(
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL
        \\);
    );

    {
        var tx = try db.beginTx(.deferred);
        defer tx.deinit();
        try db.exec("INSERT INTO t(name) VALUES('alice');");
        // no commit -> rollback via deinit
    }

    var st = try @import("stmt.zig").Stmt.init(&db, "SELECT COUNT(*) FROM t;");
    defer st.deinit();
    try std.testing.expectEqual(@import("stmt.zig").StepResult.row, try st.step());
    try std.testing.expectEqual(@as(i64, 0), st.colInt(0));
}
