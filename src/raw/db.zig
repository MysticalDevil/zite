const raw = @import("sqlite3.zig");

pub const DbHandle = raw.DbHandle;

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

pub fn close(handle: DbHandle) i32 {
    return @intCast(raw.sqlite3_close(handle.ptr));
}

pub fn closeV2(handle: DbHandle) i32 {
    return @intCast(raw.sqlite3_close_v2(handle.ptr));
}

pub fn errmsg(handle: DbHandle) ?[*:0]const u8 {
    return raw.sqlite3_errmsg(handle.ptr);
}

pub fn exec(handle: DbHandle, sql: [*]const u8) i32 {
    return @intCast(raw.sqlite3_exec(handle.ptr, sql, null, null, null));
}

pub fn lastInsertRowId(handle: DbHandle) i64 {
    return raw.sqlite3_last_insert_rowid(handle.ptr);
}

pub fn changes(handle: DbHandle) i32 {
    return @intCast(raw.sqlite3_changes(handle.ptr));
}
