const std = @import("std");
const orm = @import("zite");

fn containsAny(hay: []const u8, needles: []const []const u8) bool {
    for (needles) |n| {
        if (std.mem.indexOf(u8, hay, n) != null) return true;
    }
    return false;
}

test "errmsg: exec syntax error provides message" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    const r = db.exec("THIS IS NOT SQL;");
    try std.testing.expectError(error.SqliteExecFailed, r);

    const msg = db.errmsg();
    try std.testing.expect(msg.len != 0);
    try std.testing.expect(containsAny(msg, &.{ "syntax", "error" }));
}

test "errmsg: step runtime error provides message" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    try db.exec(
        \\CREATE TABLE users(
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL UNIQUE
        \\);
    );

    // 第一次插入成功
    {
        var st1 = try orm.Stmt.init(&db, "INSERT INTO users(name) VALUES (?1);");
        defer st1.deinit();
        try st1.bindOne(1, "alice");
        try std.testing.expectEqual(orm.StepResult.done, try st1.step());
    }

    // 第二次插入触发 UNIQUE 约束，prepare 成功，step 失败
    {
        var st2 = try orm.Stmt.init(&db, "INSERT INTO users(name) VALUES (?1);");
        defer st2.deinit();
        try st2.bindOne(1, "alice");
        try std.testing.expectError(error.SqliteStepFailed, st2.step());
    }

    const msg = db.errmsg();
    try std.testing.expect(msg.len != 0);
    try std.testing.expect(std.mem.indexOf(u8, msg, "UNIQUE constraint failed") != null);
}

test "errmsg: bind out-of-range provides message" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    var st = try orm.Stmt.init(&db, "SELECT ?1;");
    defer st.deinit();

    const r = st.bindOne(2, @as(i64, 1));
    try std.testing.expectError(error.SqliteBindFailed, r);

    const msg = db.errmsg();
    try std.testing.expect(msg.len != 0);
    try std.testing.expect(containsAny(msg, &.{ "range", "index", "bind" }));
}
