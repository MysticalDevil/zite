const std = @import("std");
const raw = @import("../raw/mod.zig");
const errors = @import("../core/errors.zig");

/// Maps SQLite return codes to more specific ZiteError values.
pub fn mapSqliteRc(rc: i32, fallback: errors.ZiteError) errors.ZiteError {
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

test "sqlite_errors: map known codes and fallback" {
    try std.testing.expectEqual(error.SqliteBusy, mapSqliteRc(raw.SQLITE_BUSY, error.SqliteError));
    try std.testing.expectEqual(error.SqliteConstraint, mapSqliteRc(raw.SQLITE_CONSTRAINT, error.SqliteError));
    try std.testing.expectEqual(error.SqliteMisuse, mapSqliteRc(raw.SQLITE_MISUSE, error.SqliteError));
    try std.testing.expectEqual(error.SqliteIo, mapSqliteRc(raw.SQLITE_IOERR, error.SqliteError));
    try std.testing.expectEqual(error.SqliteReadonly, mapSqliteRc(raw.SQLITE_READONLY, error.SqliteError));
    try std.testing.expectEqual(error.SqliteCantOpen, mapSqliteRc(raw.SQLITE_CANTOPEN, error.SqliteError));
    try std.testing.expectEqual(error.SqliteRange, mapSqliteRc(raw.SQLITE_RANGE, error.SqliteError));
    try std.testing.expectEqual(error.SqliteTooBig, mapSqliteRc(raw.SQLITE_TOOBIG, error.SqliteError));
    try std.testing.expectEqual(error.OutOfMemory, mapSqliteRc(raw.SQLITE_NOMEM, error.SqliteError));
    try std.testing.expectEqual(error.SqliteError, mapSqliteRc(raw.SQLITE_OK, error.SqliteError));
}
