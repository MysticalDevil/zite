const raw = @import("sqlite3.zig");

pub const DbHandle = raw.DbHandle;

pub fn open(path_z: [*]const u8, out: *?DbHandle) c_int {
    var handle_ptr: ?*raw.sqlite3 = null;
    const rc = raw.sqlite3_open(path_z, &handle_ptr);
    if (handle_ptr) |h| {
        out.* = .{ .ptr = h };
    } else {
        out.* = null;
    }
    return rc;
}

pub fn close(handle: DbHandle) c_int {
    return raw.sqlite3_close(handle.ptr);
}

pub fn closeV2(handle: DbHandle) c_int {
    return raw.sqlite3_close_v2(handle.ptr);
}

pub fn errmsg(handle: DbHandle) ?[*:0]const u8 {
    return raw.sqlite3_errmsg(handle.ptr);
}

pub fn exec(handle: DbHandle, sql: [*]const u8) c_int {
    return raw.sqlite3_exec(handle.ptr, sql, null, null, null);
}

pub fn lastInsertRowId(handle: DbHandle) i64 {
    return raw.sqlite3_last_insert_rowid(handle.ptr);
}

pub fn changes(handle: DbHandle) c_int {
    return raw.sqlite3_changes(handle.ptr);
}
