const std = @import("std");
const zite = @import("zite");
const orm = zite.orm(zite.drivers.sqlite3);
const helpers = @import("helpers.zig");

test "tx types are exposed from root and orm" {
    const m1: orm.TxMode = .deferred;
    _ = m1;
    const m2: orm.TxMode = .immediate;
    _ = m2;
}

const User = struct {
    id: i64,
    name: orm.types.OwnedText,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

test "orm transaction: commit persists rows" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var tx = try repo.beginTx(.deferred);
    defer tx.deinit();

    var n = try orm.types.OwnedText.fromConst(a, "alice");
    defer n.deinit(a);
    _ = try repo.insert(.{ .id = 0, .name = n });
    try tx.commit();

    const found = try repo.findByIdOwned(@as(i64, 1));
    try std.testing.expect(found != null);
    if (found) |row| {
        var owned = row;
        defer owned.deinit();
        try std.testing.expectEqualStrings("alice", owned.value.name.value);
    }
}

test "orm transaction: rollback drops rows" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    {
        var tx = try repo.beginTx(.deferred);
        defer tx.deinit();
        var n = try orm.types.OwnedText.fromConst(a, "alice");
        defer n.deinit(a);
        _ = try repo.insert(.{ .id = 0, .name = n });
        // no commit
    }

    const found = try repo.findByIdOwned(@as(i64, 1));
    try std.testing.expect(found == null);
}

test "orm transaction: explicit rollback drops rows" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var tx = try repo.beginTx(.deferred);
    defer tx.deinit();
    var n = try orm.types.OwnedText.fromConst(a, "alice");
    defer n.deinit(a);
    _ = try repo.insert(.{ .id = 0, .name = n });
    try tx.rollback();

    const found = try repo.findByIdOwned(@as(i64, 1));
    try std.testing.expect(found == null);
}
