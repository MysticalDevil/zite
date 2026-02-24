const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Db = @import("db.zig").Db;

fn sqlSnippet(sql: []const u8) []const u8 {
    const max: usize = 200;
    if (sql.len <= max) return sql;
    return sql[0..max];
}

fn enabledInThisBuild() bool {
    if (!builtin.is_test) return true;
    return build_options.diag_enable_in_tests;
}

pub fn logSqlite(db: *Db, rc: c_int, comptime what: []const u8, sql: ?[]const u8) void {
    if (!enabledInThisBuild()) return;

    std.log.warn("sqlite failure what={s} rc={} msg={s}", .{ what, rc, db.errmsg() });
    if (sql) |s| std.log.warn("sqlite sql={s}", .{sqlSnippet(s)});
}

pub fn logBind(comptime kind: []const u8, idx: c_int) void {
    if (!enabledInThisBuild()) return;
    std.log.warn("sqlite bind idx={} kind={s}", .{ idx, kind });
}
