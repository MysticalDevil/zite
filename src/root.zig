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
/// Schema generation helpers.
pub const schema = @import("orm/schema.zig");

/// Database connection wrapper bound to a driver.
pub fn Db(comptime Driver: type) type {
    return @import("db/db.zig").Db(Driver);
}

/// Prepared statement wrapper bound to a driver.
pub fn Stmt(comptime Driver: type) type {
    return @import("db/stmt.zig").Stmt(Driver);
}

/// ORM API bound to a driver.
pub fn orm(comptime Driver: type) type {
    if (Driver != drivers.sqlite3) {
        @compileError("ORM currently supports only zite.drivers.sqlite3");
    }
    return @import("orm/orm.zig");
}

/// Experimental async pool API bound to a driver.
pub fn AsyncPool(comptime Driver: type) type {
    if (Driver != drivers.sqlite3) {
        @compileError("AsyncPool currently supports only zite.drivers.sqlite3");
    }
    return @import("async_pool.zig").AsyncPool;
}
