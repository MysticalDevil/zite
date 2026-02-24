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

test "owned: findByIdOwned and findManyOwned free via deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const chk = gpa.deinit();
        std.testing.expect(chk == .ok) catch unreachable;
    }
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTableFromMeta(a, &db, User);

    var name1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer name1.deinit(a);
    var name2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer name2.deinit(a);
    const id1 = try orm.mapper.insert(User, &db, .{ .id = 0, .name = name1, .age = 10 });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = name2, .age = 20 });

    if (try orm.mapper.findByIdOwned(User, &db, a, id1)) |owned| {
        var o = owned;
        defer o.deinit();
        try std.testing.expectEqualStrings("alice", o.value.name.value);
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

test "owned: empty text is released without leaks" {
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

    var empty = try orm.types.OwnedText.fromConst(a, "");
    defer empty.deinit(a);
    const id = try orm.mapper.insert(User, &db, .{ .id = 0, .name = empty, .age = null });
    if (try orm.mapper.findByIdOwned(User, &db, a, id)) |owned| {
        var o = owned;
        defer o.deinit();
        try std.testing.expectEqual(@as(usize, 0), o.value.name.value.len);
    } else {
        return error.TestExpectedRow;
    }
}
