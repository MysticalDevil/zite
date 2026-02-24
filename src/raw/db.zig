const raw = @import("sqlite3.zig");

pub const DbHandle = raw.DbHandle;

/// Opens a sqlite database handle from a zero-terminated path.
pub fn open(path_z: [*]const u8, out: *?DbHandle) i32 {
    var handle_ptr: ?*raw.sqlite3 = null;
    const rc: i32 = @intCast(raw.sqlite3_open(path_z, &handle_ptr));
    if (handle_ptr) |h| {
        out.* = .{ .ptr = h };
    } else {
        out.* = null;
    }
    return rc;
}

/// Closes the database handle (immediate close).
pub fn closeImmediate(handle: DbHandle) i32 {
    return @intCast(raw.sqlite3_close(handle.ptr));
}

/// Closes the database handle (deferred close).
pub fn closeDeferred(handle: DbHandle) i32 {
    return @intCast(raw.sqlite3_close_v2(handle.ptr));
}

/// Returns the last error message for the database handle.
pub fn errmsg(handle: DbHandle) ?[*:0]const u8 {
    return raw.sqlite3_errmsg(handle.ptr);
}

/// Executes a SQL statement (no rows).
pub fn exec(handle: DbHandle, sql: [*]const u8) i32 {
    return @intCast(raw.sqlite3_exec(handle.ptr, sql, null, null, null));
}

/// Returns the last insert rowid.
pub fn lastInsertRowId(handle: DbHandle) i64 {
    return raw.sqlite3_last_insert_rowid(handle.ptr);
}

/// Returns number of rows changed by last operation.
pub fn changes(handle: DbHandle) i32 {
    return @intCast(raw.sqlite3_changes(handle.ptr));
}
