const std = @import("std");
const zite = @import("zite");

test "Stmt: colIsNull + colTextOwned" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try zite.Db(zite.drivers.sqlite3).open(a, ":memory:");
    defer db.deinit();

    var st = try zite.Stmt(zite.drivers.sqlite3).init(&db, "SELECT NULL, 'zig', '';");
    defer st.deinit();

    const r = try st.step();
    try std.testing.expectEqual(zite.StepResult.row, r);

    try std.testing.expect(try st.colIsNull(0));
    try std.testing.expect(!(try st.colIsNull(1)));
    try std.testing.expect(!(try st.colIsNull(2)));

    const t0 = try st.colTextOwned(a, 0);
    try std.testing.expect(t0 == null);

    const t1 = (try st.colTextOwned(a, 1)).?;
    defer a.free(t1);
    try std.testing.expectEqualStrings("zig", t1);

    const t2 = (try st.colTextOwned(a, 2)).?;
    defer a.free(t2);
    try std.testing.expectEqual(@as(usize, 0), t2.len);

    const r2 = try st.step();
    try std.testing.expectEqual(zite.StepResult.done, r2);
}
