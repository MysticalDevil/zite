const raw = @import("sqlite3.zig");

pub const DbHandle = raw.DbHandle;
pub const StmtHandle = raw.StmtHandle;

pub fn prepareV2(db: DbHandle, sql: [*]const u8, n: c_int, out: *?StmtHandle) c_int {
    var stmt_ptr: ?*raw.sqlite3_stmt = null;
    const rc = raw.sqlite3_prepare_v2(db.ptr, sql, n, &stmt_ptr, null);
    if (stmt_ptr) |s| {
        out.* = .{ .ptr = s };
    } else {
        out.* = null;
    }
    return rc;
}

pub fn finalize(stmt: StmtHandle) c_int {
    return raw.sqlite3_finalize(stmt.ptr);
}

pub fn step(stmt: StmtHandle) c_int {
    return raw.sqlite3_step(stmt.ptr);
}

pub fn reset(stmt: StmtHandle) c_int {
    return raw.sqlite3_reset(stmt.ptr);
}

pub fn clearBindings(stmt: StmtHandle) c_int {
    return raw.sqlite3_clear_bindings(stmt.ptr);
}

pub fn bindNull(stmt: StmtHandle, idx: c_int) c_int {
    return raw.sqlite3_bind_null(stmt.ptr, idx);
}

pub fn bindInt64(stmt: StmtHandle, idx: c_int, value: i64) c_int {
    return raw.sqlite3_bind_int64(stmt.ptr, idx, value);
}

pub fn bindDouble(stmt: StmtHandle, idx: c_int, value: f64) c_int {
    return raw.sqlite3_bind_double(stmt.ptr, idx, value);
}

pub fn bindInt(stmt: StmtHandle, idx: c_int, value: c_int) c_int {
    return raw.sqlite3_bind_int(stmt.ptr, idx, value);
}

pub fn bindText(stmt: StmtHandle, idx: c_int, value: [*]const u8, n: c_int) c_int {
    return raw.sqlite3_bind_text(stmt.ptr, idx, value, n, raw.SQLITE_TRANSIENT);
}

pub fn bindBlob(stmt: StmtHandle, idx: c_int, value: [*]const u8, n: c_int) c_int {
    return raw.sqlite3_bind_blob(stmt.ptr, idx, value, n, raw.SQLITE_TRANSIENT);
}

pub fn columnType(stmt: StmtHandle, col: c_int) c_int {
    return raw.sqlite3_column_type(stmt.ptr, col);
}

pub fn columnInt(stmt: StmtHandle, col: c_int) c_int {
    return raw.sqlite3_column_int(stmt.ptr, col);
}

pub fn columnInt64(stmt: StmtHandle, col: c_int) i64 {
    return raw.sqlite3_column_int64(stmt.ptr, col);
}

pub fn columnDouble(stmt: StmtHandle, col: c_int) f64 {
    return raw.sqlite3_column_double(stmt.ptr, col);
}

pub fn columnText(stmt: StmtHandle, col: c_int) ?[*]const u8 {
    return raw.sqlite3_column_text(stmt.ptr, col);
}

pub fn columnBlob(stmt: StmtHandle, col: c_int) ?*const anyopaque {
    return raw.sqlite3_column_blob(stmt.ptr, col);
}

pub fn columnBytes(stmt: StmtHandle, col: c_int) c_int {
    return raw.sqlite3_column_bytes(stmt.ptr, col);
}
