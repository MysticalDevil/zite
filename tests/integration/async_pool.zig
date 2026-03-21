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
    };
};

fn makeDbPath(allocator: std.mem.Allocator, tmp: *std.testing.TmpDir, file_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/{s}",
        .{ tmp.sub_path, file_name },
    );
}

fn initThreadedIo() std.Io.Threaded {
    return .init(std.testing.allocator, .{});
}

fn initFileDb(comptime T: type, file_name: []const u8) !struct {
    tmp: std.testing.TmpDir,
    db_path: []u8,
} {
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();

    const db_path = try makeDbPath(std.testing.allocator, &tmp, file_name);
    errdefer std.testing.allocator.free(db_path);

    var db = try zite.Db.open(std.testing.allocator, db_path);
    defer db.deinit();
    try helpers.createTableFromMeta(std.testing.allocator, &db, T);

    return .{
        .tmp = tmp,
        .db_path = db_path,
    };
}

test "async_pool: insert and findByIdOwned" {
    var io_instance = initThreadedIo();
    defer io_instance.deinit();
    const io = io_instance.io();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const db_path = try makeDbPath(std.testing.allocator, &tmp, "async.sqlite");
    defer std.testing.allocator.free(db_path);

    {
        var db = try zite.Db.open(std.testing.allocator, db_path);
        defer db.deinit();
        try helpers.createTableFromMeta(std.testing.allocator, &db, User);
    }

    var pool = try zite.AsyncPool.init(std.testing.allocator, db_path, .{});
    defer pool.deinit();

    var inserted_name = try zite.types.OwnedText.fromConst(std.testing.allocator, "alice");
    defer inserted_name.deinit(std.testing.allocator);
    _ = try pool.insert(io, User, .{
        .id = 1,
        .name = inserted_name,
        .age = 20,
    });

    const row_opt = try pool.findByIdOwned(io, User, std.testing.allocator, @as(i64, 1));
    try std.testing.expect(row_opt != null);
    var row = row_opt.?;
    defer row.deinit();
    try std.testing.expectEqualStrings("alice", row.value.name.value);
    try std.testing.expectEqual(@as(i64, 20), row.value.age.?);
}

fn findUserNameTask(args: struct {
    pool: *const zite.AsyncPool,
    io: std.Io,
    allocator: std.mem.Allocator,
    id: i64,
}) zite.errors.AsyncOrmError![]u8 {
    const row_opt = try args.pool.findByIdOwned(args.io, User, args.allocator, args.id);
    var row = row_opt orelse return error.UnexpectedNull;
    defer row.deinit();
    return try args.allocator.dupe(u8, row.value.name.value);
}

test "async_pool: concurrent findByIdOwned queries" {
    var io_instance = initThreadedIo();
    defer io_instance.deinit();
    const io = io_instance.io();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const db_path = try makeDbPath(std.testing.allocator, &tmp, "async-concurrent.sqlite");
    defer std.testing.allocator.free(db_path);

    {
        var db = try zite.Db.open(std.testing.allocator, db_path);
        defer db.deinit();
        try helpers.createTableFromMeta(std.testing.allocator, &db, User);
        var repo = zite.orm.repository(User, &db, std.testing.allocator);

        var n1 = try zite.types.OwnedText.fromConst(std.testing.allocator, "alice");
        defer n1.deinit(std.testing.allocator);
        var n2 = try zite.types.OwnedText.fromConst(std.testing.allocator, "bob");
        defer n2.deinit(std.testing.allocator);
        _ = try repo.insert(.{ .id = 1, .name = n1, .age = 30 });
        _ = try repo.insert(.{ .id = 2, .name = n2, .age = 40 });
    }

    var pool = try zite.AsyncPool.init(std.testing.allocator, db_path, .{});
    defer pool.deinit();

    var f1 = try std.Io.concurrent(io, findUserNameTask, .{.{
        .pool = &pool,
        .io = io,
        .allocator = std.testing.allocator,
        .id = 1,
    }});
    var f2 = try std.Io.concurrent(io, findUserNameTask, .{.{
        .pool = &pool,
        .io = io,
        .allocator = std.testing.allocator,
        .id = 2,
    }});
    const name1 = try f1.await(io);
    defer std.testing.allocator.free(name1);
    const name2 = try f2.await(io);
    defer std.testing.allocator.free(name2);

    try std.testing.expectEqualStrings("alice", name1);
    try std.testing.expectEqualStrings("bob", name2);
}

test "async_pool: open failure propagates" {
    var io_instance = initThreadedIo();
    defer io_instance.deinit();
    const io = io_instance.io();

    var pool = try zite.AsyncPool.init(
        std.testing.allocator,
        "/definitely/missing/zite/async/open-failure.sqlite",
        .{},
    );
    defer pool.deinit();

    var inserted_name = try zite.types.OwnedText.fromConst(std.testing.allocator, "alice");
    defer inserted_name.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.SqliteCantOpen,
        pool.insert(io, User, .{
            .id = 1,
            .name = inserted_name,
            .age = 20,
        }),
    );
}

test "async_pool: findOne returns owned row value and caller frees it" {
    var io_instance = initThreadedIo();
    defer io_instance.deinit();
    const io = io_instance.io();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const db_path = try makeDbPath(std.testing.allocator, &tmp, "async-find-one.sqlite");
    defer std.testing.allocator.free(db_path);

    {
        var db = try zite.Db.open(std.testing.allocator, db_path);
        defer db.deinit();
        try helpers.createTableFromMeta(std.testing.allocator, &db, User);
        var repo = zite.orm.repository(User, &db, std.testing.allocator);

        var name = try zite.types.OwnedText.fromConst(std.testing.allocator, "carol");
        defer name.deinit(std.testing.allocator);
        _ = try repo.insert(.{ .id = 3, .name = name, .age = 50 });
    }

    var pool = try zite.AsyncPool.init(std.testing.allocator, db_path, .{});
    defer pool.deinit();

    var name_param = try zite.types.OwnedText.fromConst(std.testing.allocator, "carol");
    defer name_param.deinit(std.testing.allocator);
    const user_opt = try pool.findOne(io, User, std.testing.allocator, "\"name\"=?1", .{name_param});
    try std.testing.expect(user_opt != null);
    var user = user_opt.?;
    defer zite.AsyncPool.freeOwnedRow(User, std.testing.allocator, &user);
    try std.testing.expectEqualStrings("carol", user.name.value);
    try std.testing.expectEqual(@as(i64, 50), user.age.?);
}

test "async_pool: update persists changes" {
    var io_instance = initThreadedIo();
    defer io_instance.deinit();
    const io = io_instance.io();

    var fixture = try initFileDb(User, "async-update.sqlite");
    defer fixture.tmp.cleanup();
    defer std.testing.allocator.free(fixture.db_path);

    {
        var db = try zite.Db.open(std.testing.allocator, fixture.db_path);
        defer db.deinit();
        var repo = zite.orm.repository(User, &db, std.testing.allocator);
        var name = try zite.types.OwnedText.fromConst(std.testing.allocator, "alice");
        defer name.deinit(std.testing.allocator);
        _ = try repo.insert(.{ .id = 1, .name = name, .age = 20 });
    }

    var pool = try zite.AsyncPool.init(std.testing.allocator, fixture.db_path, .{});
    defer pool.deinit();

    var updated_name = try zite.types.OwnedText.fromConst(std.testing.allocator, "alice-updated");
    defer updated_name.deinit(std.testing.allocator);
    const changed = try pool.update(io, User, .{
        .id = 1,
        .name = updated_name,
        .age = 99,
    });
    try std.testing.expectEqual(@as(i32, 1), changed);

    const row_opt = try pool.findByIdOwned(io, User, std.testing.allocator, @as(i64, 1));
    try std.testing.expect(row_opt != null);
    var row = row_opt.?;
    defer row.deinit();
    try std.testing.expectEqualStrings("alice-updated", row.value.name.value);
    try std.testing.expectEqual(@as(i64, 99), row.value.age.?);
}

test "async_pool: deleteById removes row" {
    var io_instance = initThreadedIo();
    defer io_instance.deinit();
    const io = io_instance.io();

    var fixture = try initFileDb(User, "async-delete.sqlite");
    defer fixture.tmp.cleanup();
    defer std.testing.allocator.free(fixture.db_path);

    {
        var db = try zite.Db.open(std.testing.allocator, fixture.db_path);
        defer db.deinit();
        var repo = zite.orm.repository(User, &db, std.testing.allocator);
        var name = try zite.types.OwnedText.fromConst(std.testing.allocator, "bob");
        defer name.deinit(std.testing.allocator);
        _ = try repo.insert(.{ .id = 1, .name = name, .age = 40 });
    }

    var pool = try zite.AsyncPool.init(std.testing.allocator, fixture.db_path, .{});
    defer pool.deinit();

    const changed = try pool.deleteById(io, User, @as(i64, 1));
    try std.testing.expectEqual(@as(i32, 1), changed);
    try std.testing.expect((try pool.findByIdOwned(io, User, std.testing.allocator, @as(i64, 1))) == null);
}

test "async_pool: upsert inserts then updates" {
    var io_instance = initThreadedIo();
    defer io_instance.deinit();
    const io = io_instance.io();

    var fixture = try initFileDb(User, "async-upsert.sqlite");
    defer fixture.tmp.cleanup();
    defer std.testing.allocator.free(fixture.db_path);

    var pool = try zite.AsyncPool.init(std.testing.allocator, fixture.db_path, .{});
    defer pool.deinit();

    var name1 = try zite.types.OwnedText.fromConst(std.testing.allocator, "alice");
    defer name1.deinit(std.testing.allocator);
    const first = try pool.upsert(io, User, .{
        .id = 1,
        .name = name1,
        .age = 20,
    });
    try std.testing.expectEqual(zite.orm.UpsertResult.inserted, first);

    var name2 = try zite.types.OwnedText.fromConst(std.testing.allocator, "alice-updated");
    defer name2.deinit(std.testing.allocator);
    const second = try pool.upsert(io, User, .{
        .id = 1,
        .name = name2,
        .age = 21,
    });
    try std.testing.expectEqual(zite.orm.UpsertResult.updated, second);

    const row_opt = try pool.findByIdOwned(io, User, std.testing.allocator, @as(i64, 1));
    try std.testing.expect(row_opt != null);
    var row = row_opt.?;
    defer row.deinit();
    try std.testing.expectEqualStrings("alice-updated", row.value.name.value);
    try std.testing.expectEqual(@as(i64, 21), row.value.age.?);
}

test "async_pool: insert propagates SqliteConstraint" {
    var io_instance = initThreadedIo();
    defer io_instance.deinit();
    const io = io_instance.io();

    var fixture = try initFileDb(User, "async-constraint.sqlite");
    defer fixture.tmp.cleanup();
    defer std.testing.allocator.free(fixture.db_path);

    {
        var db = try zite.Db.open(std.testing.allocator, fixture.db_path);
        defer db.deinit();
        try db.exec("DROP TABLE users;");
        try db.exec(
            "CREATE TABLE users (" ++
                "id INTEGER PRIMARY KEY AUTOINCREMENT, " ++
                "name TEXT NOT NULL UNIQUE, " ++
                "age INTEGER" ++
                ");",
        );
    }

    var pool = try zite.AsyncPool.init(std.testing.allocator, fixture.db_path, .{});
    defer pool.deinit();

    var name1 = try zite.types.OwnedText.fromConst(std.testing.allocator, "dup");
    defer name1.deinit(std.testing.allocator);
    _ = try pool.insert(io, User, .{
        .id = 0,
        .name = name1,
        .age = null,
    });

    var name2 = try zite.types.OwnedText.fromConst(std.testing.allocator, "dup");
    defer name2.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.SqliteConstraint,
        pool.insert(io, User, .{
            .id = 0,
            .name = name2,
            .age = null,
        }),
    );
}

test "async_pool: missing rows return null" {
    var io_instance = initThreadedIo();
    defer io_instance.deinit();
    const io = io_instance.io();

    var fixture = try initFileDb(User, "async-null.sqlite");
    defer fixture.tmp.cleanup();
    defer std.testing.allocator.free(fixture.db_path);

    var pool = try zite.AsyncPool.init(std.testing.allocator, fixture.db_path, .{});
    defer pool.deinit();

    try std.testing.expect((try pool.findByIdOwned(io, User, std.testing.allocator, @as(i64, 999))) == null);

    var nobody = try zite.types.OwnedText.fromConst(std.testing.allocator, "nobody");
    defer nobody.deinit(std.testing.allocator);
    try std.testing.expect((try pool.findOne(io, User, std.testing.allocator, "\"name\"=?1", .{nobody})) == null);
}
