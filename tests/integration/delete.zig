const std = @import("std");
const orm = @import("zite");
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

    var name = try orm.types.OwnedText.fromConst(a, "alice");
    defer name.deinit(a);
    const id = try orm.mapper.insert(User, &db, .{ .id = 0, .name = name, .age = null });
    try std.testing.expect(id > 0);

    const changed = try orm.mapper.deleteById(User, &db, id);
    try std.testing.expectEqual(@as(i32, 1), changed);

    const found = try orm.mapper.findById(User, &db, a, id);
    try std.testing.expect(found == null);
}

test "mapper.deleteById: returns 0 when id not found" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTable(a, &db, User, "users");

    const changed = try orm.mapper.deleteById(User, &db, 9999);
    try std.testing.expectEqual(@as(i32, 0), changed);
}

test "mapper.deleteWhere: deletes matching rows" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTable(a, &db, User, "users");

    // Insert two rows
    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    var n2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer n2.deinit(a);
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = n1, .age = @as(?i64, 30) });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = n2, .age = @as(?i64, 25) });

    // Delete only alice (age = 30)
    const changed = try orm.mapper.deleteWhere(User, @TypeOf(.{@as(i64, 30)}), &db, "\"age\"=?1", .{@as(i64, 30)});
    try std.testing.expectEqual(@as(i32, 1), changed);

    // Bob should still exist
    var bob_name = try orm.types.OwnedText.fromConst(a, "bob");
    defer bob_name.deinit(a);
    const P = @TypeOf(.{bob_name});
    const bob = try orm.mapper.findOne(User, P, &db, a, "\"name\"=?1", .{bob_name});
    if (bob) |row| {
        var mut = row;
        orm.mapper.freeOwnedRow(User, a, &mut);
    } else {
        return error.ExpectedBobToExist;
    }
}

test "mapper.deleteWhere: no clause deletes all" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTable(a, &db, User, "users");

    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    var n2 = try orm.types.OwnedText.fromConst(a, "bob");
    defer n2.deinit(a);
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = n1, .age = null });
    _ = try orm.mapper.insert(User, &db, .{ .id = 0, .name = n2, .age = null });

    const changed = try orm.mapper.deleteWhere(User, @TypeOf(.{}), &db, "", .{});
    try std.testing.expectEqual(@as(i32, 2), changed);
}
