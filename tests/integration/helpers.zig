const std = @import("std");
const orm = @import("zite");

pub fn openMemoryDb(a: std.mem.Allocator) !orm.Db {
    return orm.Db.open(a, ":memory:");
}

pub fn createTableFromMeta(a: std.mem.Allocator, db: *orm.Db, comptime T: type) !void {
    const ddl = try orm.schema.createTableSqlFromMeta(a, T);
    defer a.free(ddl);
    try db.exec(ddl);
}

pub fn createTable(a: std.mem.Allocator, db: *orm.Db, comptime T: type, table_name: []const u8) !void {
    const ddl = try orm.schema.createTableSql(a, T, .{ .table_name = table_name });
    defer a.free(ddl);
    try db.exec(ddl);
}
