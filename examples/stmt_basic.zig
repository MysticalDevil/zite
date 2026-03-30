const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const zite = @import("zite");
const Driver = zite.drivers.sqlite3;
const Db = zite.Db(Driver);
const Stmt = zite.Stmt(Driver);

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer {
        if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
            _ = debug_allocator.deinit();
        }
    }
    _ = &debug_allocator;
    const a: Allocator = switch (builtin.mode) {
        .Debug, .ReleaseSafe => debug_allocator.allocator(),
        .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
    };

    var db = try Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);");

    var insert = try Stmt.init(&db, "INSERT INTO notes (id, body) VALUES (?1, ?2);");
    defer insert.deinit();
    try insert.bindInt(1, 1);
    try insert.bindText(2, "hello");
    _ = try insert.step();

    var query = try Stmt.init(&db, "SELECT body FROM notes WHERE id=?1;");
    defer query.deinit();
    try query.bindInt(1, 1);

    if (try query.step() == .row) {
        if (try query.colTextOwned(a, 0)) |body| {
            defer a.free(body);
            std.debug.print("body={s}\n", .{body});
        }
    }
}
