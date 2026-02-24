const std = @import("std");
const zite = @import("zite");

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
        .skip = &.{ "transient_field" },
        .unique = &.{
            &.{ "email" },
        },
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
        .id = 0,
        .name = try OwnedText.fromConst(gpa, "Alice"),
        .email = try OwnedText.fromConst(gpa, "alice@example.com"),
        .created_at = .{ .value = 1700000000000 },
        .transient_field = try OwnedText.fromConst(gpa, "skip"),
    };
    defer zite.mapper.freeOwnedRow(User, gpa, &user);

    _ = try zite.mapper.insert(User, &db, user);
}
