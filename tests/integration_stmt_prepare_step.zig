const std = @import("std");
const orm = @import("zig_orm_sqlite");

test "Stmt: prepare + step reads scalar result" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    var st = try orm.Stmt.init(&db, "SELECT 1;");
    defer st.deinit();

    const r1 = try st.step();
    try std.testing.expectEqual(orm.StepResult.row, r1);
    try std.testing.expectEqual(@as(i64, 1), st.colInt(0));

    const r2 = try st.step();
    try std.testing.expectEqual(orm.StepResult.done, r2);
}
