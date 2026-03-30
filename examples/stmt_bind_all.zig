const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const zite = @import("zite");
const Driver = zite.drivers.sqlite3;
const Db = zite.Db(Driver);
const Stmt = zite.Stmt(Driver);

const OwnedText = zite.types.OwnedText;

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

    var body = try OwnedText.fromConst(a, "hello");
    defer body.deinit(a);

    try insert.bindAll(.{ 1, body });
    _ = try insert.step();
}
