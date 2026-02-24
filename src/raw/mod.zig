const sqlite = @import("sqlite3.zig");

pub const sqlite3 = sqlite.sqlite3;
pub const sqlite3_stmt = sqlite.sqlite3_stmt;

pub const SQLITE_OK = sqlite.SQLITE_OK;
pub const SQLITE_ROW = sqlite.SQLITE_ROW;
pub const SQLITE_DONE = sqlite.SQLITE_DONE;
pub const SQLITE_NULL = sqlite.SQLITE_NULL;
pub const SQLITE_TRANSIENT = sqlite.SQLITE_TRANSIENT;
pub const SQLITE_BUSY = sqlite.SQLITE_BUSY;
pub const SQLITE_CONSTRAINT = sqlite.SQLITE_CONSTRAINT;
pub const SQLITE_MISUSE = sqlite.SQLITE_MISUSE;
pub const SQLITE_IOERR = sqlite.SQLITE_IOERR;
pub const SQLITE_READONLY = sqlite.SQLITE_READONLY;
pub const SQLITE_CANTOPEN = sqlite.SQLITE_CANTOPEN;
pub const SQLITE_RANGE = sqlite.SQLITE_RANGE;
pub const SQLITE_TOOBIG = sqlite.SQLITE_TOOBIG;
pub const SQLITE_NOMEM = sqlite.SQLITE_NOMEM;

pub const DbHandle = sqlite.DbHandle;
pub const StmtHandle = sqlite.StmtHandle;

pub const sqlite3_open = sqlite.sqlite3_open;
pub const sqlite3_close = sqlite.sqlite3_close;
pub const sqlite3_close_v2 = sqlite.sqlite3_close_v2;
pub const sqlite3_errmsg = sqlite.sqlite3_errmsg;
pub const sqlite3_free = sqlite.sqlite3_free;
pub const sqlite3_exec = sqlite.sqlite3_exec;
pub const sqlite3_prepare_v2 = sqlite.sqlite3_prepare_v2;
pub const sqlite3_finalize = sqlite.sqlite3_finalize;
pub const sqlite3_step = sqlite.sqlite3_step;
pub const sqlite3_reset = sqlite.sqlite3_reset;
pub const sqlite3_clear_bindings = sqlite.sqlite3_clear_bindings;
pub const sqlite3_bind_null = sqlite.sqlite3_bind_null;
pub const sqlite3_bind_int64 = sqlite.sqlite3_bind_int64;
pub const sqlite3_bind_double = sqlite.sqlite3_bind_double;
pub const sqlite3_bind_text = sqlite.sqlite3_bind_text;
pub const sqlite3_bind_blob = sqlite.sqlite3_bind_blob;
pub const sqlite3_column_type = sqlite.sqlite3_column_type;
pub const sqlite3_column_int = sqlite.sqlite3_column_int;
pub const sqlite3_column_int64 = sqlite.sqlite3_column_int64;
pub const sqlite3_column_double = sqlite.sqlite3_column_double;
pub const sqlite3_column_text = sqlite.sqlite3_column_text;
pub const sqlite3_column_bytes = sqlite.sqlite3_column_bytes;
pub const sqlite3_column_blob = sqlite.sqlite3_column_blob;
pub const sqlite3_last_insert_rowid = sqlite.sqlite3_last_insert_rowid;
pub const sqlite3_changes = sqlite.sqlite3_changes;

pub const db = @import("db.zig");
pub const stmt = @import("stmt.zig");
