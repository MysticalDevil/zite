const std = @import("std");
const orm = @import("zig_orm_sqlite");

const User = struct {
    id: i64,
    name: []const u8,
    age: ?u32,
    created_at: i64,
};

test "prepare_v2 + step: verify users table exists via sqlite_master" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    // Step 1: memory db
    var db = try orm.Db.open(a, ":memory:");
    defer db.close();

    // Step 2: Create table (Use schema generator + exec to preform a DDL operation)
    const ddl = try orm.schema.createTableSql(a, User, .{ .table_name = "users" });
    defer a.free(ddl);
    try db.exec(ddl);

    // Step 3: Compile the query statement using prepare_v2 (to avoid the sqlite3_exec callback)
    const q = "SELECT 1 FROM sqlite_master WHERE type='table' AND name='users' LIMIT 1;";
    const qz = try a.dupeZ(u8, q);
    defer a.free(qz);

    var stmt_opt: ?*orm.c.sqlite3_stmt = null;
    const rc_prep = orm.c.sqlite3_prepare_v2(db.handle, qz.ptr, -1, &stmt_opt, null);
    try std.testing.expectEqual(orm.c.SQLITE_OK, rc_prep);
    const stmt = stmt_opt.?;

    defer _ = orm.c.sqlite3_finalize(stmt);

    // Step 4: step: Result row found -> SQLITE_ROW
    const rc_step1 = orm.c.sqlite3_step(stmt);
    try std.testing.expectEqual(orm.c.SQLITE_ROW, rc_step1);

    // Step 5: Read column 0 (SELECT 1), should be 1
    const v = orm.c.sqlite3_column_int(stmt, 0);
    try std.testing.expectEqual(@as(c_int, 1), v);

    // Step 6: Step once more -> SQLITE_DONE
    const rc_step2 = orm.c.sqlite3_step(stmt);
    try std.testing.expectEqual(orm.c.SQLITE_DONE, rc_step2);
}
