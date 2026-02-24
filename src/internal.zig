/// Internal wiring for core/db/raw modules (not part of public API).
pub const raw = @import("raw/mod.zig");
/// Unified error set used across public APIs.
pub const errors = @import("core/errors.zig");

/// Database connection wrapper.
pub const Db = @import("db/db.zig").Db;
/// Prepared statement wrapper.
pub const Stmt = @import("db/stmt.zig").Stmt;
/// Statement step result enum.
pub const StepResult = @import("db/stmt.zig").StepResult;
/// Diagnostics helpers for sqlite failures/binds.
pub const diag = @import("db/diag.zig");

/// Shared core types (OwnedText/OwnedBlob/EpochMillis).
pub const types = @import("core/types.zig");
/// Struct metadata helpers.
pub const meta = @import("core/meta.zig");
/// SQL builder/utilities.
pub const sqlutil = @import("core/sqlutil.zig");
