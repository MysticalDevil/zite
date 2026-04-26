const std = @import("std");
const zite = @import("zite");
const helpers = @import("helpers.zig");

const User = struct {
    id: i64,
    name: zite.types.OwnedText,
    age: ?i64,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

test "mapper.insertMany: inserts multiple rows and supports empty input" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTableFromMeta(a, &db, User);
    var repo = zite.repository(User, &db, a);

    var n1 = try zite.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    var n2 = try zite.types.OwnedText.fromConst(a, "bob");
    defer n2.deinit(a);
    var n3 = try zite.types.OwnedText.fromConst(a, "carol");
    defer n3.deinit(a);

    const inserted = try repo.insertMany(&[_]User{
        .{ .id = 0, .name = n1, .age = 20 },
        .{ .id = 0, .name = n2, .age = null },
        .{ .id = 0, .name = n3, .age = 30 },
    });
    try std.testing.expectEqual(@as(usize, 3), inserted);

    const inserted_empty = try repo.insertMany(&[_]User{});
    try std.testing.expectEqual(@as(usize, 0), inserted_empty);

    var st_count = try zite.Stmt(zite.drivers.sqlite3).init(&db, "SELECT COUNT(*) FROM users;");
    defer st_count.deinit();
    try std.testing.expectEqual(zite.StepResult.row, try st_count.step());
    try std.testing.expectEqual(@as(i64, 3), try st_count.colInt(0));
    try std.testing.expectEqual(zite.StepResult.done, try st_count.step());
}
