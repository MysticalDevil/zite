const std = @import("std");
const zite = @import("zite");

pub fn openMemoryDb(a: std.mem.Allocator) !zite.Db(zite.drivers.sqlite3) {
    return zite.Db(zite.drivers.sqlite3).open(a, ":memory:");
}

pub fn createTableFromMeta(a: std.mem.Allocator, db: *zite.Db(zite.drivers.sqlite3), comptime T: type) !void {
    const ddl = try zite.schema.createTableSqlFromMeta(a, T);
    defer a.free(ddl);
    try db.exec(ddl);
}

pub fn createTable(a: std.mem.Allocator, db: *zite.Db(zite.drivers.sqlite3), comptime T: type, table_name: []const u8) !void {
    const ddl = try zite.schema.createTableSql(a, T, .{ .table_name = table_name });
    defer a.free(ddl);
    try db.exec(ddl);
}
