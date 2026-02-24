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
    pub fn exec(self: *Self, sql: []const u8) errors.ZiteError!void {
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        const rc = raw.db.exec(self.handle, sql_z.ptr);

        if (rc != raw.SQLITE_OK) {
            diag.logSqlite(self, rc, "sqlite3_exec", sql);
            return sqlite_errors.mapSqliteRc(rc, error.SqliteExecFailed);
        }
    }

    /// Returns the last SQLite error message for this connection.
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
        self.active_stmts -= 1;
        if (self.active_stmts < 0) {
            std.log.warn("sqlite warning what=stmt_count_underflow", .{});
            self.active_stmts = 0;
        }
    }
};
