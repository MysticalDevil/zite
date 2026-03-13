const std = @import("std");
const orm = @import("zite");
const helpers = @import("helpers.zig");

const User = struct {
    id: i64,
    name: orm.types.OwnedText,
    age: ?i64,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

test "orm.query: whereEq/orderBy/limit/offset/whereRaw" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.orm.repository(User, &db, a);

    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    var n2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer n2.deinit(a);
    var n3 = try orm.types.OwnedText.fromConst(a, "carol");
    defer n3.deinit(a);

    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 20) });
    _ = try repo.insert(.{ .id = 0, .name = n2, .age = @as(?i64, 30) });
    _ = try repo.insert(.{ .id = 0, .name = n3, .age = @as(?i64, 40) });

    var q1 = repo.query();
    defer q1.deinit();
    try q1.whereEq("id", @as(i64, 2));
    const one = (try q1.firstOwned()).?;
    var one_mut = one;
    defer one_mut.deinit();
    try std.testing.expectEqualStrings("bob", one_mut.value.name.value);

    var q2 = repo.query();
    defer q2.deinit();
    try q2.whereRaw("\"age\">?1", .{@as(i64, 20)});
    try q2.orderBy("id", .asc);
    q2.setLimit(1);
    q2.setOffset(1);
    const many = try q2.allOwned();
    defer a.free(many);
    defer for (many) |*row| row.deinit();

    try std.testing.expectEqual(@as(usize, 1), many.len);
    try std.testing.expectEqualStrings("carol", many[0].value.name.value);
}
