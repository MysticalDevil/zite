const std = @import("std");
const zite = @import("zite");
const orm = zite.orm(zite.drivers.sqlite3);
const helpers = @import("helpers.zig");

const User = struct {
    id: i64,
    name: orm.types.OwnedText,
    age: ?i64,

    pub const Meta = .{
        .table = "users",
    };
};

test "mapper.deleteById: removes record by primary key" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTable(a, &db, User, "users");
    var repo = orm.repository(User, &db, a);

    var name = try orm.types.OwnedText.fromConst(a, "alice");
    defer name.deinit(a);
    const id = try repo.insert(.{ .id = 0, .name = name, .age = null });
    try std.testing.expect(id > 0);

    const changed = try repo.deleteById(id);
    try std.testing.expectEqual(@as(i32, 1), changed);

    const found = try repo.findById(id);
    try std.testing.expect(found == null);
}

test "mapper.deleteById: returns 0 when id not found" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTable(a, &db, User, "users");
    var repo = orm.repository(User, &db, a);

    const changed = try repo.deleteById(@as(i64, 9999));
    try std.testing.expectEqual(@as(i32, 0), changed);
}

test "mapper.deleteWhere: deletes matching rows" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTable(a, &db, User, "users");
    var repo = orm.repository(User, &db, a);

    // Insert two rows
    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    var n2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer n2.deinit(a);
    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 30) });
    _ = try repo.insert(.{ .id = 0, .name = n2, .age = @as(?i64, 25) });

    // Delete only alice (age = 30)
    const changed = try repo.deleteWhereSql("\"age\"=?1", .{@as(i64, 30)});
    try std.testing.expectEqual(@as(i32, 1), changed);

    // Bob should still exist
    var bob_name = try orm.types.OwnedText.fromConst(a, "bob");
    defer bob_name.deinit(a);
    const bob = try repo.findOneSql("\"name\"=?1", .{bob_name});
    if (bob) |row| {
        var mut = row;
        repo.freeOwnedRow(&mut);
    } else {
        return error.ExpectedBobToExist;
    }
}

test "mapper.deleteWhere: empty clause is rejected" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTable(a, &db, User, "users");
    var repo = orm.repository(User, &db, a);

    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    var n2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer n2.deinit(a);
    _ = try repo.insert(.{ .id = 0, .name = n1, .age = null });
    _ = try repo.insert(.{ .id = 0, .name = n2, .age = null });

    try std.testing.expectError(error.EmptyWhereClause, repo.deleteWhereSql("", .{}));
}

test "mapper.deleteWhereSql: guarded API rejects unsafe fragment" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTable(a, &db, User, "users");
    var repo = orm.repository(User, &db, a);

    try std.testing.expectError(
        error.UnsafeSqlFragment,
        repo.deleteWhereSql("1=1 -- force", .{}),
    );
}

test "mapper.deleteWhereSqlUnsafe: preserves prior behavior" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTable(a, &db, User, "users");
    var repo = orm.repository(User, &db, a);

    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    var n2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer n2.deinit(a);
    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 30) });
    _ = try repo.insert(.{ .id = 0, .name = n2, .age = @as(?i64, 25) });

    const changed = try repo.deleteWhereSqlUnsafe("\"age\"=?1 -- trusted", .{@as(i64, 30)});
    try std.testing.expectEqual(@as(i32, 1), changed);
}
