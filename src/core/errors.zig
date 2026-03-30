/// Shared allocation failures used across all layers.
pub const AllocError = error{
    /// Allocator failed to allocate memory.
    OutOfMemory,
};

/// Driver result codes normalized into stable library error names.
pub const DriverMappedError = error{
    /// Generic driver error not mapped to a more specific code.
    DriverError,
    /// Database is busy/locked.
    DriverBusy,
    /// Constraint violation (e.g., UNIQUE).
    DriverConstraint,
    /// Driver API misuse.
    DriverMisuse,
    /// I/O error during driver operation.
    DriverIo,
    /// Attempted write to readonly database.
    DriverReadonly,
    /// Failed to open database.
    DriverCantOpen,
    /// Parameter/column index out of range.
    DriverRange,
    /// Operation exceeds backend limits.
    DriverTooBig,
};

/// Database connection lifecycle and execution errors.
pub const DbError = AllocError || DriverMappedError || error{
    /// Driver open failed.
    DriverOpenFailed,
    /// Driver exec failed.
    DriverExecFailed,
    /// Statement bookkeeping underflowed (double-finalize or mismatched lifecycle).
    StatementCountUnderflow,
};

/// Prepared statement lifecycle, bind, and execution errors.
pub const StmtError = DbError || error{
    /// Driver prepare failed.
    DriverPrepareFailed,
    /// Driver reset failed.
    DriverResetFailed,
    /// Driver step failed.
    DriverStepFailed,
    /// Driver finalize failed.
    DriverFinalizeFailed,
    /// Driver bind failed.
    DriverBindFailed,
    /// Unsupported type passed to bindOne.
    UnsupportedBindType,
    /// Row-backed handle or view accessed after its statement was finalized.
    StatementFinalized,
    /// bindAll expects a struct/tuple.
    BindAllExpectedStructOrTuple,
};

/// Row decoding and row-view lifetime errors.
pub const RowReadError = StmtError || error{
    /// Unsupported field type for column reads.
    UnsupportedColumnType,
    /// Column type did not match expected type.
    UnexpectedColumnType,
    /// Column was NULL when a non-optional value was required.
    UnexpectedNull,
    /// Row view accessed after the cursor advanced to another row.
    RowViewStale,
};

/// ORM and query builder invariants layered on top of statement and row errors.
pub const OrmError = RowReadError || error{
    /// WHERE clause must not be empty for destructive operations.
    EmptyWhereClause,
    /// Raw SQL fragment contains unsafe constructs for guarded raw APIs.
    UnsafeSqlFragment,
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
