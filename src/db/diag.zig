const std = @import("std");
const builtin = @import("builtin");
const Db = @import("db.zig").Db;

fn sqlSnippet(sql: []const u8) []const u8 {
    const max: usize = 200;
    if (sql.len <= max) {
        return sql;
    }
    return sql[0..max];
}

fn enabledInThisBuild() bool {
    return !builtin.is_test;
}

/// Logs a driver failure with optional SQL snippet (if enabled).
/// Safe to call with partially-initialized handles (e.g. after a failed open),
/// because `Driver.db.errmsg` is required to work on any non-null handle.
pub fn logSqlite(comptime Driver: type, db: *Db(Driver), rc: i32, comptime what: []const u8, sql: ?[]const u8) void {
    if (!enabledInThisBuild()) {
        return;
    }

    std.log.warn("driver failure what={s} rc={} msg={s}", .{ what, rc, db.errmsg() });
    if (sql) |s| {
        std.log.warn("driver sql={s}", .{sqlSnippet(s)});
    }
}

/// Logs bind failures when diagnostics are enabled.
pub fn logBind(comptime kind: []const u8, idx: i32) void {
    if (!enabledInThisBuild()) {
        return;
    }
    std.log.warn("driver bind idx={} kind={s}", .{ idx, kind });
}
