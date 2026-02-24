const std = @import("std");
const orm = @import("zite");

const User = struct {
    id: i64,
    name: []const u8,
    age: ?i64,
    created_at: i64,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

fn freeUser(a: std.mem.Allocator, u: *User) void {
    a.free(@constCast(u.name));
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

    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = "alice", .age = null, .created_at = 1 });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = "bob", .age = 42, .created_at = 2 });

    const P1 = @TypeOf(.{"bob"});
    var got = (try orm.mapper.findOne(User, P1, &db, a, "\"name\"=?1", .{"bob"})).?;
    defer freeUser(a, &got);

    try std.testing.expectEqualStrings("bob", got.name);
    try std.testing.expectEqual(@as(i64, 42), got.age.?);

    const P2 = @TypeOf(.{});
    var got2 = (try orm.mapper.findOne(User, P2, &db, a, "\"age\" IS NULL", .{})).?;
    defer freeUser(a, &got2);

    try std.testing.expectEqualStrings("alice", got2.name);
    try std.testing.expect(got2.age == null);

    const P3 = @TypeOf(.{"nobody"});
    const none = try orm.mapper.findOne(User, P3, &db, a, "\"name\"=?1", .{"nobody"});
    try std.testing.expect(none == null);
}
