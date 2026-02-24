const std = @import("std");
const zite = @import("zite");

const OwnedText = zite.types.OwnedText;

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    var db = try zite.Db.open(gpa, ":memory:");
    defer db.deinit();

    try db.exec("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);");

    var insert = try zite.Stmt.init(&db, "INSERT INTO notes (id, body) VALUES (?1, ?2);");
    defer insert.deinit();

    var body = try OwnedText.fromConst(gpa, "hello");
    defer body.deinit(gpa);

    try insert.bindAll(.{ 1, body });
    _ = try insert.step();
}
