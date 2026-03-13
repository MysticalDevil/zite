const std = @import("std");
const orm = @import("zite");
const helpers = @import("helpers.zig");

const Note = struct {
    id: i64,
    body: orm.types.OwnedText,

    pub const Meta = .{
        .table = "notes",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

test "mapper: text round trip with types.OwnedText" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    try helpers.createTableFromMeta(a, &db, Note);
    var repo = orm.orm.repository(Note, &db, a);

    const payload = "hello text";
    var body = try orm.types.OwnedText.fromConst(a, payload);
    defer body.deinit(a);
    _ = try repo.insert(.{
        .id = 0,
        .body = body,
    });

    var got = (try repo.findByIdOwned(@as(i64, 1))).?;
    defer got.deinit();

    try std.testing.expectEqualStrings(payload, got.value.body.value);
}
