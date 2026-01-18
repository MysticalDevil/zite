const std = @import("std");

pub const std_options: std.Options = .{
    .log_level = .err,
};

comptime {
    _ = @import("integration_create_table.zig");
    _ = @import("integration_prepare_step.zig");
    _ = @import("integration_stmt_prepare_step.zig");
    _ = @import("integration_stmt_bindall.zig");
    _ = @import("integration_insert_update.zig");
    _ = @import("integration_stmt_column_owned.zig");
    _ = @import("integration_getbyid.zig");
    _ = @import("integration_findone.zig");
    _ = @import("integration_float_time.zig");
    _ = @import("integration_findmany.zig");
    _ = @import("integration_expected_errors.zig");
    _ = @import("integration_errmsg.zig");
    _ = @import("integration_owned.zig");
}
