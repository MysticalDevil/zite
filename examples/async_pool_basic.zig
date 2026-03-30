const std = @import("std");
const zite = @import("zite");
const Driver = zite.drivers.sqlite3;
const Db = zite.Db(Driver);
const AsyncPool = zite.AsyncPool(Driver);

const User = struct {
    id: i64,
    name: zite.types.OwnedText,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
    };
};

pub fn main(init: std.process.Init) !void {
    const a = init.gpa;
    const io = init.io;

    var db = try Db.open(a, "async_pool_basic.sqlite");
    defer db.deinit();
    try db.exec("DROP TABLE IF EXISTS users;");
    const ddl = try zite.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var pool = try AsyncPool.init(a, "async_pool_basic.sqlite", .{});
    defer pool.deinit();

    var name = try zite.types.OwnedText.fromConst(a, "alice");
    defer name.deinit(a);
    _ = try pool.insert(io, User, .{
        .id = 1,
        .name = name,
    });

    if (try pool.findByIdOwned(io, User, a, @as(i64, 1))) |row| {
        var owned = row;
        defer owned.deinit();
        std.debug.print("async user name={s}\n", .{owned.value.name.value});
    }
}
