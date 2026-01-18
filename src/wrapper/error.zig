const raw = @import("../raw/sqlite3.zig");

pub fn rcToError(rc: c_int) anyerror {
    _ = rc;
    return error.SqliteError;
}

pub fn ensureOk(rc: c_int) !void {
    if (rc == raw.SQLITE_OK) return;
    return rcToError(rc);
}
