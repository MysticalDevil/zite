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

test "mapper.findMany: ioterate rows and free owned fields" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try orm.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = "alice", .age = null, .created_at = 1 });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = "bob", .age = 20, .created_at = 2 });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = "carol", .age = 30, .created_at = 3 });

    const P = @TypeOf(.{@as(i64, 18)});
    var rows = try orm.mapper.findMany(User, P, &db, a, "\"age\">?1 ORDER BY \"id\" ASC", .{@as(i64, 18)});
    defer rows.deinit();

    var count: usize = 0;

    while (try rows.next()) |u| {
        var tmp = u;
        defer orm.mapper.freeOwned(User, a, &tmp);

        if (count == 0) {
            try std.testing.expectEqualStrings("bob", tmp.name);
            try std.testing.expectEqual(@as(i64, 20), tmp.age.?);
        } else if (count == 1) {
            try std.testing.expectEqualStrings("carol", tmp.name);
            try std.testing.expectEqual(@as(i64, 30), tmp.age.?);
        }
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 2), count);
}
