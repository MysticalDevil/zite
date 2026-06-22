const std = @import("std");
const zite = @import("zite");
const helpers = @import("helpers.zig");

const User = struct {
    id: i64,
    name: zite.types.OwnedText,
    age: ?u32,
    created_at: i64,
};

test "create table from struct and verify sqlite_master" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTable(a, &db, User, "users");

    const query = "SELECT name FROM sqlite_master WHERE type='table' AND name='users' LIMIT 1;";
    const qz = try a.dupeSentinel(u8, query, 0);
    defer a.free(qz);

    var stmt_opt: ?zite.raw.StmtHandle = null;
    const rc_prep = zite.raw.stmt.prepare(db.handle, qz.ptr, -1, &stmt_opt);
    try std.testing.expectEqual(zite.raw.SQLITE_OK, rc_prep);
    const stmt = stmt_opt.?;
    defer _ = zite.raw.stmt.finalize(stmt);

    const rc_step = zite.raw.stmt.step(stmt);
    try std.testing.expectEqual(zite.raw.SQLITE_ROW, rc_step);

    const name_ptr = zite.raw.stmt.columnText(stmt, 0);
    try std.testing.expect(name_ptr != null);
}
