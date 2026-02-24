/// Unified error set returned by public APIs.
pub const ZiteError = error{
    OutOfMemory,

    SqliteError,
    SqliteBusy,
    SqliteConstraint,
    SqliteMisuse,
    SqliteIo,
    SqliteReadonly,
    SqliteCantOpen,
    SqliteRange,
    SqliteTooBig,
    SqliteOpenFailed,
    SqliteExecFailed,
    SqlitePrepareFailed,
    SqliteResetFailed,
    SqliteClearBindingsFailed,
    SqliteStepFailed,
    SqliteBindFailed,

    UnsupportedBindType,
    UnsupportedColumnType,
    UnexpectedColumnType,
    UnexpectedNull,
    BindAllExpecteStructOrTuple,

    NoInsertableFields,
    NoUpdatableFields,
    UnexpectedRowOnInsert,
    UnexpectedRowOnUpdate,
    UnexpectedExtraRows,
};
