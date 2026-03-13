const std = @import("std");
const orm = @import("zite");
const helpers = @import("helpers.zig");

const User = struct {
    id: i64,
    name: orm.types.OwnedText,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

test "mapper.findManyWithOptions: supports order_by + limit + offset" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTableFromMeta(a, &db, User);

    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    var n2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer n2.deinit(a);
    var n3 = try orm.types.OwnedText.fromConst(a, "carol");
    defer n3.deinit(a);
    var n4 = try orm.types.OwnedText.fromConst(a, "dave");
    defer n4.deinit(a);

    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = n1 });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = n2 });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = n3 });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = n4 });

    const P = @TypeOf(.{});
    var rows = try orm.mapper.findManyWithOptions(
        User,
        P,
        &db,
        a,
        "",
        .{},
        .{
            .order_by = "\"id\" DESC",
            .limit = 2,
            .offset = 1,
        },
    );
    defer rows.deinit();

    var ids = std.ArrayList(i64).empty;
    defer ids.deinit(a);
    while (try rows.next()) |u| {
        var tmp = u;
        defer orm.mapper.freeOwnedRow(User, a, &tmp);
        try ids.append(a, tmp.id);
    }

    try std.testing.expectEqual(@as(usize, 2), ids.items.len);
    try std.testing.expectEqual(@as(i64, 3), ids.items[0]);
    try std.testing.expectEqual(@as(i64, 2), ids.items[1]);
}
