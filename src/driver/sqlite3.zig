const raw = @import("../raw/sqlite3.zig");

pub const Rc = i32;

pub const OK: Rc = @intCast(raw.SQLITE_OK);
pub const ROW: Rc = @intCast(raw.SQLITE_ROW);
pub const DONE: Rc = @intCast(raw.SQLITE_DONE);
pub const NULL: Rc = @intCast(raw.SQLITE_NULL);
pub const BUSY: Rc = @intCast(raw.SQLITE_BUSY);
pub const CONSTRAINT: Rc = @intCast(raw.SQLITE_CONSTRAINT);
pub const MISUSE: Rc = @intCast(raw.SQLITE_MISUSE);
pub const IOERR: Rc = @intCast(raw.SQLITE_IOERR);
pub const READONLY: Rc = @intCast(raw.SQLITE_READONLY);
pub const CANTOPEN: Rc = @intCast(raw.SQLITE_CANTOPEN);
pub const RANGE: Rc = @intCast(raw.SQLITE_RANGE);
pub const TOOBIG: Rc = @intCast(raw.SQLITE_TOOBIG);
pub const NOMEM: Rc = @intCast(raw.SQLITE_NOMEM);

pub const SQLITE_OK = OK;
pub const SQLITE_ROW = ROW;
pub const SQLITE_DONE = DONE;
pub const SQLITE_NULL = NULL;

pub const sqlite3 = raw.sqlite3;
pub const sqlite3_stmt = raw.sqlite3_stmt;

pub const DbHandle = raw.DbHandle;
pub const StmtHandle = raw.StmtHandle;

pub const db = struct {
    pub fn open(path_z: [*]const u8, out: *?DbHandle) Rc {
        var handle_ptr: ?*raw.sqlite3 = null;
        const rc: Rc = @intCast(raw.sqlite3_open(path_z, &handle_ptr));
        if (handle_ptr) |h| {
            out.* = .{ .ptr = h };
        } else {
            out.* = null;
        }
        return rc;
    }

    pub fn closeImmediate(handle: DbHandle) Rc {
        return @intCast(raw.sqlite3_close(handle.ptr));
    }

    pub fn closeDeferred(handle: DbHandle) Rc {
        return @intCast(raw.sqlite3_close_v2(handle.ptr));
    }

    pub fn errmsg(handle: DbHandle) ?[*:0]const u8 {
        return raw.sqlite3_errmsg(handle.ptr);
    }

    pub fn exec(handle: DbHandle, sql: [*]const u8) Rc {
        return @intCast(raw.sqlite3_exec(handle.ptr, sql, null, null, null));
    }

    pub fn lastInsertRowId(handle: DbHandle) i64 {
        return raw.sqlite3_last_insert_rowid(handle.ptr);
    }

    pub fn changes(handle: DbHandle) i32 {
        return @intCast(raw.sqlite3_changes(handle.ptr));
    }
};

pub const stmt = struct {
    pub fn prepare(db_handle: DbHandle, sql: [*]const u8, n: i32, out: *?StmtHandle) Rc {
        var stmt_ptr: ?*raw.sqlite3_stmt = null;
        const rc: Rc = @intCast(raw.sqlite3_prepare_v2(db_handle.ptr, sql, @intCast(n), &stmt_ptr, null));
        if (stmt_ptr) |s| {
            out.* = .{ .ptr = s };
        } else {
            out.* = null;
        }
        return rc;
    }

    pub fn finalize(stmt_handle: StmtHandle) Rc {
        return @intCast(raw.sqlite3_finalize(stmt_handle.ptr));
    }

    pub fn step(stmt_handle: StmtHandle) Rc {
        return @intCast(raw.sqlite3_step(stmt_handle.ptr));
    }

    pub fn reset(stmt_handle: StmtHandle) Rc {
        return @intCast(raw.sqlite3_reset(stmt_handle.ptr));
    }

    pub fn bindNull(stmt_handle: StmtHandle, idx: i32) Rc {
        return @intCast(raw.sqlite3_bind_null(stmt_handle.ptr, @intCast(idx)));
    }

    pub fn bindInt64(stmt_handle: StmtHandle, idx: i32, value: i64) Rc {
        return @intCast(raw.sqlite3_bind_int64(stmt_handle.ptr, @intCast(idx), value));
    }

    pub fn bindDouble(stmt_handle: StmtHandle, idx: i32, value: f64) Rc {
        return @intCast(raw.sqlite3_bind_double(stmt_handle.ptr, @intCast(idx), value));
    }

    pub fn bindInt(stmt_handle: StmtHandle, idx: i32, value: i32) Rc {
        return @intCast(raw.sqlite3_bind_int(stmt_handle.ptr, @intCast(idx), @intCast(value)));
    }

    pub fn bindText(stmt_handle: StmtHandle, idx: i32, value: [*]const u8, n: i32) Rc {
        return @intCast(raw.sqlite3_bind_text(stmt_handle.ptr, @intCast(idx), value, @intCast(n), raw.SQLITE_TRANSIENT));
    }

    pub fn bindTextStatic(stmt_handle: StmtHandle, idx: i32, value: [*]const u8, n: i32) Rc {
        return @intCast(raw.sqlite3_bind_text(stmt_handle.ptr, @intCast(idx), value, @intCast(n), raw.SQLITE_STATIC));
    }

    pub fn bindBlob(stmt_handle: StmtHandle, idx: i32, value: [*]const u8, n: i32) Rc {
        return @intCast(raw.sqlite3_bind_blob(stmt_handle.ptr, @intCast(idx), value, @intCast(n), raw.SQLITE_TRANSIENT));
    }

    pub fn bindBlobStatic(stmt_handle: StmtHandle, idx: i32, value: [*]const u8, n: i32) Rc {
        return @intCast(raw.sqlite3_bind_blob(stmt_handle.ptr, @intCast(idx), value, @intCast(n), raw.SQLITE_STATIC));
    }

    pub fn columnType(stmt_handle: StmtHandle, col: i32) Rc {
        return @intCast(raw.sqlite3_column_type(stmt_handle.ptr, @intCast(col)));
    }

    pub fn columnInt(stmt_handle: StmtHandle, col: i32) i32 {
        return @intCast(raw.sqlite3_column_int(stmt_handle.ptr, @intCast(col)));
    }

    pub fn columnInt64(stmt_handle: StmtHandle, col: i32) i64 {
        return raw.sqlite3_column_int64(stmt_handle.ptr, @intCast(col));
    }

    pub fn columnDouble(stmt_handle: StmtHandle, col: i32) f64 {
        return raw.sqlite3_column_double(stmt_handle.ptr, @intCast(col));
    }

    pub fn columnText(stmt_handle: StmtHandle, col: i32) ?[*]const u8 {
        return raw.sqlite3_column_text(stmt_handle.ptr, @intCast(col));
    }

    pub fn columnBlob(stmt_handle: StmtHandle, col: i32) ?*const anyopaque {
        return raw.sqlite3_column_blob(stmt_handle.ptr, @intCast(col));
    }

    pub fn columnBytes(stmt_handle: StmtHandle, col: i32) i32 {
        return @intCast(raw.sqlite3_column_bytes(stmt_handle.ptr, @intCast(col)));
    }
};
