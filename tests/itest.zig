const std = @import("std");

pub const std_options: std.Options = .{
    .log_level = .err,
};

comptime {
    _ = @import("integration/create_table.zig");
    _ = @import("integration/prepare_step.zig");
    _ = @import("integration/stmt_prepare_step.zig");
    _ = @import("integration/stmt_bindall.zig");
    _ = @import("integration/insert_update.zig");
    _ = @import("integration/stmt_column_owned.zig");
    _ = @import("integration/getbyid.zig");
    _ = @import("integration/findone.zig");
    _ = @import("integration/float_time.zig");
    _ = @import("integration/findmany.zig");
    _ = @import("integration/expected_errors.zig");
    _ = @import("integration/errmsg.zig");
    _ = @import("integration/owned.zig");
}
