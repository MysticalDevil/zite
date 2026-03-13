/// Unified error set returned by public APIs.
pub const ZiteError = error{
    /// Allocator failed to allocate memory.
    OutOfMemory,

    /// Generic sqlite error not mapped to a more specific code.
    SqliteError,
    /// Database is busy/locked.
    SqliteBusy,
    /// Constraint violation (e.g., UNIQUE).
    SqliteConstraint,
    /// SQLite API misuse.
    SqliteMisuse,
    /// I/O error during sqlite operation.
    SqliteIo,
    /// Attempted write to readonly database.
    SqliteReadonly,
    /// Failed to open database.
    SqliteCantOpen,
    /// Parameter/column index out of range.
    SqliteRange,
    /// Operation exceeds SQLite limits.
    SqliteTooBig,
    /// sqlite3_open failed.
    SqliteOpenFailed,
    /// sqlite3_exec failed.
    SqliteExecFailed,
    /// sqlite3_prepare_v2 failed.
    SqlitePrepareFailed,
    /// sqlite3_reset failed.
    SqliteResetFailed,
    /// sqlite3_step failed.
    SqliteStepFailed,
    /// sqlite3_bind_* failed.
    SqliteBindFailed,

    /// Unsupported type passed to bindOne.
    UnsupportedBindType,
    /// Unsupported field type for column reads.
    UnsupportedColumnType,
    /// Column type did not match expected type.
    UnexpectedColumnType,
    /// Column was NULL when a non-optional value was required.
    UnexpectedNull,
    /// bindAll expects a struct/tuple.
    BindAllExpectedStructOrTuple,

    /// No insertable fields found for INSERT.
    NoInsertableFields,
    /// No updatable fields found for UPDATE.
    NoUpdatableFields,
    /// INSERT returned a row unexpectedly.
    UnexpectedRowOnInsert,
    /// UPDATE returned a row unexpectedly.
    UnexpectedRowOnUpdate,
    /// DELETE returned a row unexpectedly.
    UnexpectedRowOnDelete,
    /// More rows than expected (LIMIT 1) were returned.
    UnexpectedExtraRows,
};
