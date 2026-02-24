const std = @import("std");
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

    var db = try zite.Db.open(gpa, ":memory:");
    defer db.deinit();

    const ddl = try zite.schema.createTableSqlFromMeta(gpa, User);
    defer gpa.free(ddl);
    try db.exec(ddl);

    var user = User{
        .id = 1,
        .email = try OwnedText.fromConst(gpa, "a@example.com"),
    };
    defer zite.mapper.freeOwnedRow(User, gpa, &user);
    _ = try zite.mapper.insert(User, &db, user);

    const Params = struct { email: []const u8 };
    if (try zite.mapper.findOne(User, Params, &db, gpa, "email = ?", .{ .email = "a@example.com" })) |found| {
        defer zite.mapper.freeOwnedRow(User, gpa, &found);
        std.debug.print("id={d}\n", .{found.id});
    }
}
