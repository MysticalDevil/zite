comptime {
    _ = @import("integration_create_table.zig");
    _ = @import("integration_prepare_step.zig");
    _ = @import("integration_stmt_prepare_step.zig");
    _ = @import("integration_stmt_bindall.zig");
    _ = @import("integration_insert_update.zig");
    _ = @import("integration_stmt_column_owned.zig");
    _ = @import("integration_getbyid.zig");
}
