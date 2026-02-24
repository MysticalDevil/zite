const std = @import("std");
const orm = @import("zite");

const types = orm.types;

const Sample = struct {
    id: i64,
    score: f64,
    created_at: types.UnixMillis,

    pub const Meta = .{
        .table = "sample",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

test "float + UnixMillis: insert -> getById -> findOne" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try orm.schema.createTableSqlFromMeta(a, Sample);
    defer a.free(ddl);
    try db.exec(ddl);

    const now = types.UnixMillis{ .value = 1700000000123 };

    const id = try orm.mapper.insert(Sample, &db, .{
        .id = 0,
        .score = 12.5,
        .created_at = now,
    });
    try std.testing.expect(id > 0);

    const got = (try orm.mapper.getById(Sample, &db, a, id)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 12.5), got.score, 0.000001);
    try std.testing.expectEqual(now.value, got.created_at.value);

    const P = @TypeOf(.{@as(i64, now.value)});
    const got2 = (try orm.mapper.findOne(Sample, P, &db, a, "\"created_at\"=?1", .{now.value})).?;
    try std.testing.expectEqual(id, got2.id);
}
