const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const zite = @import("zite");
const Driver = zite.drivers.sqlite3;
const Db = zite.Db(Driver);
const Orm = zite.orm(Driver);

const OwnedText = zite.types.OwnedText;

const User = struct {
    id: i64,
    name: OwnedText,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
    };
};

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer {
        if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
            _ = debug_allocator.deinit();
        }
    }
    _ = &debug_allocator;
    const a: Allocator = switch (builtin.mode) {
        .Debug, .ReleaseSafe => debug_allocator.allocator(),
        .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
    };

    var db = try Db.open(a, ":memory:");
    defer db.deinit();
    var repo = Orm.repository(User, &db, a);

    const ddl = try zite.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var user1 = User{ .id = 1, .name = try OwnedText.fromConst(a, "Alice") };
    defer repo.freeOwnedRow(&user1);
    _ = try repo.insert(user1);

    var user2 = User{ .id = 2, .name = try OwnedText.fromConst(a, "Bob") };
    defer repo.freeOwnedRow(&user2);
    _ = try repo.insert(user2);

    var rows = try repo.findManySql("id >= ?1", .{@as(i64, 1)});
    defer rows.deinit();

    while (try rows.next()) |u| {
        var owned = u;
        defer repo.freeOwnedRow(&owned);
        std.debug.print("id={d} name={s}\n", .{ owned.id, owned.name.value });
    }
}
