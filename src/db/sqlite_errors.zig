const raw = @import("../raw/sqlite3.zig");
const errors = @import("../core/errors.zig");

pub fn mapSqliteRc(rc: c_int, fallback: errors.ZiteError) errors.ZiteError {
    return switch (rc) {
        raw.SQLITE_BUSY => error.SqliteBusy,
        raw.SQLITE_CONSTRAINT => error.SqliteConstraint,
        raw.SQLITE_MISUSE => error.SqliteMisuse,
        raw.SQLITE_IOERR => error.SqliteIo,
        raw.SQLITE_READONLY => error.SqliteReadonly,
        raw.SQLITE_CANTOPEN => error.SqliteCantOpen,
        raw.SQLITE_RANGE => error.SqliteRange,
        raw.SQLITE_TOOBIG => error.SqliteTooBig,
        raw.SQLITE_NOMEM => error.OutOfMemory,
        else => fallback,
    };
}
