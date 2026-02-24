const std = @import("std");
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

    var db = try zite.Db.open(gpa, ":memory:");
    defer db.deinit();

    const ddl = try zite.schema.createTableSqlFromMeta(gpa, User);
    defer gpa.free(ddl);
    try db.exec(ddl);

    var user = User{
        .id = 1,
        .name = try OwnedText.fromConst(gpa, "Alice"),
        .created_at = .{ .value = 1700000000000 },
    };
    defer zite.mapper.freeOwnedRow(User, gpa, &user);

    _ = try zite.mapper.insert(User, &db, user);

    if (try zite.mapper.findByIdOwned(User, &db, gpa, 1)) |row| {
        defer row.deinit();
        std.debug.print("name={s} created_at={d}\n", .{ row.value.name.value, row.value.created_at.value });
    }
}
