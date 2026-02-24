const sqlite = @import("sqlite3.zig");

/// SQLite return code type used by raw helpers.
pub const Rc = i32;

/// sqlite3 result code: success.
pub const SQLITE_OK: Rc = @intCast(sqlite.SQLITE_OK);
/// sqlite3 result code: row available.
pub const SQLITE_ROW: Rc = @intCast(sqlite.SQLITE_ROW);
/// sqlite3 result code: completion.
pub const SQLITE_DONE: Rc = @intCast(sqlite.SQLITE_DONE);
/// sqlite3 result code: NULL value.
pub const SQLITE_NULL: Rc = @intCast(sqlite.SQLITE_NULL);
/// sqlite3 destructor hint used for bind_text/blob.
pub const SQLITE_TRANSIENT = sqlite.SQLITE_TRANSIENT;
/// sqlite3 result code: database busy/locked.
pub const SQLITE_BUSY: Rc = @intCast(sqlite.SQLITE_BUSY);
/// sqlite3 result code: constraint violation.
pub const SQLITE_CONSTRAINT: Rc = @intCast(sqlite.SQLITE_CONSTRAINT);
/// sqlite3 result code: misuse of API.
pub const SQLITE_MISUSE: Rc = @intCast(sqlite.SQLITE_MISUSE);
/// sqlite3 result code: I/O error.
pub const SQLITE_IOERR: Rc = @intCast(sqlite.SQLITE_IOERR);
/// sqlite3 result code: readonly database.
pub const SQLITE_READONLY: Rc = @intCast(sqlite.SQLITE_READONLY);
/// sqlite3 result code: cannot open database.
pub const SQLITE_CANTOPEN: Rc = @intCast(sqlite.SQLITE_CANTOPEN);
/// sqlite3 result code: out-of-range parameter/index.
pub const SQLITE_RANGE: Rc = @intCast(sqlite.SQLITE_RANGE);
/// sqlite3 result code: too large.
pub const SQLITE_TOOBIG: Rc = @intCast(sqlite.SQLITE_TOOBIG);
/// sqlite3 result code: out-of-memory.
pub const SQLITE_NOMEM: Rc = @intCast(sqlite.SQLITE_NOMEM);

/// Typed sqlite3 handle.
pub const DbHandle = sqlite.DbHandle;
/// Typed sqlite3_stmt handle.
pub const StmtHandle = sqlite.StmtHandle;

/// Low-level DB helpers; avoid direct C API usage outside raw/.
pub const db = @import("db.zig");
/// Low-level statement helpers; avoid direct C API usage outside raw/.
pub const stmt = @import("stmt.zig");
