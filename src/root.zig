/// Advanced API: raw sqlite bindings and thin wrappers (db/stmt).
pub const raw = @import("raw/mod.zig");
/// Unified error set for this library.
pub const errors = @import("core/errors.zig");
/// Database connection wrapper.
pub const Db = @import("db/db.zig").Db;
/// Prepared statement wrapper.
pub const Stmt = @import("db/stmt.zig").Stmt;
/// Statement step result enum.
pub const StepResult = @import("db/stmt.zig").StepResult;
/// Diagnostics helpers.
pub const diag = @import("db/diag.zig");

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
