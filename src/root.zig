const std = @import("std");

/// Available database drivers.
pub const drivers = @import("driver/root.zig");
/// Driver selected by build option (`-Dsqlite_backend=system|pure`).
pub const DefaultDriver = drivers.default;
/// Layered error sets for this library.
pub const errors = @import("core/errors.zig");
/// Statement step result enum.
pub const StepResult = @import("db/stmt.zig").StepResult;
/// Diagnostics helpers.
pub const diag = @import("db/diag.zig");
/// Core types such as OwnedText/OwnedBlob/EpochMillis.
pub const types = @import("core/types.zig");
/// Advanced API: struct metadata helpers.
pub const meta = @import("core/meta.zig");
/// Advanced API: SQL builder/utilities.
pub const sqlutil = @import("core/sqlutil.zig");

/// Re-export the sqlite3 driver for low-level access.
pub const raw = drivers.sqlite3;

/// Transaction mode alias.
pub const TxMode = Db(drivers.sqlite3).TxMode;
/// Transaction handle alias.
pub const Tx = Db(drivers.sqlite3).Tx;

// ========== ORM subsystem ==========

/// ORM subsystem entry point.
pub const orm = @import("orm/root.zig");

// Root-level aliases for backward compatibility and convenience.
pub const schema = orm.schema;
pub const UpsertResult = orm.UpsertResult;
pub const FindManyOptions = orm.FindManyOptions;
pub const OrderDir = orm.OrderDir;
pub const QueryParam = orm.QueryParam;
pub const Repository = orm.Repository;
pub const repository = orm.repository;
pub const Query = orm.Query;
pub const RowView = orm.RowView;
pub const RowHandle = orm.RowHandle;
pub const RowCursor = orm.RowCursor;
pub const OwnedRow = orm.OwnedRow;
pub const OwnedRows = orm.OwnedRows;
pub const Rows = orm.Rows;
pub const freeOwnedRow = orm.freeOwnedRow;
pub const ViewFieldType = orm.ViewFieldType;
pub const appendRebasedWhereSql = orm.appendRebasedWhereSql;
pub const toQueryParam = orm.toQueryParam;
pub const bindQueryParam = orm.bindQueryParam;
pub const validateWhereRawFragment = orm.validateWhereRawFragment;
pub const validateOrderByRawFragment = orm.validateOrderByRawFragment;

// ========== Core generics ==========

/// Database connection wrapper bound to a driver.
pub fn Db(comptime Driver: type) type {
    return @import("db/db.zig").Db(Driver);
}

/// Prepared statement wrapper bound to a driver.
pub fn Stmt(comptime Driver: type) type {
    return @import("db/stmt.zig").Stmt(Driver);
}

/// Experimental async pool API bound to a driver.
pub fn AsyncPool(comptime Driver: type) type {
    if (Driver != drivers.sqlite3) {
        @compileError("AsyncPool currently supports only zite.drivers.sqlite3");
    }
    return @import("async_pool.zig").AsyncPool;
}
