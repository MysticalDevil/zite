const std = @import("std");
const orm = @import("zite");
const helpers = @import("helpers.zig");

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
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTableFromMeta(a, &db, Doc);
    var repo = orm.orm.repository(Doc, &db, a);

    const payload = [_]u8{ 0, 1, 2, 3, 4, 5 };
    var data = try orm.types.OwnedBlob.fromConst(a, payload[0..]);
    defer data.deinit(a);
    _ = try repo.insert(.{
        .id = 0,
        .data = data,
    });

    var got = (try repo.findByIdOwned(@as(i64, 1))).?;
    defer got.deinit();

    try std.testing.expectEqual(@as(usize, payload.len), got.value.data.value.len);
    try std.testing.expect(std.mem.eql(u8, payload[0..], got.value.data.value));
}
