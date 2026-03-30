const std = @import("std");
const zite = @import("zite");
const orm = zite.orm(zite.drivers.sqlite3);
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

test "mapper.findOne: where + params" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var name1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer name1.deinit(a);
    var name2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer name2.deinit(a);
    _ = try repo.insert(.{ .id = 0, .name = name1, .age = null, .created_at = 1 });
    _ = try repo.insert(.{ .id = 0, .name = name2, .age = 42, .created_at = 2 });

    var bob = try orm.types.OwnedText.fromConst(a, "bob");
    defer bob.deinit(a);
    var got = (try repo.findOneSql("\"name\"=?1", .{bob})).?;
    defer freeUser(a, &got);

    try std.testing.expectEqualStrings("bob", got.name.value);
    try std.testing.expectEqual(@as(i64, 42), got.age.?);

    var got2 = (try repo.findOneSql("\"age\" IS NULL", .{})).?;
    defer freeUser(a, &got2);

    try std.testing.expectEqualStrings("alice", got2.name.value);
    try std.testing.expect(got2.age == null);

    var nobody = try orm.types.OwnedText.fromConst(a, "nobody");
    defer nobody.deinit(a);
    const none = try repo.findOneSql("\"name\"=?1", .{nobody});
    try std.testing.expect(none == null);
}

test "mapper.findOne: returns UnexpectedExtraRows for multi-match query" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var name1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer name1.deinit(a);
    var name2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer name2.deinit(a);
    _ = try repo.insert(.{ .id = 0, .name = name1, .age = null, .created_at = 1 });
    _ = try repo.insert(.{ .id = 0, .name = name2, .age = null, .created_at = 2 });

    try std.testing.expectError(
        error.UnsafeSqlFragment,
        repo.findOneSql("1=1 --", .{}),
    );

    try std.testing.expectError(
        error.UnexpectedExtraRows,
        repo.findOneSqlUnsafe("1=1 --", .{}),
    );
}
