const std = @import("std");
const zite = @import("zite");
const orm = zite.orm(zite.drivers.sqlite3);
const helpers = @import("helpers.zig");

const User = struct {
    id: i64,
    name: orm.types.OwnedText,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
        .order_by = "\"id\" DESC",
    };
};

test "mapper.findManySqlWithOptions: supports meta default order_by and explicit override" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    var n2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer n2.deinit(a);
    var n3 = try orm.types.OwnedText.fromConst(a, "carol");
    defer n3.deinit(a);
    var n4 = try orm.types.OwnedText.fromConst(a, "dave");
    defer n4.deinit(a);

    _ = try repo.insert(.{ .id = 0, .name = n1 });
    _ = try repo.insert(.{ .id = 0, .name = n2 });
    _ = try repo.insert(.{ .id = 0, .name = n3 });
    _ = try repo.insert(.{ .id = 0, .name = n4 });

    // Meta.default order_by should apply when opts.order_by is null.
    var rows_default = try repo.findManySql("", .{});
    defer rows_default.deinit();

    if (try rows_default.next()) |u| {
        var tmp = u;
        defer repo.freeOwnedRow(&tmp);
        try std.testing.expectEqual(@as(i64, 4), tmp.id);
    } else {
        return error.TestExpectedEqual;
    }

    // Explicit options override Meta.order_by.
    var rows = try repo.findManySqlWithOptions("", .{}, .{
        .order_by = "\"id\" ASC",
        .limit = 2,
        .offset = 1,
    });
    defer rows.deinit();

    var ids = std.ArrayList(i64).empty;
    defer ids.deinit(a);
    while (try rows.next()) |u| {
        var tmp = u;
        defer repo.freeOwnedRow(&tmp);
        try ids.append(a, tmp.id);
    }

    try std.testing.expectEqual(@as(usize, 2), ids.items.len);
    try std.testing.expectEqual(@as(i64, 2), ids.items[0]);
    try std.testing.expectEqual(@as(i64, 3), ids.items[1]);
}

test "mapper.findManySqlWithOptions: guarded order_by rejects unsafe fragments" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    try std.testing.expectError(
        error.UnsafeSqlFragment,
        repo.findManySqlWithOptions("", .{}, .{
            .order_by = "\"id\" ASC; DROP TABLE users",
        }),
    );

    try std.testing.expectError(
        error.UnsafeSqlFragment,
        repo.findManySqlWithOptions("", .{}, .{
            .order_by = "\"id\" ASC -- force",
        }),
    );
}

test "mapper.findManySqlWithOptionsUnsafe: keeps previous behavior for trusted SQL" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    var n2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer n2.deinit(a);
    _ = try repo.insert(.{ .id = 0, .name = n1 });
    _ = try repo.insert(.{ .id = 0, .name = n2 });

    var rows = try repo.findManySqlWithOptionsUnsafe("\"id\">?1", .{@as(i64, 0)}, .{
        .order_by = "\"id\" DESC -- trusted",
        .limit = 1,
    });
    defer rows.deinit();

    const first = (try rows.next()).?;
    var first_mut = first;
    defer repo.freeOwnedRow(&first_mut);
    try std.testing.expectEqual(@as(i64, 2), first_mut.id);
}
