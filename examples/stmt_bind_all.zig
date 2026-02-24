const std = @import("std");
const Allocator = std.mem.Allocator;
const zite = @import("zite");

const OwnedText = zite.types.OwnedText;

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const a: Allocator = gpa;

    var db = try zite.Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);");

    var insert = try zite.Stmt.init(&db, "INSERT INTO notes (id, body) VALUES (?1, ?2);");
    defer insert.deinit();

    var body = try OwnedText.fromConst(a, "hello");
    defer body.deinit(a);

    try insert.bindAll(.{ 1, body });
    _ = try insert.step();
}
