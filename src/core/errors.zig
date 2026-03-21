/// Shared allocation failures used across all layers.
pub const AllocError = error{
    /// Allocator failed to allocate memory.
    OutOfMemory,
};

/// SQLite result codes normalized into stable library error names.
pub const SqliteMappedError = error{
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
};

/// Database connection lifecycle and execution errors.
pub const DbError = AllocError || SqliteMappedError || error{
    /// sqlite3_open failed.
    SqliteOpenFailed,
    /// sqlite3_exec failed.
    SqliteExecFailed,
    /// Statement bookkeeping underflowed (double-finalize or mismatched lifecycle).
    StatementCountUnderflow,
};

/// Prepared statement lifecycle, bind, and execution errors.
pub const StmtError = DbError || error{
    /// sqlite3_prepare_v2 failed.
    SqlitePrepareFailed,
    /// sqlite3_reset failed.
    SqliteResetFailed,
    /// sqlite3_step failed.
    SqliteStepFailed,
    /// sqlite3_finalize failed.
    SqliteFinalizeFailed,
    /// sqlite3_bind_* failed.
    SqliteBindFailed,
    /// Unsupported type passed to bindOne.
    UnsupportedBindType,
    /// Borrowed row/view accessed after its statement was finalized.
    StatementFinalized,
    /// bindAll expects a struct/tuple.
    BindAllExpectedStructOrTuple,
};

/// Row decoding and borrowed row validity errors.
pub const RowReadError = StmtError || error{
    /// Unsupported field type for column reads.
    UnsupportedColumnType,
    /// Column type did not match expected type.
    UnexpectedColumnType,
    /// Column was NULL when a non-optional value was required.
    UnexpectedNull,
    /// Borrowed row/view accessed after iterator advanced to another row.
    BorrowedRowStale,
};

/// ORM and query builder invariants layered on top of statement and row errors.
pub const OrmError = RowReadError || error{
    /// WHERE clause must not be empty for destructive operations.
    EmptyWhereClause,
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

/// Async execution capability and worker propagation errors.
pub const AsyncError = error{
    /// Async/concurrent execution is unavailable in the selected Io implementation.
    ConcurrencyUnavailable,
};

/// Async ORM operations add concurrency availability on top of ORM failures.
pub const AsyncOrmError = AsyncError || OrmError;

/// SQL text generation only allocates and validates ORM query invariants.
pub const SqlBuildError = AllocError || error{
    /// WHERE clause must not be empty for destructive operations.
    EmptyWhereClause,
};

/// CREATE TABLE generation only allocates.
pub const SchemaError = AllocError;

/// Deprecated aggregate kept for migration compatibility.
pub const ZiteError = DbError || StmtError || RowReadError || OrmError || AsyncError;
