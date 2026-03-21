/// Advanced API: raw sqlite bindings and thin wrappers (db/stmt).
pub const raw = @import("raw/mod.zig");
/// Layered error sets for this library.
pub const errors = @import("core/errors.zig");
/// Database connection wrapper.
pub const Db = @import("db/db.zig").Db;
/// Transaction mode enum for Db.beginTx().
pub const TxMode = Db.TxMode;
/// Transaction handle returned by Db.beginTx().
pub const Tx = Db.Tx;
/// Prepared statement wrapper.
pub const Stmt = @import("db/stmt.zig").Stmt;
/// Statement step result enum.
pub const StepResult = @import("db/stmt.zig").StepResult;
/// Diagnostics helpers.
pub const diag = @import("db/diag.zig");
/// Experimental async execution layer built on Zig 0.16 `std.Io`.
pub const async_pool = @import("async_pool.zig");
/// Experimental async pool handle.
pub const AsyncPool = async_pool.AsyncPool;

/// ORM repository/query API.
pub const orm = @import("orm/orm.zig");
/// Core types such as OwnedText/OwnedBlob/EpochMillis.
pub const types = @import("core/types.zig");
/// Advanced API: struct metadata helpers.
pub const meta = @import("core/meta.zig");
/// Advanced API: SQL builder/utilities.
pub const sqlutil = @import("core/sqlutil.zig");
/// Schema generation helpers.
pub const schema = @import("orm/schema.zig");

/// OwnedRow wrapper for ORM allocations.
pub const OwnedRow = orm.OwnedRow;
/// Owned rows iterator wrapper for ORM allocations.
pub const OwnedRows = orm.OwnedRows;
