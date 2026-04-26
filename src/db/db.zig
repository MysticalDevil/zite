const std = @import("std");
const diag = @import("diag.zig");
const errors = @import("../core/errors.zig");
const driver_root = @import("../driver/root.zig");
const driver_errors = @import("driver_errors.zig");

/// Database connection wrapper around a selected driver.
pub fn Db(comptime Driver: type) type {
    comptime driver_root.assertDriver(Driver);

    return struct {
        /// Allocator used for SQL strings and owned data.
        allocator: std.mem.Allocator,
        /// Opaque driver handle.
        handle: Driver.DbHandle,
        /// Tracks active statements created from this Db to warn on close.
        /// Updated with atomic operations for thread-safety.
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

            pub fn commit(self: *TxSelf) errors.DbError!void {
                if (self.finished) {
                    return;
                }
                try self.db.exec("COMMIT;");
                self.finished = true;
            }

            pub fn rollback(self: *TxSelf) errors.DbError!void {
                if (self.finished) {
                    return;
                }
                try self.db.exec("ROLLBACK;");
                self.finished = true;
            }

            /// Rolls back unfinished transactions. Ignores rollback errors in cleanup paths.
            pub fn deinit(self: *TxSelf) void {
                if (self.finished) {
                    return;
                }
                self.db.exec("ROLLBACK;") catch |err| {
                    std.log.warn("driver warning what=tx_rollback_failed err={}", .{err});
                };
                self.finished = true;
            }
        };

        /// Opens a database at the provided path.
        /// Caller must `deinit()` when finished.
        pub fn open(allocator: std.mem.Allocator, path: []const u8) errors.DbError!Self {
            const path_z = try allocator.dupeZ(u8, path);
            defer allocator.free(path_z);

            var db_handle: ?Driver.DbHandle = null;
            const rc = Driver.db.open(path_z.ptr, &db_handle);
            if (rc != Driver.OK or db_handle == null) {
                if (db_handle) |h| {
                    var tmp = Self{ .allocator = allocator, .handle = h };
                    diag.logSqlite(Driver, &tmp, rc, "driver_open", null);
                    const close_rc = Driver.db.closeImmediate(h);
                    if (close_rc != Driver.OK) {
                        diag.logSqlite(Driver, &tmp, close_rc, "driver_closeImmediate", null);
                    }
                } else {
                    std.log.warn("driver failure what=driver_open rc={} msg=handle_null", .{rc});
                }
                return driver_errors.mapDriverRc(Driver, rc, error.DriverOpenFailed);
            }

            return .{ .allocator = allocator, .handle = db_handle.? };
        }

        /// Closes the database connection. Warns if statements are still active.
        pub fn close(self: *Self) void {
            if (self.active_stmts != 0) {
                std.log.warn("driver warning what=close_with_active_statements count={}", .{self.active_stmts});
            }
            const rc = Driver.db.closeDeferred(self.handle);
            if (rc != Driver.OK) {
                diag.logSqlite(Driver, self, rc, "driver_close_deferred", null);
            }
        }

        /// Alias for close() to match deinit patterns.
        pub fn deinit(self: *Self) void {
            self.close();
        }

        /// Executes a SQL statement without returning rows.
        /// The SQL string is copied into a temporary null-terminated buffer.
        pub fn exec(self: *Self, sql: []const u8) errors.DbError!void {
            const sql_z = try self.allocator.dupeZ(u8, sql);
            defer self.allocator.free(sql_z);

            const rc = Driver.db.exec(self.handle, sql_z.ptr);

            if (rc != Driver.OK) {
                diag.logSqlite(Driver, self, rc, "driver_exec", sql);
                return driver_errors.mapDriverRc(Driver, rc, error.DriverExecFailed);
            }
        }

        pub fn beginTx(self: *Self, mode: TxMode) errors.DbError!Tx {
            switch (mode) {
                .deferred => try self.exec("BEGIN;"),
                .immediate => try self.exec("BEGIN IMMEDIATE;"),
                .exclusive => try self.exec("BEGIN EXCLUSIVE;"),
            }
            return .{ .db = self };
        }

        /// Returns the last error message for this connection.
        /// The returned slice is only valid until the next driver call.
        pub fn errmsg(self: *Self) []const u8 {
            const p = Driver.db.errmsg(self.handle);
            if (p == null) {
                return "";
            }
            return std.mem.span(p.?);
        }

        /// Returns the rowid of the most recent successful INSERT.
        pub fn lastInsertRowId(self: *Self) i64 {
            return Driver.db.lastInsertRowId(self.handle);
        }

        /// Returns the number of rows changed by the last operation.
        pub fn changes(self: *Self) i32 {
            return Driver.db.changes(self.handle);
        }

        /// Records that a new statement has been prepared.
        pub fn registerStmt(self: *Self) void {
            while (true) {
                const current = @atomicLoad(i32, &self.active_stmts, .monotonic);
                if (@cmpxchgWeak(i32, &self.active_stmts, current, current + 1, .monotonic, .monotonic) == null) {
                    break;
                }
            }
        }

        /// Records that a statement has been finalized.
        /// Returns an error if the counter would underflow.
        pub fn unregisterStmt(self: *Self) errors.DbError!void {
            while (true) {
                const current = @atomicLoad(i32, &self.active_stmts, .monotonic);
                if (current <= 0) {
                    return error.StatementCountUnderflow;
                }
                const next = current - 1;
                if (@cmpxchgWeak(i32, &self.active_stmts, current, next, .monotonic, .monotonic) == null) {
                    return;
                }
            }
        }
    };
}

test "db: exec, changes, lastInsertRowId" {
    const Driver = @import("../driver/sqlite3.zig");
    const DbT = Db(Driver);
    const a = std.testing.allocator;
    var db = try DbT.open(a, ":memory:");
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
    const Driver = @import("../driver/sqlite3.zig");
    const DbT = Db(Driver);
    const a = std.testing.allocator;
    var db = try DbT.open(a, ":memory:");
    defer db.deinit();

    try std.testing.expectError(error.DriverExecFailed, db.exec("THIS IS NOT SQL;"));
    const msg = db.errmsg();
    try std.testing.expect(msg.len != 0);
}

test "db: register/unregister underflow returns error" {
    const Driver = @import("../driver/sqlite3.zig");
    const DbT = Db(Driver);
    var db = try DbT.open(std.testing.allocator, ":memory:");
    defer db.deinit();

    db.registerStmt();
    try db.unregisterStmt();
    try std.testing.expectError(error.StatementCountUnderflow, db.unregisterStmt());
    try std.testing.expectEqual(@as(i32, 0), db.active_stmts);
}

test "db: transaction commit persists changes" {
    const Driver = @import("../driver/sqlite3.zig");
    const DbT = Db(Driver);
    const StmtT = @import("stmt.zig").Stmt(Driver);
    const a = std.testing.allocator;
    var db = try DbT.open(a, ":memory:");
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

    var st = try StmtT.init(&db, "SELECT COUNT(*) FROM t;");
    defer st.deinit();
    try std.testing.expectEqual(@import("stmt.zig").StepResult.row, try st.step());
    try std.testing.expectEqual(@as(i64, 1), try st.colInt(0));
}

test "db: transaction deinit rolls back unfinished work" {
    const Driver = @import("../driver/sqlite3.zig");
    const DbT = Db(Driver);
    const StmtT = @import("stmt.zig").Stmt(Driver);
    const a = std.testing.allocator;
    var db = try DbT.open(a, ":memory:");
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
    }

    var st = try StmtT.init(&db, "SELECT COUNT(*) FROM t;");
    defer st.deinit();
    try std.testing.expectEqual(@import("stmt.zig").StepResult.row, try st.step());
    try std.testing.expectEqual(@as(i64, 0), try st.colInt(0));
}
