const std = @import("std");

pub const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const Db = struct {
    allocator: std.mem.Allocator,
    handle: *c.sqlite3,

    const Self = @This();

    pub fn open(allocator: std.mem.Allocator, path: []const u8) !Self {
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        var db_ptr: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path_z.ptr, &db_ptr);
        if (rc != c.SQLITE_OK or db_ptr == null) {
            return error.SqliteOpenFailed;
        }

        return .{ .allocator = allocator, .handle = db_ptr.? };
    }

    pub fn close(self: *Self) void {
        _ = c.sqlite3_close(self.handle);
    }

    pub fn exec(self: *Self, sql: []const u8) !void {
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        var errmsg: [*c]u8 = null;
        const rc = c.sqlite3_exec(self.handle, sql_z.ptr, null, null, &errmsg);
        defer if (errmsg != null) c.sqlite3_free(errmsg);

        if (rc != c.SQLITE_OK) {
            return error.SqliteExecFailed;
        }
    }
};
