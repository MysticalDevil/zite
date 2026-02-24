const std = @import("std");
const Allocator = std.mem.Allocator;
const zite = @import("zite");

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
    const gpa = std.heap.page_allocator;
    const a: Allocator = gpa;

    var db = try zite.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try zite.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var user1 = User{ .id = 1, .name = try OwnedText.fromConst(a, "Alice") };
    defer zite.mapper.freeOwnedRow(User, a, &user1);
    _ = try zite.mapper.insert(User, &db, user1);

    var user2 = User{ .id = 2, .name = try OwnedText.fromConst(a, "Bob") };
    defer zite.mapper.freeOwnedRow(User, a, &user2);
    _ = try zite.mapper.insert(User, &db, user2);

    const Params = struct { min_id: i64 };
    var rows = try zite.mapper.findMany(User, Params, &db, a, "id >= ?", .{ .min_id = 1 });
    defer rows.deinit();

    while (try rows.next()) |u| {
        defer zite.mapper.freeOwnedRow(User, a, &u);
        std.debug.print("id={d} name={s}\n", .{ u.id, u.name.value });
    }
}
