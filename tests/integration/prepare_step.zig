const std = @import("std");
const zite = @import("zite");
const helpers = @import("helpers.zig");

const User = struct {
    id: i64,
    name: zite.types.OwnedText,
    age: ?u32,
    created_at: i64,
};

test "prepare_v2 + step: verify users table exists via sqlite_master" {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    // Step 1: memory db
    var db = try helpers.openMemoryDb(a);
    defer db.deinit();

    // Step 2: Create table (Use schema generator + exec to preform a DDL operation)
    try helpers.createTable(a, &db, User, "users");

    // Step 3: Compile the query statement using prepare_v2 (to avoid the sqlite3_exec callback)
    const q = "SELECT 1 FROM sqlite_master WHERE type='table' AND name='users' LIMIT 1;";
    const qz = try a.dupeSentinel(u8, q, 0);
    defer a.free(qz);

    var stmt_opt: ?zite.raw.StmtHandle = null;
    const rc_prep = zite.raw.stmt.prepare(db.handle, qz.ptr, -1, &stmt_opt);
    try std.testing.expectEqual(zite.raw.SQLITE_OK, rc_prep);
    const stmt = stmt_opt.?;

    defer _ = zite.raw.stmt.finalize(stmt);

    // Step 4: step: Result row found -> SQLITE_ROW
    const rc_step1 = zite.raw.stmt.step(stmt);
    try std.testing.expectEqual(zite.raw.SQLITE_ROW, rc_step1);

    // Step 5: Read column 0 (SELECT 1), should be 1
    const v = zite.raw.stmt.columnInt(stmt, 0);
    try std.testing.expectEqual(@as(i32, 1), v);

    // Step 6: Step once more -> SQLITE_DONE
    const rc_step2 = zite.raw.stmt.step(stmt);
    try std.testing.expectEqual(zite.raw.SQLITE_DONE, rc_step2);
}
