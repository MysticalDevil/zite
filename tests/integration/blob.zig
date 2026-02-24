const std = @import("std");
const orm = @import("zite");

const Doc = struct {
    id: i64,
    data: orm.types.OwnedBlob,

    pub const Meta = .{
        .table = "docs",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

test "mapper: blob round trip" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try orm.schema.createTableSqlFromMeta(a, Doc);
    defer a.free(ddl);
    try db.exec(ddl);

    const payload = [_]u8{ 0, 1, 2, 3, 4, 5 };
    const data = try orm.types.OwnedBlob.fromConst(a, payload[0..]);
    defer a.free(data.value);
    _ = try orm.mapper.insert(Doc, &db, .{
        .id = 0,
        .data = data,
    });

    var got = (try orm.mapper.findByIdOwned(Doc, &db, a, @as(i64, 1))).?;
    defer got.deinit();

    try std.testing.expectEqual(@as(usize, payload.len), got.value.data.value.len);
    try std.testing.expect(std.mem.eql(u8, payload[0..], got.value.data.value));
}
