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
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

fn freeUser(a: std.mem.Allocator, u: *User) void {
    u.name.deinit(a);
}

test "mapper.findById: insert -> findById -> update -> findById" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.orm.repository(User, &db, a);

    var name1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer name1.deinit(a);
    var u = User{
        .id = 0,
        .name = name1,
        .age = null,
        .created_at = 123,
    };

    const new_id = try repo.insert(u);
    try std.testing.expect(new_id > 0);

    var got1 = (try repo.findById(new_id)).?;
    defer freeUser(a, &got1);

    try std.testing.expectEqual(new_id, got1.id);
    try std.testing.expectEqualStrings("alice", got1.name.value);
    try std.testing.expect(got1.age == null);
    try std.testing.expectEqual(@as(i64, 123), got1.created_at);

    u.id = new_id;
    var name2 = try orm.types.OwnedText.fromConst(a, "alice2");
    defer name2.deinit(a);
    u.name = name2;
    u.age = 42;

    const changed = try repo.update(u);
    try std.testing.expectEqual(@as(i32, 1), changed);

    var got2 = (try repo.findById(new_id)).?;
    defer freeUser(a, &got2);

    try std.testing.expectEqualStrings("alice2", got2.name.value);
    try std.testing.expectEqual(@as(i64, 42), got2.age.?);
}
