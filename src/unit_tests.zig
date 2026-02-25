test "core unit tests" {
    _ = @import("core/types.zig");
    _ = @import("core/meta.zig");
    _ = @import("core/sqlutil.zig");
    _ = @import("db/db.zig");
    _ = @import("db/stmt.zig");
}
