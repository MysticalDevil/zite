const std = @import("std");
const raw = @import("../raw/sqlite3.zig");
const diag = @import("diag.zig");

pub const Db = struct {
    allocator: std.mem.Allocator,
    handle: ?*raw.sqlite3,

    const Self = @This();

    pub fn open(allocator: std.mem.Allocator, path: []const u8) !Self {
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
            return error.SqliteOpenFailed;
        }

        return .{ .allocator = allocator, .handle = db_ptr.? };
    }

    pub fn close(self: *Self) void {
        const h = self.handle orelse return;
        const rc = raw.sqlite3_close(h);
        if (rc == raw.SQLITE_OK) {
            self.handle = null;
            return;
        }
        std.log.warn("sqlite close failure rc={} msg={s}", .{ rc, self.errmsg() });
    }

    pub fn deinit(self: *Self) void {
        self.close();
    }

    pub fn exec(self: *Self, sql: []const u8) !void {
        const h = self.handle orelse return error.DbClosed;
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        const rc = raw.sqlite3_exec(h, sql_z.ptr, null, null, null);

        if (rc != raw.SQLITE_OK) {
            diag.logSqlite(self, rc, "sqlite3_exec", sql);
            return error.SqliteExecFailed;
        }
    }

    pub fn errmsg(self: *Db) []const u8 {
        const h = self.handle orelse return "db_closed";
        const p = raw.sqlite3_errmsg(h);
        if (p == null) return "";
        return std.mem.span(p);
    }

    pub fn lastInsertRowId(self: *Self) i64 {
        const h = self.handle orelse return 0;
        return raw.sqlite3_last_insert_rowid(h);
    }

    pub fn changes(self: *Self) c_int {
        const h = self.handle orelse return 0;
        return raw.sqlite3_changes(h);
    }
};
