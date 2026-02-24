const internal = @import("internal.zig");

/// Raw sqlite bindings and thin wrappers (db/stmt).
pub const raw = internal.raw;
/// Unified error set for this library.
pub const errors = internal.errors;
/// Database connection wrapper.
pub const Db = internal.Db;
/// Prepared statement wrapper.
pub const Stmt = internal.Stmt;
/// Statement step result enum.
pub const StepResult = internal.StepResult;
/// Diagnostics helpers.
pub const diag = internal.diag;

/// ORM mapper utilities (insert/update/find...).
pub const mapper = @import("orm/mapper.zig");
/// Core types such as OwnedText/OwnedBlob/EpochMillis.
pub const types = internal.types;
/// Struct metadata helpers.
pub const meta = internal.meta;
/// SQL builder/utilities.
pub const sqlutil = internal.sqlutil;
/// Schema generation helpers.
pub const schema = @import("orm/schema.zig");

/// OwnedRow wrapper for mapper allocations.
pub const OwnedRow = mapper.OwnedRow;
