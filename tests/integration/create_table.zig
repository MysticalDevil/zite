const std = @import("std");
const orm = @import("zite");

const User = struct {
    id: i64,
    name: orm.types.OwnedText,
    age: ?u32,
    created_at: i64,
};

test "create table from struct and verify sqlite_master" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.close();

    const sql = try orm.schema.createTableSql(a, User, .{ .table_name = "users" });
    defer a.free(sql);
    try db.exec(sql);

    const query = "SELECT name FROM sqlite_master WHERE type='table' AND name='users' LIMIT 1;";
    const qz = try a.dupeZ(u8, query);
    defer a.free(qz);

    var stmt_opt: ?orm.raw.StmtHandle = null;
    const rc_prep = orm.raw.stmt.prepare(db.handle, qz.ptr, -1, &stmt_opt);
    try std.testing.expectEqual(orm.raw.SQLITE_OK, rc_prep);
    const stmt = stmt_opt.?;
    defer _ = orm.raw.stmt.finalize(stmt);

    const rc_step = orm.raw.stmt.step(stmt);
    try std.testing.expectEqual(orm.raw.SQLITE_ROW, rc_step);

    const name_ptr = orm.raw.stmt.columnText(stmt, 0);
    try std.testing.expect(name_ptr != null);
}
