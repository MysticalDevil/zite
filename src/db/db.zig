const std = @import("std");
const raw = @import("../raw/sqlite3.zig");
const diag = @import("diag.zig");
const errors = @import("../core/errors.zig");
const sqlite_errors = @import("sqlite_errors.zig");

pub const Db = struct {
    allocator: std.mem.Allocator,
    handle: *raw.sqlite3,

    const Self = @This();

    pub fn open(allocator: std.mem.Allocator, path: []const u8) errors.ZiteError!Self {
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        var db_ptr: ?*raw.sqlite3 = null;
        const rc = raw.sqlite3_open(path_z.ptr, &db_ptr);
        if (rc != raw.SQLITE_OK or db_ptr == null) {
            if (db_ptr) |h| {
                var tmp = Db{ .allocator = allocator, .handle = h };
                diag.logSqlite(&tmp, rc, "sqlite3_open", null);
                _ = raw.sqlite3_close(h);
            } else {
                std.log.warn("sqlite failure what=sqlite3_open rc={} msg=handle_null", .{rc});
            }
            return sqlite_errors.mapSqliteRc(rc, error.SqliteOpenFailed);
        }

        return .{ .allocator = allocator, .handle = db_ptr.? };
    }

    pub fn close(self: *Self) void {
        const rc = raw.sqlite3_close_v2(self.handle);
        if (rc != raw.SQLITE_OK) {
            diag.logSqlite(self, rc, "sqlite3_close_v2", null);
        }
    }

    pub fn deinit(self: *Self) void {
        self.close();
    }

    pub fn exec(self: *Self, sql: []const u8) errors.ZiteError!void {
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        const rc = raw.sqlite3_exec(self.handle, sql_z.ptr, null, null, null);

        if (rc != raw.SQLITE_OK) {
            diag.logSqlite(self, rc, "sqlite3_exec", sql);
            return sqlite_errors.mapSqliteRc(rc, error.SqliteExecFailed);
        }
    }

    pub fn errmsg(self: *Db) []const u8 {
        const p = raw.sqlite3_errmsg(self.handle);
        if (p == null) return "";
        return std.mem.span(p);
    }

    pub fn lastInsertRowId(self: *Self) i64 {
        return raw.sqlite3_last_insert_rowid(self.handle);
    }

    pub fn changes(self: *Self) c_int {
        return raw.sqlite3_changes(self.handle);
    }
};
