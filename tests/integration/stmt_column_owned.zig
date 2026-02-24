const std = @import("std");
const orm = @import("zite");

test "Stmt: colIsNull + colTextOwned" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    var st = try orm.Stmt.init(&db, "SELECT NULL, 'zig', '';");
    defer st.deinit();

    const r = try st.step();
    try std.testing.expectEqual(orm.StepResult.row, r);

    try std.testing.expect(st.colIsNull(0));
    try std.testing.expect(!st.colIsNull(1));
    try std.testing.expect(!st.colIsNull(2));

    const t0 = try st.colTextOwned(a, 0);
    try std.testing.expect(t0 == null);

    const t1 = (try st.colTextOwned(a, 1)).?;
    defer a.free(t1);
    try std.testing.expectEqualStrings("zig", t1);

    const t2 = (try st.colTextOwned(a, 2)).?;
    defer a.free(t2);
    try std.testing.expectEqual(@as(usize, 0), t2.len);

    const r2 = try st.step();
    try std.testing.expectEqual(orm.StepResult.done, r2);
}
