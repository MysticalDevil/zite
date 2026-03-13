const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const zite = @import("zite");

const OwnedText = zite.types.OwnedText;

const User = struct {
    id: i64,
    email: OwnedText,

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

    var db = try zite.Db.open(a, ":memory:");
    defer db.deinit();
    var repo = zite.orm.repository(User, &db, a);

    const ddl = try zite.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var user = User{
        .id = 1,
        .email = try OwnedText.fromConst(a, "a@example.com"),
    };
    defer repo.freeOwnedRow(&user);
    _ = try repo.insert(user);

    if (try repo.findOneRaw("email = ?1", .{"a@example.com"})) |found| {
        var owned = found;
        defer repo.freeOwnedRow(&owned);
        std.debug.print("id={d}\n", .{owned.id});
    }
}
