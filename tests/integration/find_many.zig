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

test "mapper.findMany: ioterate rows and free owned fields" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTableFromMeta(a, &db, User);

    var name1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer name1.deinit(a);
    var name2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer name2.deinit(a);
    var name3 = try orm.types.OwnedText.fromConst(a, "carol");
    defer name3.deinit(a);
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = name1, .age = null, .created_at = 1 });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = name2, .age = 20, .created_at = 2 });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = name3, .age = 30, .created_at = 3 });

    const P = @TypeOf(.{@as(i64, 18)});
    var rows = try orm.mapper.findMany(User, P, &db, a, "\"age\">?1 ORDER BY \"id\" ASC", .{@as(i64, 18)});
    defer rows.deinit();

    var count: usize = 0;

    while (try rows.next()) |u| {
        var tmp = u;
        defer orm.mapper.freeOwnedRow(User, a, &tmp);

        if (count == 0) {
            try std.testing.expectEqualStrings("bob", tmp.name.value);
            try std.testing.expectEqual(@as(i64, 20), tmp.age.?);
        } else if (count == 1) {
            try std.testing.expectEqualStrings("carol", tmp.name.value);
            try std.testing.expectEqual(@as(i64, 30), tmp.age.?);
        }
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 2), count);
}
