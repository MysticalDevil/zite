const std = @import("std");
const orm = @import("zite");

const User = struct {
    id: i64,
    name: []const u8,
    age: ?i64,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

test "owned: getByIdOwned and findManyOwned free via deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const chk = gpa.deinit();
        std.testing.expect(chk == .ok) catch unreachable;
    }
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try orm.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    const id1 = try orm.mapper.insert(User, &db, .{ .id = 0, .name = "alice", .age = 10 });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = "bob", .age = 20 });

    if (try orm.mapper.getByIdOwned(User, &db, a, id1)) |owned| {
        var o = owned;
        defer o.deinit();
        try std.testing.expectEqualStrings("alice", o.value.name);
    } else {
        return error.TestExpectedRow;
    }

    const P = @TypeOf(.{@as(i64, 0)});
    var rows = try orm.mapper.findManyOwned(User, P, &db, a, "\"id\">?1 ORDER BY \"id\" ASC", .{@as(i64, 0)});
    defer rows.deinit();

    var cnt: usize = 0;
    while (try rows.next()) |owned_row| {
        var r = owned_row;
        defer r.deinit();
        _ = r.value;
        cnt += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), cnt);
}
