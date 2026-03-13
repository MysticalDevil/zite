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
    };
};

test "mapper.upsert: insert then update and no-op update keeps single row" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.orm.repository(User, &db, a);

    var name_insert = try orm.types.OwnedText.fromConst(a, "alice");
    defer name_insert.deinit(a);
    const inserted = try repo.upsert(.{
        .id = 1,
        .name = name_insert,
        .age = 20,
    });
    try std.testing.expectEqual(orm.orm.UpsertResult.inserted, inserted);

    var name_update = try orm.types.OwnedText.fromConst(a, "alice2");
    defer name_update.deinit(a);
    const updated = try repo.upsert(.{
        .id = 1,
        .name = name_update,
        .age = 30,
    });
    try std.testing.expectEqual(orm.orm.UpsertResult.updated, updated);

    var name_same = try orm.types.OwnedText.fromConst(a, "alice2");
    defer name_same.deinit(a);
    const updated_same = try repo.upsert(.{
        .id = 1,
        .name = name_same,
        .age = 30,
    });
    try std.testing.expectEqual(orm.orm.UpsertResult.updated, updated_same);

    var st_count = try orm.Stmt.init(&db, "SELECT COUNT(*) FROM users WHERE id=?1;");
    defer st_count.deinit();
    try st_count.bindInt(1, 1);
    try std.testing.expectEqual(orm.StepResult.row, try st_count.step());
    try std.testing.expectEqual(@as(i64, 1), try st_count.colInt(0));
    try std.testing.expectEqual(orm.StepResult.done, try st_count.step());

    var st_name = try orm.Stmt.init(&db, "SELECT name, age FROM users WHERE id=?1;");
    defer st_name.deinit();
    try st_name.bindInt(1, 1);
    try std.testing.expectEqual(orm.StepResult.row, try st_name.step());
    const name = (try st_name.colTextOwned(a, 0)).?;
    defer a.free(name);
    try std.testing.expectEqualStrings("alice2", name);
    try std.testing.expectEqual(@as(i64, 30), try st_name.colInt(1));
    try std.testing.expectEqual(orm.StepResult.done, try st_name.step());
}
