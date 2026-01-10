const std = @import("std");
const orm = @import("zig_orm_sqlite");

test "Stmt.bindAll: binds int/text/null and reads them back" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    var st = try orm.Stmt.init(&db, "SELECT ?1 AS a, ?2 as b, ?3 as c;");
    defer st.deinit();

    try st.bindAll(.{
        @as(i64, 42),
        @as([]const u8, "zig"),
        @as(?i64, null),
    });

    const r1 = try st.step();
    try std.testing.expectEqual(orm.StepResult.row, r1);

    try std.testing.expectEqual(@as(i64, 42), st.colInt(0));

    const b = st.colText(1).?;
    try std.testing.expectEqualStrings("zig", b);

    try std.testing.expect(st.colText(2) == null);

    const r2 = try st.step();
    try std.testing.expectEqual(orm.StepResult.done, r2);
}
