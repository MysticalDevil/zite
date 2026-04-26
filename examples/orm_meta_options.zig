const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const zite = @import("zite");
const Driver = zite.drivers.sqlite3;
const Db = zite.Db(Driver);

const OwnedText = zite.types.OwnedText;
const EpochMillis = zite.types.EpochMillis;

const User = struct {
    id: i64,
    name: OwnedText,
    email: OwnedText,
    created_at: EpochMillis,
    transient_field: OwnedText,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
        .rename = &.{
            .{ .field = "created_at", .column = "createdAt" },
        },
        .skip = &.{"transient_field"},
        .unique = &.{
            &.{"email"},
        },
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
    var repo = zite.repository(User, &db, a);

    const ddl = try zite.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var user = User{
        .id = 0,
        .name = try OwnedText.fromConst(a, "Alice"),
        .email = try OwnedText.fromConst(a, "alice@example.com"),
        .created_at = .{ .value = 1700000000000 },
        .transient_field = try OwnedText.fromConst(a, "skip"),
    };
    defer repo.freeOwnedRow(&user);

    _ = try repo.insert(user);
}
