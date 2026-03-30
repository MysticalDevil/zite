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
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

test "orm.query: whereEq/orderBy/limit/offset/whereSql" {
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

    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 20) });
    _ = try repo.insert(.{ .id = 0, .name = n2, .age = @as(?i64, 30) });
    _ = try repo.insert(.{ .id = 0, .name = n3, .age = @as(?i64, 40) });

    var q1 = repo.query();
    defer q1.deinit();
    try q1.whereEq("id", @as(i64, 2));
    const one = (try q1.firstOwned()).?;
    var one_mut = one;
    defer one_mut.deinit();
    try std.testing.expectEqualStrings("bob", one_mut.value.name.value);

    var q2 = repo.query();
    defer q2.deinit();
    try q2.whereSql("\"age\">?1", .{@as(i64, 20)});
    try q2.orderBy("id", .asc);
    q2.setLimit(1);
    q2.setOffset(1);
    const many = try q2.allOwned();
    defer a.free(many);
    defer for (many) |*row| row.deinit();

    try std.testing.expectEqual(@as(usize, 1), many.len);
    try std.testing.expectEqualStrings("carol", many[0].value.name.value);
}

test "orm.query: orderBy supports multi-column sort" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var n1 = try orm.types.OwnedText.fromConst(a, "b");
    defer n1.deinit(a);
    var n2 = try orm.types.OwnedText.fromConst(a, "a");
    defer n2.deinit(a);
    var n3 = try orm.types.OwnedText.fromConst(a, "c");
    defer n3.deinit(a);

    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 20) });
    _ = try repo.insert(.{ .id = 0, .name = n2, .age = @as(?i64, 20) });
    _ = try repo.insert(.{ .id = 0, .name = n3, .age = @as(?i64, 10) });

    var q = repo.query();
    defer q.deinit();
    try q.orderBy("age", .asc);
    try q.orderBy("name", .asc);

    const rows = try q.allOwned();
    defer a.free(rows);
    defer for (rows) |*row| row.deinit();

    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqualStrings("c", rows[0].value.name.value);
    try std.testing.expectEqualStrings("a", rows[1].value.name.value);
    try std.testing.expectEqualStrings("b", rows[2].value.name.value);
}

test "orm.query: iterateViews and row handle lookups are zero-copy" {
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
    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 11) });
    _ = try repo.insert(.{ .id = 0, .name = n2, .age = @as(?i64, 22) });

    var q = repo.query();
    defer q.deinit();
    try q.orderBy("id", .asc);

    var rows = try q.iterateViews();
    defer rows.deinit();

    const r1 = (try rows.next()).?;
    try std.testing.expectEqualStrings("alice", try r1.get("name"));
    try std.testing.expectEqual(@as(i64, 11), (try r1.get("age")).?);

    const r2 = (try rows.next()).?;
    try std.testing.expectEqualStrings("bob", try r2.get("name"));
    try std.testing.expectEqual(@as(i64, 22), (try r2.get("age")).?);
    try std.testing.expect((try rows.next()) == null);

    if (try repo.findByIdHandle(@as(i64, 2))) |one| {
        var got = one;
        defer got.deinit();
        try std.testing.expectEqualStrings("bob", try got.get("name"));
    } else {
        return error.TestExpectedRow;
    }

    if (try repo.findOneHandleSql("\"name\"=?1", .{"alice"})) |one_raw| {
        var got_raw = one_raw;
        defer got_raw.deinit();
        try std.testing.expectEqual(@as(i64, 1), try got_raw.get("id"));
        try std.testing.expectEqualStrings("alice", try got_raw.get("name"));
    } else {
        return error.TestExpectedRow;
    }
}

test "orm.query: row view becomes stale after cursor advances" {
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
    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 11) });
    _ = try repo.insert(.{ .id = 0, .name = n2, .age = @as(?i64, 22) });

    var q = repo.query();
    defer q.deinit();
    try q.orderBy("id", .asc);
    var rows = try q.iterateViews();
    defer rows.deinit();

    const r1 = (try rows.next()).?;
    _ = try rows.next();
    try std.testing.expectError(error.RowViewStale, r1.get("name"));
}

test "orm.query: row handle is invalid after deinit" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 11) });

    var one = (try repo.findByIdHandle(@as(i64, 1))).?;
    one.deinit();
    try std.testing.expectError(error.StatementFinalized, one.get("name"));
}

test "orm.query: firstHandle remains valid after query builder deinit" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 11) });

    var q = repo.query();
    try q.whereEq("id", @as(i64, 1));

    var handle = (try q.firstHandle()).?;
    q.deinit();
    defer handle.deinit();

    try std.testing.expectEqualStrings("alice", try handle.get("name"));
    try std.testing.expectEqual(@as(i64, 11), (try handle.get("age")).?);
}

test "orm.query: row view is finalized after cursor deinit" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 11) });

    var q = repo.query();
    defer q.deinit();
    var cursor = try q.iterateViews();

    const row = (try cursor.next()).?;
    cursor.deinit();

    try std.testing.expectError(error.StatementFinalized, row.get("name"));
}

test "orm.query: whereSql is atomic when param conversion fails" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var q = repo.query();
    defer q.deinit();

    const where_len_before = q.where_buf.items.len;
    const params_len_before = q.params.items.len;

    const bad = [_]i32{ 1, 2 };
    try std.testing.expectError(
        error.UnsupportedBindType,
        q.whereSql("\"id\"=?1", .{bad[0..]}),
    );

    try std.testing.expectEqual(where_len_before, q.where_buf.items.len);
    try std.testing.expectEqual(params_len_before, q.params.items.len);
}

test "orm.query: guarded raw APIs reject unsafe SQL fragments" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var q = repo.query();
    defer q.deinit();

    try std.testing.expectError(error.UnsafeSqlFragment, q.whereSql("\"id\"=?1; DROP TABLE users", .{@as(i64, 1)}));
    try std.testing.expectError(error.UnsafeSqlFragment, q.whereSql("1=1 -- force", .{}));
    try std.testing.expectError(error.UnsafeSqlFragment, q.whereSql("\"id\" IN (SELECT id FROM users)", .{}));

    try std.testing.expectError(error.UnsafeSqlFragment, repo.findOneSql("1=1 -- force", .{}));
    try std.testing.expectError(error.UnsafeSqlFragment, repo.findOneHandleSql("1=1 -- force", .{}));
    try std.testing.expectError(error.UnsafeSqlFragment, repo.findManySql("1=1 -- force", .{}));
    try std.testing.expectError(error.UnsafeSqlFragment, repo.findManyOwnedSql("1=1 -- force", .{}));
}

test "orm.query: unsafe raw APIs preserve prior behavior" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();
    try helpers.createTableFromMeta(a, &db, User);
    var repo = orm.repository(User, &db, a);

    var n1 = try orm.types.OwnedText.fromConst(a, "alice");
    defer n1.deinit(a);
    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 11) });

    var q = repo.query();
    defer q.deinit();
    try q.whereSqlUnsafe("\"id\"=?1 -- keep", .{@as(i64, 1)});
    const one = (try q.firstOwned()).?;
    var one_mut = one;
    defer one_mut.deinit();
    try std.testing.expectEqualStrings("alice", one_mut.value.name.value);

    if (try repo.findOneHandleSqlUnsafe("\"name\"=?1 -- keep", .{"alice"})) |h| {
        var handle = h;
        defer handle.deinit();
        try std.testing.expectEqualStrings("alice", try handle.get("name"));
    } else {
        return error.TestExpectedRow;
    }

    var rows = try repo.findManySqlUnsafe("\"id\"=?1 -- keep", .{@as(i64, 1)});
    defer rows.deinit();
    const found_row = (try rows.next()).?;
    var found_mut = found_row;
    defer repo.freeOwnedRow(&found_mut);
    try std.testing.expectEqualStrings("alice", found_mut.name.value);

    var owned_rows = try repo.findManyOwnedSqlUnsafe("\"id\"=?1 -- keep", .{@as(i64, 1)});
    defer owned_rows.deinit();
    const owned = (try owned_rows.next()).?;
    var owned_mut = owned;
    defer owned_mut.deinit();
    try std.testing.expectEqualStrings("alice", owned_mut.value.name.value);
}

test "orm.query: whereSql then whereEq keeps placeholder indices aligned" {
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
    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 30) });
    _ = try repo.insert(.{ .id = 0, .name = n2, .age = @as(?i64, 40) });

    var q = repo.query();
    defer q.deinit();
    try q.whereSql("\"name\"=?1", .{"bob"});
    try q.whereEq("age", @as(i64, 40)); // should bind as ?2

    const one = (try q.firstOwned()).?;
    var one_mut = one;
    defer one_mut.deinit();
    try std.testing.expectEqualStrings("bob", one_mut.value.name.value);
    try std.testing.expectEqual(@as(i64, 40), one_mut.value.age.?);
}

test "orm.query: whereEq then whereSql rebases relative placeholders" {
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
    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 30) });
    _ = try repo.insert(.{ .id = 0, .name = n2, .age = @as(?i64, 40) });

    var q = repo.query();
    defer q.deinit();
    try q.whereEq("age", @as(i64, 30)); // uses ?1
    try q.whereSql("\"name\"=?1", .{"alice"});

    const one = (try q.firstOwned()).?;
    var one_mut = one;
    defer one_mut.deinit();
    try std.testing.expectEqualStrings("alice", one_mut.value.name.value);
    try std.testing.expectEqual(@as(i64, 30), one_mut.value.age.?);
}

test "orm.query: whereSql rebases anonymous placeholders after whereEq" {
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
    _ = try repo.insert(.{ .id = 0, .name = n1, .age = @as(?i64, 30) });
    _ = try repo.insert(.{ .id = 0, .name = n2, .age = @as(?i64, 40) });

    var q = repo.query();
    defer q.deinit();
    try q.whereEq("age", @as(i64, 40));
    try q.whereSql("\"name\"=?", .{"bob"});

    const one = (try q.firstOwned()).?;
    var one_mut = one;
    defer one_mut.deinit();
    try std.testing.expectEqualStrings("bob", one_mut.value.name.value);
    try std.testing.expectEqual(@as(i64, 40), one_mut.value.age.?);
}
