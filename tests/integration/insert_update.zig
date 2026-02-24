const std = @import("std");
const orm = @import("zite");
const helpers = @import("helpers.zig");

const User = struct {
    id: i64,
    name: orm.types.OwnedText,
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

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTable(a, &db, User, "users");

    var name1 = try orm.types.OwnedText.fromConst(a, "aice");
    defer name1.deinit(a);
    var u = User{
        .id = 0,
        .name = name1,
        .age = null,
        .created_at = 123,
    };

    const new_id = try orm.mapper.insert(User, &db, u);
    try std.testing.expect(new_id > 0);

    u.id = new_id;
    var name2 = try orm.types.OwnedText.fromConst(a, "alice2");
    defer name2.deinit(a);
    u.name = name2;
    u.age = 42;

    const changed = try orm.mapper.update(User, &db, u);
    try std.testing.expectEqual(@as(i32, 1), changed);

    var st = try orm.Stmt.init(&db, "SELECT name, age FROM users WHERE id=?1 LIMIT 1;");
    defer st.deinit();

    try st.bindAll(.{new_id});

    const r1 = try st.step();
    try std.testing.expectEqual(orm.StepResult.row, r1);

    const name = (try st.colTextOwned(a, 0)).?;
    defer a.free(name);
    try std.testing.expectEqualStrings("alice2", name);
    try std.testing.expectEqual(@as(i64, 42), st.colInt(1));

    const r2 = try st.step();
    try std.testing.expectEqual(orm.StepResult.done, r2);
}
