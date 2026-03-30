const std = @import("std");
const zite = @import("zite");
const orm = zite.orm(zite.drivers.sqlite3);

fn returnType(comptime function: anytype) type {
    return @typeInfo(@TypeOf(function)).@"fn".return_type orelse
        @compileError("function must have an explicit return type");
}

test "expected error: Db.exec invalid SQL returns DriverExecFailed" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    try std.testing.expectError(error.DriverExecFailed, db.exec("THIS IS NOT SQL;"));
}

test "expected error: Stmt.init invalid SQL retures DriverPrepareFailed" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    try std.testing.expectError(error.DriverPrepareFailed, orm.Stmt.init(&db, "SELECT FROM ;"));
}

test "expected error: Stmt.bindOne out-of-range index returns DriverRange" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    var st = try orm.Stmt.init(&db, "SELECT ?1;");
    defer st.deinit();

    try std.testing.expectError(error.DriverRange, st.bindOne(2, @as(i64, 1)));
}

test "expected error: Stmt.step SQL runtime error returns DriverConstraint" {
    var gpa = std.heap.DebugAllocator(.{}).init;
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
        var name1 = try orm.types.OwnedText.fromConst(a, "alice");
        defer name1.deinit(a);
        try st1.bindOne(1, name1);
        try std.testing.expectEqual(orm.StepResult.done, try st1.step());
    }

    {
        var st2 = try orm.Stmt.init(&db, "INSERT INTO users(name) VALUES (?1);");
        defer st2.deinit();
        var name2 = try orm.types.OwnedText.fromConst(a, "alice");
        defer name2.deinit(a);
        try st2.bindOne(1, name2);
        try std.testing.expectError(error.DriverConstraint, st2.step());
    }
}

test "expected error: operations after close return DriverMisuse" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    db.close();
    db.close();

    try std.testing.expectError(error.DriverMisuse, db.exec("SELECT 1;"));
    try std.testing.expectError(error.DriverMisuse, orm.Stmt.init(&db, "SELECT 1;"));
}

test "error contract: public APIs expose layered error sets" {
    try std.testing.expect(returnType(orm.Db.open) == orm.errors.DbError!orm.Db);
    try std.testing.expect(returnType(orm.Stmt.init) == orm.errors.StmtError!orm.Stmt);
    try std.testing.expect(returnType(orm.schema.createTableSqlFromMeta) == orm.errors.SchemaError![]u8);
}

test "error contract: deprecated aggregate alias remains usable" {
    const compat_exec: orm.errors.ZiteError = error.DriverExecFailed;
    const compat_null: orm.errors.ZiteError = error.UnexpectedNull;
    try std.testing.expect(compat_exec == error.DriverExecFailed);
    try std.testing.expect(compat_null == error.UnexpectedNull);
}
