const std = @import("std");
const zite = @import("zite");
const Driver = zite.drivers.sqlite3;
const Db = zite.Db(Driver);
const Stmt = zite.Stmt(Driver);

pub fn main(init: std.process.Init) !void {
    const a = init.gpa;

    const body = init.environ_map.get("ZITE_NOTE_BODY") orelse "note-from-env-default";

    var db = try Db.open(a, ":memory:");
    defer db.deinit();
    try db.exec("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);");

    var insert = try Stmt.init(&db, "INSERT INTO notes (id, body) VALUES (?1, ?2);");
    defer insert.deinit();
    try insert.bindInt(1, 1);
    try insert.bindText(2, body);
    _ = try insert.step();

    var query = try Stmt.init(&db, "SELECT body FROM notes WHERE id=?1;");
    defer query.deinit();
    try query.bindInt(1, 1);

    if (try query.step() == .row) {
        if (try query.colTextOwned(a, 0)) |value| {
            defer a.free(value);
            std.debug.print("env note body={s}\n", .{value});
        }
    }
}
