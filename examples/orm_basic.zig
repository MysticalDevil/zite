const std = @import("std");
const Allocator = std.mem.Allocator;
const zite = @import("zite");

const OwnedText = zite.types.OwnedText;
const EpochMillis = zite.types.EpochMillis;

const User = struct {
    id: i64,
    name: OwnedText,
    created_at: EpochMillis,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
    };
};

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const a: Allocator = gpa;

    var db = try zite.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try zite.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var user = User{
        .id = 1,
        .name = try OwnedText.fromConst(a, "Alice"),
        .created_at = .{ .value = 1700000000000 },
    };
    defer zite.mapper.freeOwnedRow(User, a, &user);

    _ = try zite.mapper.insert(User, &db, user);

    if (try zite.mapper.findByIdOwned(User, &db, a, 1)) |row| {
        defer row.deinit();
        std.debug.print("name={s} created_at={d}\n", .{ row.value.name.value, row.value.created_at.value });
    }
}
