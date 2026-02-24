const raw = @import("sqlite3.zig");

pub const DbHandle = raw.DbHandle;
pub const StmtHandle = raw.StmtHandle;

/// Prepares a SQL statement with sqlite3_prepare_v2.
pub fn prepare(db: DbHandle, sql: [*]const u8, n: i32, out: *?StmtHandle) i32 {
    var stmt_ptr: ?*raw.sqlite3_stmt = null;
    const rc: i32 = @intCast(raw.sqlite3_prepare_v2(db.ptr, sql, @intCast(n), &stmt_ptr, null));
    if (stmt_ptr) |s| {
        out.* = .{ .ptr = s };
    } else {
        out.* = null;
    }
    return rc;
}

/// Finalizes a prepared statement.
pub fn finalize(stmt: StmtHandle) i32 {
    return @intCast(raw.sqlite3_finalize(stmt.ptr));
}

/// Steps the prepared statement.
pub fn step(stmt: StmtHandle) i32 {
    return @intCast(raw.sqlite3_step(stmt.ptr));
}

/// Resets a prepared statement.
pub fn reset(stmt: StmtHandle) i32 {
    return @intCast(raw.sqlite3_reset(stmt.ptr));
}

/// Clears all bound parameters.
pub fn clearBindings(stmt: StmtHandle) i32 {
    return @intCast(raw.sqlite3_clear_bindings(stmt.ptr));
}

/// Binds NULL to a 1-based parameter index.
pub fn bindNull(stmt: StmtHandle, idx: i32) i32 {
    return @intCast(raw.sqlite3_bind_null(stmt.ptr, @intCast(idx)));
}

/// Binds int64 to a 1-based parameter index.
pub fn bindInt64(stmt: StmtHandle, idx: i32, value: i64) i32 {
    return @intCast(raw.sqlite3_bind_int64(stmt.ptr, @intCast(idx), value));
}

/// Binds double to a 1-based parameter index.
pub fn bindDouble(stmt: StmtHandle, idx: i32, value: f64) i32 {
    return @intCast(raw.sqlite3_bind_double(stmt.ptr, @intCast(idx), value));
}

/// Binds int to a 1-based parameter index.
pub fn bindInt(stmt: StmtHandle, idx: i32, value: i32) i32 {
    return @intCast(raw.sqlite3_bind_int(stmt.ptr, @intCast(idx), @intCast(value)));
}

/// Binds UTF-8 text to a 1-based parameter index.
pub fn bindText(stmt: StmtHandle, idx: i32, value: [*]const u8, n: i32) i32 {
    return @intCast(raw.sqlite3_bind_text(stmt.ptr, @intCast(idx), value, @intCast(n), raw.SQLITE_TRANSIENT));
}

/// Binds a blob to a 1-based parameter index.
pub fn bindBlob(stmt: StmtHandle, idx: i32, value: [*]const u8, n: i32) i32 {
    return @intCast(raw.sqlite3_bind_blob(stmt.ptr, @intCast(idx), value, @intCast(n), raw.SQLITE_TRANSIENT));
}

/// Returns the column type for a 0-based column index.
pub fn columnType(stmt: StmtHandle, col: i32) i32 {
    return @intCast(raw.sqlite3_column_type(stmt.ptr, @intCast(col)));
}

/// Returns a 32-bit integer column value.
pub fn columnInt(stmt: StmtHandle, col: i32) i32 {
    return @intCast(raw.sqlite3_column_int(stmt.ptr, @intCast(col)));
}

/// Returns a 64-bit integer column value.
pub fn columnInt64(stmt: StmtHandle, col: i32) i64 {
    return raw.sqlite3_column_int64(stmt.ptr, @intCast(col));
}

/// Returns a double column value.
pub fn columnDouble(stmt: StmtHandle, col: i32) f64 {
    return raw.sqlite3_column_double(stmt.ptr, @intCast(col));
}

/// Returns a pointer to text for a 0-based column index.
pub fn columnText(stmt: StmtHandle, col: i32) ?[*]const u8 {
    return raw.sqlite3_column_text(stmt.ptr, @intCast(col));
}

/// Returns a pointer to blob data for a 0-based column index.
pub fn columnBlob(stmt: StmtHandle, col: i32) ?*const anyopaque {
    return raw.sqlite3_column_blob(stmt.ptr, @intCast(col));
}

/// Returns size in bytes for the column value.
pub fn columnBytes(stmt: StmtHandle, col: i32) i32 {
    return @intCast(raw.sqlite3_column_bytes(stmt.ptr, @intCast(col)));
}
