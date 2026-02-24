const std = @import("std");
const orm = @import("zite");

const Note = struct {
    id: i64,
    body: orm.types.Text,

    pub const Meta = .{
        .table = "notes",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

test "mapper: text round trip with types.Text" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try orm.schema.createTableSqlFromMeta(a, Note);
    defer a.free(ddl);
    try db.exec(ddl);

    var payload = "hello text".*;
    _ = try orm.mapper.insert(Note, &db, .{
        .id = 0,
        .body = .{ .value = payload[0..] },
    });

    var got = (try orm.mapper.getByIdOwned(Note, &db, a, @as(i64, 1))).?;
    defer got.deinit();

    try std.testing.expectEqualStrings(&payload, got.value.body.value);
}
