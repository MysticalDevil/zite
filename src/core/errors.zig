pub const ZiteError = error{
    OutOfMemory,

    SqliteError,
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
