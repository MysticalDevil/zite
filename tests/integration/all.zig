comptime {
    _ = @import("blob.zig");
    _ = @import("create_table.zig");
    _ = @import("text.zig");
    _ = @import("prepare_step.zig");
    _ = @import("stmt_prepare_step.zig");
    _ = @import("stmt_bindall.zig");
    _ = @import("insert_update.zig");
    _ = @import("stmt_column_owned.zig");
    _ = @import("getbyid.zig");
    _ = @import("findone.zig");
    _ = @import("float_time.zig");
    _ = @import("findmany.zig");
    _ = @import("expected_errors.zig");
    _ = @import("errmsg.zig");
    _ = @import("owned.zig");
}
