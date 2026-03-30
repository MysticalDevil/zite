test "core unit tests" {
    _ = @import("core/types.zig");
    _ = @import("core/meta.zig");
    _ = @import("core/sqlutil.zig");
    _ = @import("db/db.zig");
    _ = @import("db/stmt.zig");
    _ = @import("db/driver_errors.zig");
    _ = @import("async_pool.zig");
    _ = @import("orm/mapper.zig");
}
