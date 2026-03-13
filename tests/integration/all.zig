comptime {
    _ = @import("blob.zig");
    _ = @import("create_table.zig");
    _ = @import("text.zig");
    _ = @import("prepare_step.zig");
    _ = @import("stmt_prepare_step.zig");
    _ = @import("stmt_bind_all.zig");
    _ = @import("insert_update.zig");
    _ = @import("insert_many.zig");
    _ = @import("stmt_column_owned.zig");
    _ = @import("find_by_id.zig");
    _ = @import("find_one.zig");
    _ = @import("float_epoch_millis.zig");
    _ = @import("find_many.zig");
    _ = @import("find_many_options.zig");
    _ = @import("expected_errors.zig");
    _ = @import("errmsg.zig");
    _ = @import("owned_row.zig");
    _ = @import("delete.zig");
    _ = @import("upsert.zig");
}
