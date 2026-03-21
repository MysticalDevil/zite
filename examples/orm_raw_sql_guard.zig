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

    var user1 = User{
        .id = 1,
        .email = try OwnedText.fromConst(a, "a@example.com"),
    };
    defer repo.freeOwnedRow(&user1);
    _ = try repo.insert(user1);

    var user2 = User{
        .id = 2,
        .email = try OwnedText.fromConst(a, "b@example.com"),
    };
    defer repo.freeOwnedRow(&user2);
    _ = try repo.insert(user2);

    var search_email = try OwnedText.fromConst(a, "a@example.com");
    defer search_email.deinit(a);
    if (try repo.findOneSql("\"email\" = ?1", .{search_email})) |row| {
        var found = row;
        defer repo.freeOwnedRow(&found);
        std.debug.print("guarded lookup id={d} email={s}\n", .{ found.id, found.email.value });
    }

    const guarded = repo.findOneSql("1=1 --", .{});
    try std.testing.expectError(error.UnsafeSqlFragment, guarded);
    std.debug.print("guarded raw fragment rejected: UnsafeSqlFragment\n", .{});

    const unsafe = repo.findOneSqlUnsafe("1=1 --", .{});
    try std.testing.expectError(error.UnexpectedExtraRows, unsafe);
    std.debug.print("unsafe raw fragment executed: got UnexpectedExtraRows\n", .{});
}
