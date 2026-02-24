const std = @import("std");
const Allocator = std.mem.Allocator;
const zite = @import("zite");

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const a: Allocator = gpa;

    var db = try zite.Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);");

    var insert = try zite.Stmt.init(&db, "INSERT INTO notes (id, body) VALUES (?1, ?2);");
    defer insert.deinit();
    try insert.bindInt(1, 1);
    try insert.bindText(2, "hello");
    _ = try insert.step();

    var query = try zite.Stmt.init(&db, "SELECT body FROM notes WHERE id=?1;");
    defer query.deinit();
    try query.bindInt(1, 1);

    if (try query.step() == .row) {
        if (try query.colTextOwned(a, 0)) |body| {
            defer a.free(body);
            std.debug.print("body={s}\n", .{body});
        }
    }
}
