const std = @import("std");
const orm = @import("zite");

const User = struct {
    id: i64,
    name: orm.types.OwnedText,
    age: ?i64,
    created_at: i64,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

fn freeUser(a: std.mem.Allocator, u: *User) void {
    u.name.deinit(a);
}

test "mapper.findOne: where + params" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try orm.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var name1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer name1.deinit(a);
    var name2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer name2.deinit(a);
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = name1, .age = null, .created_at = 1 });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = name2, .age = 42, .created_at = 2 });

    var bob = try orm.types.OwnedText.fromConst(a, "bob");
    defer bob.deinit(a);
    const P1 = @TypeOf(.{bob});
    var got = (try orm.mapper.findOne(User, P1, &db, a, "\"name\"=?1", .{bob})).?;
    defer freeUser(a, &got);

    try std.testing.expectEqualStrings("bob", got.name.value);
    try std.testing.expectEqual(@as(i64, 42), got.age.?);

    const P2 = @TypeOf(.{});
    var got2 = (try orm.mapper.findOne(User, P2, &db, a, "\"age\" IS NULL", .{})).?;
    defer freeUser(a, &got2);

    try std.testing.expectEqualStrings("alice", got2.name.value);
    try std.testing.expect(got2.age == null);

    var nobody = try orm.types.OwnedText.fromConst(a, "nobody");
    defer nobody.deinit(a);
    const P3 = @TypeOf(.{nobody});
    const none = try orm.mapper.findOne(User, P3, &db, a, "\"name\"=?1", .{nobody});
    try std.testing.expect(none == null);
}
