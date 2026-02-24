const sqlite = @import("sqlite3.zig");

pub const Rc = i32;

pub const SQLITE_OK: Rc = @intCast(sqlite.SQLITE_OK);
pub const SQLITE_ROW: Rc = @intCast(sqlite.SQLITE_ROW);
pub const SQLITE_DONE: Rc = @intCast(sqlite.SQLITE_DONE);
pub const SQLITE_NULL: Rc = @intCast(sqlite.SQLITE_NULL);
pub const SQLITE_TRANSIENT = sqlite.SQLITE_TRANSIENT;
pub const SQLITE_BUSY: Rc = @intCast(sqlite.SQLITE_BUSY);
pub const SQLITE_CONSTRAINT: Rc = @intCast(sqlite.SQLITE_CONSTRAINT);
pub const SQLITE_MISUSE: Rc = @intCast(sqlite.SQLITE_MISUSE);
pub const SQLITE_IOERR: Rc = @intCast(sqlite.SQLITE_IOERR);
pub const SQLITE_READONLY: Rc = @intCast(sqlite.SQLITE_READONLY);
pub const SQLITE_CANTOPEN: Rc = @intCast(sqlite.SQLITE_CANTOPEN);
pub const SQLITE_RANGE: Rc = @intCast(sqlite.SQLITE_RANGE);
pub const SQLITE_TOOBIG: Rc = @intCast(sqlite.SQLITE_TOOBIG);
pub const SQLITE_NOMEM: Rc = @intCast(sqlite.SQLITE_NOMEM);

pub const DbHandle = sqlite.DbHandle;
pub const StmtHandle = sqlite.StmtHandle;

pub const db = @import("db.zig");
pub const stmt = @import("stmt.zig");
