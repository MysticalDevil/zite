const std = @import("std");
const zite = @import("zite");

test "Stmt: prepare + step reads scalar result" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try zite.Db(zite.drivers.sqlite3).open(a, ":memory:");
    defer db.deinit();

    var st = try zite.Stmt(zite.drivers.sqlite3).init(&db, "SELECT 1;");
    defer st.deinit();

    const r1 = try st.step();
    try std.testing.expectEqual(zite.StepResult.row, r1);
    try std.testing.expectEqual(@as(i64, 1), try st.colInt(0));

    const r2 = try st.step();
    try std.testing.expectEqual(zite.StepResult.done, r2);
}
