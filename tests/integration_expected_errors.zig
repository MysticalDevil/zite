const std = @import("std");
const orm = @import("zite");

test "expected error: Db.exec invalid SQL returns SqliteExecFailed" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    try std.testing.expectError(error.SqliteExecFailed, db.exec("THIS IS NOT SQL;"));
}

test "expected error: Stmt.init invalid SQL retures SqlitePrepareFailed" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    try std.testing.expectError(error.SqlitePrepareFailed, orm.Stmt.init(&db, "SELECT FROM ;"));
}

test "expected error: Stmt.bindOne out-of-range index returns SqliteBindFailed" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    var st = try orm.Stmt.init(&db, "SELECT ?1;");
    defer st.deinit();

    try std.testing.expectError(error.SqliteBindFailed, st.bindOne(2, @as(i64, 1)));
}

test "expected error: Stmt.step SQL runtime error returns SqliteStepFailed" {
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

    {
        var st1 = try orm.Stmt.init(&db, "INSERT INTO users(name) VALUES (?1);");
        defer st1.deinit();
        try st1.bindOne(1, "alice");
        try std.testing.expectEqual(orm.StepResult.done, try st1.step());
    }

    {
        var st2 = try orm.Stmt.init(&db, "INSERT INTO users(name) VALUES (?1);");
        defer st2.deinit();
        try st2.bindOne(1, "alice");
        try std.testing.expectError(error.SqliteStepFailed, st2.step());
    }
}
