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

test "mapper.getById: insert -> getById -> update -> getById" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try orm.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var u = User{
        .id = 0,
        .name = "alice",
        .age = null,
        .created_at = 123,
    };

    const new_id = try orm.mapper.insert(User, &db, u);
    try std.testing.expect(new_id > 0);

    var got1 = (try orm.mapper.getById(User, &db, a, new_id)).?;
    defer freeUser(a, &got1);

    try std.testing.expectEqual(new_id, got1.id);
    try std.testing.expectEqualStrings("alice", got1.name);
    try std.testing.expect(got1.age == null);
    try std.testing.expectEqual(@as(i64, 123), got1.created_at);

    u.id = new_id;
    u.name = "alice2";
    u.age = 42;

    const changed = try orm.mapper.update(User, &db, u);
    try std.testing.expectEqual(@as(c_int, 1), changed);

    var got2 = (try orm.mapper.getById(User, &db, a, new_id)).?;
    defer freeUser(a, &got2);

    try std.testing.expectEqualStrings("alice2", got2.name);
    try std.testing.expectEqual(@as(i64, 42), got2.age.?);
}
