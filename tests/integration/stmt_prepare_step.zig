const std = @import("std");
const zite = @import("zite");
const orm = zite.orm(zite.drivers.sqlite3);

test "Stmt: prepare + step reads scalar result" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    var st = try orm.Stmt.init(&db, "SELECT 1;");
    defer st.deinit();

    const r1 = try st.step();
    try std.testing.expectEqual(orm.StepResult.row, r1);
    try std.testing.expectEqual(@as(i64, 1), try st.colInt(0));

    const r2 = try st.step();
    try std.testing.expectEqual(orm.StepResult.done, r2);
}
