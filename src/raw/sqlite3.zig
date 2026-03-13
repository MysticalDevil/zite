/// Direct C bindings to sqlite3.h (raw FFI).
const c = @cImport({
    @cInclude("sqlite3.h");
});

/// Opaque sqlite3 connection type (C).
pub const sqlite3 = c.sqlite3;
/// Opaque sqlite3 statement type (C).
pub const sqlite3_stmt = c.sqlite3_stmt;

/// Typed wrapper for sqlite3*.
pub const DbHandle = struct {
    /// Opaque sqlite3 pointer.
    ptr: *sqlite3,
};

/// Typed wrapper for sqlite3_stmt*.
pub const StmtHandle = struct {
    /// Opaque sqlite3_stmt pointer.
    ptr: *sqlite3_stmt,
};

/// sqlite3_open
pub const sqlite3_open = c.sqlite3_open;
/// sqlite3_close
pub const sqlite3_close = c.sqlite3_close;
/// sqlite3_close_v2
pub const sqlite3_close_v2 = c.sqlite3_close_v2;
/// sqlite3_errmsg
pub const sqlite3_errmsg = c.sqlite3_errmsg;
/// sqlite3_free
pub const sqlite3_free = c.sqlite3_free;

/// sqlite3_exec
pub const sqlite3_exec = c.sqlite3_exec;

/// sqlite3_prepare_v2
pub const sqlite3_prepare_v2 = c.sqlite3_prepare_v2;
/// sqlite3_finalize
pub const sqlite3_finalize = c.sqlite3_finalize;
/// sqlite3_step
pub const sqlite3_step = c.sqlite3_step;
/// sqlite3_reset
pub const sqlite3_reset = c.sqlite3_reset;
/// sqlite3_bind_null
pub const sqlite3_bind_null = c.sqlite3_bind_null;
/// sqlite3_bind_int64
pub const sqlite3_bind_int64 = c.sqlite3_bind_int64;
/// sqlite3_bind_int
pub const sqlite3_bind_int = c.sqlite3_bind_int;
/// sqlite3_bind_double
pub const sqlite3_bind_double = c.sqlite3_bind_double;
/// sqlite3_bind_text
pub const sqlite3_bind_text = c.sqlite3_bind_text;
/// sqlite3_bind_blob
pub const sqlite3_bind_blob = c.sqlite3_bind_blob;

/// sqlite3_column_type
pub const sqlite3_column_type = c.sqlite3_column_type;
/// sqlite3_column_int
pub const sqlite3_column_int = c.sqlite3_column_int;
/// sqlite3_column_int64
pub const sqlite3_column_int64 = c.sqlite3_column_int64;
/// sqlite3_column_double
pub const sqlite3_column_double = c.sqlite3_column_double;
/// sqlite3_column_text
pub const sqlite3_column_text = c.sqlite3_column_text;
/// sqlite3_column_bytes
pub const sqlite3_column_bytes = c.sqlite3_column_bytes;
/// sqlite3_column_blob
pub const sqlite3_column_blob = c.sqlite3_column_blob;

/// sqlite3_last_insert_rowid
pub const sqlite3_last_insert_rowid = c.sqlite3_last_insert_rowid;
/// sqlite3_changes
pub const sqlite3_changes = c.sqlite3_changes;

/// SQLITE_OK
pub const SQLITE_OK = c.SQLITE_OK;
/// SQLITE_ROW
pub const SQLITE_ROW = c.SQLITE_ROW;
/// SQLITE_DONE
pub const SQLITE_DONE = c.SQLITE_DONE;
/// SQLITE_NULL
pub const SQLITE_NULL = c.SQLITE_NULL;
/// SQLITE_TRANSIENT
pub const SQLITE_TRANSIENT = c.SQLITE_TRANSIENT;
/// SQLITE_BUSY
pub const SQLITE_BUSY = c.SQLITE_BUSY;
/// SQLITE_CONSTRAINT
pub const SQLITE_CONSTRAINT = c.SQLITE_CONSTRAINT;
/// SQLITE_MISUSE
pub const SQLITE_MISUSE = c.SQLITE_MISUSE;
/// SQLITE_IOERR
pub const SQLITE_IOERR = c.SQLITE_IOERR;
/// SQLITE_READONLY
pub const SQLITE_READONLY = c.SQLITE_READONLY;
/// SQLITE_CANTOPEN
pub const SQLITE_CANTOPEN = c.SQLITE_CANTOPEN;
/// SQLITE_RANGE
pub const SQLITE_RANGE = c.SQLITE_RANGE;
/// SQLITE_TOOBIG
pub const SQLITE_TOOBIG = c.SQLITE_TOOBIG;
/// SQLITE_NOMEM
pub const SQLITE_NOMEM = c.SQLITE_NOMEM;
