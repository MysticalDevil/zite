const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const sqlite3 = c.sqlite3;
pub const sqlite3_stmt = c.sqlite3_stmt;

pub const sqlite3_open = c.sqlite3_open;
pub const sqlite3_close = c.sqlite3_close;
pub const sqlite3_errmsg = c.sqlite3_errmsg;
pub const sqlite3_free = c.sqlite3_free;

pub const sqlite3_exec = c.sqlite3_exec;

pub const sqlite3_prepare_v2 = c.sqlite3_prepare_v2;
pub const sqlite3_finalize = c.sqlite3_finalize;
pub const sqlite3_step = c.sqlite3_step;
pub const sqlite3_reset = c.sqlite3_reset;
pub const sqlite3_clear_bindings = c.sqlite3_clear_bindings;

pub const sqlite3_bind_null = c.sqlite3_bind_null;
pub const sqlite3_bind_int64 = c.sqlite3_bind_int64;
pub const sqlite3_bind_double = c.sqlite3_bind_double;
pub const sqlite3_bind_text = c.sqlite3_bind_text;
pub const sqlite3_bind_blob = c.sqlite3_bind_blob;

pub const sqlite3_column_type = c.sqlite3_column_type;
pub const sqlite3_column_int = c.sqlite3_column_int;
pub const sqlite3_column_int64 = c.sqlite3_column_int64;
pub const sqlite3_column_double = c.sqlite3_column_double;
pub const sqlite3_column_text = c.sqlite3_column_text;
pub const sqlite3_column_bytes = c.sqlite3_column_bytes;
pub const sqlite3_column_blob = c.sqlite3_column_blob;

pub const sqlite3_last_insert_rowid = c.sqlite3_last_insert_rowid;
pub const sqlite3_changes = c.sqlite3_changes;

pub const SQLITE_OK = c.SQLITE_OK;
pub const SQLITE_ROW = c.SQLITE_ROW;
pub const SQLITE_DONE = c.SQLITE_DONE;
pub const SQLITE_NULL = c.SQLITE_NULL;
pub const SQLITE_TRANSIENT = c.SQLITE_TRANSIENT;
