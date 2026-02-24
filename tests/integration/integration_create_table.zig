const std = @import("std");
const orm = @import("zite");

const User = struct {
    id: i64,
    name: []const u8,
    age: ?u32,
    created_at: i64,
};

test "create table from struct and verify sqlite_master" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.close();

    const sql = try orm.schema.createTableSql(a, User, .{ .table_name = "users" });
    defer a.free(sql);
    try db.exec(sql);

    var found = false;

    const query = "SELECT name FROM sqlite_master WHERE type='table' AND name='users';";
    const qz = try a.dupeZ(u8, query);
    defer a.free(qz);

    const Callback = struct {
        pub fn cb(userdata: ?*anyopaque, argc: c_int, argv: [*c][*c]u8, col: [*c][*c]u8) callconv(.c) c_int {
            _ = argc;
            _ = argv;
            _ = col;

            const p: *bool = @ptrCast(@alignCast(userdata.?));
            p.* = true;
            return 0;
        }
    };

    var errmsg: [*c]u8 = null;
    defer if (errmsg != null) orm.raw.sqlite3_free(errmsg);

    const rc = orm.raw.sqlite3_exec(db.handle, qz.ptr, Callback.cb, &found, &errmsg);
    try std.testing.expectEqual(orm.raw.SQLITE_OK, rc);
    try std.testing.expect(found);
}
