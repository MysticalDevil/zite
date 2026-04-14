/// Direct C bindings to sqlite3 (raw FFI).
/// Hand-written extern declarations to avoid @cImport (deprecated in Zig 0.16).

pub const sqlite3 = opaque {};
pub const sqlite3_stmt = opaque {};

/// Opaque sqlite3 connection type (C).
pub const DbHandle = struct {
    /// Opaque sqlite3 pointer.
    ptr: *sqlite3,
};

/// Opaque sqlite3 statement type (C).
pub const StmtHandle = struct {
    /// Opaque sqlite3_stmt pointer.
    ptr: *sqlite3_stmt,
};

/// sqlite3_open
pub extern "sqlite3" fn sqlite3_open(filename: [*c]const u8, ppDb: *?*sqlite3) c_int;
/// sqlite3_close
pub extern "sqlite3" fn sqlite3_close(db: ?*sqlite3) c_int;
/// sqlite3_close_v2
pub extern "sqlite3" fn sqlite3_close_v2(db: ?*sqlite3) c_int;
/// sqlite3_errmsg
pub extern "sqlite3" fn sqlite3_errmsg(db: ?*sqlite3) [*:0]const u8;
/// sqlite3_free
pub extern "sqlite3" fn sqlite3_free(ptr: ?*anyopaque) void;

/// sqlite3_exec
pub extern "sqlite3" fn sqlite3_exec(
    db: ?*sqlite3,
    sql: [*c]const u8,
    callback: ?*const fn (?*anyopaque, c_int, [*c][*c]u8, [*c][*c]u8) callconv(.c) c_int,
    userdata: ?*anyopaque,
    errmsg: [*c][*c]u8,
) c_int;

/// sqlite3_prepare_v2
pub extern "sqlite3" fn sqlite3_prepare_v2(
    db: ?*sqlite3,
    zSql: [*c]const u8,
    nByte: c_int,
    ppStmt: *?*sqlite3_stmt,
    pzTail: [*c][*c]const u8,
) c_int;
/// sqlite3_finalize
pub extern "sqlite3" fn sqlite3_finalize(pStmt: ?*sqlite3_stmt) c_int;
/// sqlite3_step
pub extern "sqlite3" fn sqlite3_step(pStmt: ?*sqlite3_stmt) c_int;
/// sqlite3_reset
pub extern "sqlite3" fn sqlite3_reset(pStmt: ?*sqlite3_stmt) c_int;

/// sqlite3_bind_null
pub extern "sqlite3" fn sqlite3_bind_null(pStmt: ?*sqlite3_stmt, idx: c_int) c_int;
/// sqlite3_bind_int64
pub extern "sqlite3" fn sqlite3_bind_int64(pStmt: ?*sqlite3_stmt, idx: c_int, value: i64) c_int;
/// sqlite3_bind_int
pub extern "sqlite3" fn sqlite3_bind_int(pStmt: ?*sqlite3_stmt, idx: c_int, value: c_int) c_int;
/// sqlite3_bind_double
pub extern "sqlite3" fn sqlite3_bind_double(pStmt: ?*sqlite3_stmt, idx: c_int, value: f64) c_int;
/// sqlite3_bind_text
pub extern "sqlite3" fn sqlite3_bind_text(
    pStmt: ?*sqlite3_stmt,
    idx: c_int,
    text: [*c]const u8,
    n: c_int,
    destructor: ?*const fn (?*anyopaque) callconv(.c) void,
) c_int;
/// sqlite3_bind_blob
pub extern "sqlite3" fn sqlite3_bind_blob(
    pStmt: ?*sqlite3_stmt,
    idx: c_int,
    blob: ?*const anyopaque,
    n: c_int,
    destructor: ?*const fn (?*anyopaque) callconv(.c) void,
) c_int;

/// sqlite3_column_type
pub extern "sqlite3" fn sqlite3_column_type(pStmt: ?*sqlite3_stmt, iCol: c_int) c_int;
/// sqlite3_column_int
pub extern "sqlite3" fn sqlite3_column_int(pStmt: ?*sqlite3_stmt, iCol: c_int) c_int;
/// sqlite3_column_int64
pub extern "sqlite3" fn sqlite3_column_int64(pStmt: ?*sqlite3_stmt, iCol: c_int) i64;
/// sqlite3_column_double
pub extern "sqlite3" fn sqlite3_column_double(pStmt: ?*sqlite3_stmt, iCol: c_int) f64;
/// sqlite3_column_text
pub extern "sqlite3" fn sqlite3_column_text(pStmt: ?*sqlite3_stmt, iCol: c_int) [*:0]const u8;
/// sqlite3_column_bytes
pub extern "sqlite3" fn sqlite3_column_bytes(pStmt: ?*sqlite3_stmt, iCol: c_int) c_int;
/// sqlite3_column_blob
pub extern "sqlite3" fn sqlite3_column_blob(pStmt: ?*sqlite3_stmt, iCol: c_int) ?*const anyopaque;

/// sqlite3_last_insert_rowid
pub extern "sqlite3" fn sqlite3_last_insert_rowid(db: ?*sqlite3) i64;
/// sqlite3_changes
pub extern "sqlite3" fn sqlite3_changes(db: ?*sqlite3) c_int;

/// SQLITE_OK
pub const SQLITE_OK: c_int = 0;
/// SQLITE_ROW
pub const SQLITE_ROW: c_int = 100;
/// SQLITE_DONE
pub const SQLITE_DONE: c_int = 101;
/// SQLITE_NULL
pub const SQLITE_NULL: c_int = 5;
/// SQLITE_TRANSIENT
pub const SQLITE_TRANSIENT = @as(?*const fn (?*anyopaque) callconv(.c) void, @ptrFromInt(~@as(usize, 0)));
/// SQLITE_BUSY
pub const SQLITE_BUSY: c_int = 5;
/// SQLITE_CONSTRAINT
pub const SQLITE_CONSTRAINT: c_int = 19;
/// SQLITE_MISUSE
pub const SQLITE_MISUSE: c_int = 21;
/// SQLITE_IOERR
pub const SQLITE_IOERR: c_int = 10;
/// SQLITE_READONLY
pub const SQLITE_READONLY: c_int = 8;
/// SQLITE_CANTOPEN
pub const SQLITE_CANTOPEN: c_int = 14;
/// SQLITE_RANGE
pub const SQLITE_RANGE: c_int = 25;
/// SQLITE_TOOBIG
pub const SQLITE_TOOBIG: c_int = 18;
/// SQLITE_NOMEM
pub const SQLITE_NOMEM: c_int = 7;
