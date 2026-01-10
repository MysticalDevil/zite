const std = @import("std");
const orm = @import("zig_orm_sqlite");

const User = struct {
    id: i64,
    name: []const u8,
    age: ?i64,
    created_at: i64,

    pub const Meta = .{
        .table = "users",
    };
};

test "mapper.insert + mapper.update: roundtrip" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try orm.schema.createTableSql(a, User, .{ .table_name = "users" });
    defer a.free(ddl);
    try db.exec(ddl);

    var u = User{
        .id = 0,
        .name = "aice",
        .age = null,
        .created_at = 123,
    };

    const new_id = try orm.mapper.insert(User, &db, u);
    try std.testing.expect(new_id > 0);

    u.id = new_id;
    u.name = "alice2";
    u.age = 42;

    const changed = try orm.mapper.update(User, &db, u);
    try std.testing.expectEqual(@as(c_int, 1), changed);

    var st = try orm.Stmt.init(&db, "SELECT name, age FROM users WHERE id=?1 LIMIT 1;");
    defer st.deinit();

    try st.bindAll(.{new_id});

    const r1 = try st.step();
    try std.testing.expectEqual(orm.StepResult.row, r1);

    const name = st.colText(0).?;
    try std.testing.expectEqualStrings("alice2", name);
    try std.testing.expectEqual(@as(i64, 42), st.colInt(1));

    const r2 = try st.step();
    try std.testing.expectEqual(orm.StepResult.done, r2);
}
