const std = @import("std");
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
    const gpa = std.heap.page_allocator;
    const a: Allocator = gpa;

    var db = try zite.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try zite.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var user = User{
        .id = 1,
        .email = try OwnedText.fromConst(a, "a@example.com"),
    };
    defer zite.mapper.freeOwnedRow(User, a, &user);
    _ = try zite.mapper.insert(User, &db, user);

    const Params = struct { email: []const u8 };
    if (try zite.mapper.findOne(User, Params, &db, a, "email = ?", .{ .email = "a@example.com" })) |found| {
        defer zite.mapper.freeOwnedRow(User, a, &found);
        std.debug.print("id={d}\n", .{found.id});
    }
}
