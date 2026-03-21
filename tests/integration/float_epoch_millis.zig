const std = @import("std");
const zite = @import("zite");
const orm = zite.orm(zite.drivers.sqlite3);

const types = orm.types;

const Sample = struct {
    id: i64,
    score: f64,
    created_at: types.EpochMillis,

    pub const Meta = .{
        .table = "sample",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

test "float + EpochMillis: insert -> findById -> findOne" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();
    var repo = orm.repository(Sample, &db, a);

    const ddl = try orm.schema.createTableSqlFromMeta(a, Sample);
    defer a.free(ddl);
    try db.exec(ddl);

    const now = types.EpochMillis{ .value = 1700000000123 };

    const id = try repo.insert(.{
        .id = 0,
        .score = 12.5,
        .created_at = now,
    });
    try std.testing.expect(id > 0);

    const got = (try repo.findById(id)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 12.5), got.score, 0.000001);
    try std.testing.expectEqual(now.value, got.created_at.value);

    const got2 = (try repo.findOneSql("\"created_at\"=?1", .{now.value})).?;
    try std.testing.expectEqual(id, got2.id);
}
