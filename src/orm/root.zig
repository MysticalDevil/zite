const std = @import("std");

// ========== ORM public types ==========

/// Result tag returned by upsert.
pub const UpsertResult = enum {
    inserted,
    updated,
};

/// Optional clauses for findMany queries.
pub const FindManyOptions = struct {
    order_by: ?[]const u8 = null,
    limit: ?usize = null,
    offset: ?usize = null,
};

/// Sort direction for query builder.
pub const OrderDir = enum {
    asc,
    desc,
};

/// Parameter value for query builder binding.
pub const QueryParam = union(enum) {
    null,
    int: i64,
    float: f64,
    bool: bool,
    text: []const u8,
    blob: []const u8,
};

// ========== Subsystem re-exports (non-cyclic) ==========

pub const schema = @import("schema.zig");
pub const guard = @import("guard.zig");

// ========== Lazy re-exports via generic functions ==========

pub fn OwnedRow(comptime T: type) type {
    return @import("mapper.zig").OwnedRow(T);
}
pub fn OwnedRows(comptime T: type) type {
    return @import("mapper.zig").OwnedRows(T);
}
pub fn Rows(comptime T: type) type {
    return @import("mapper.zig").Rows(T);
}
pub const freeOwnedRow = @import("mapper.zig").freeOwnedRow;

pub fn Query(comptime T: type) type {
    return @import("query.zig").Query(T);
}
pub const appendRebasedWhereSql = @import("query.zig").appendRebasedWhereSql;
pub const toQueryParam = @import("query.zig").toQueryParam;
pub const bindQueryParam = @import("query.zig").bindQueryParam;

pub fn RowView(comptime T: type) type {
    return @import("cursor.zig").RowView(T);
}
pub fn RowHandle(comptime T: type) type {
    return @import("cursor.zig").RowHandle(T);
}
pub fn RowCursor(comptime T: type) type {
    return @import("cursor.zig").RowCursor(T);
}
pub fn ViewFieldType(comptime T: type, comptime field: []const u8) type {
    return @import("cursor.zig").ViewFieldType(T, field);
}

pub fn Repository(comptime T: type) type {
    return @import("repository.zig").Repository(T);
}
pub fn repository(comptime T: type, db: anytype, owned_allocator: std.mem.Allocator) Repository(T) {
    return @import("repository.zig").repository(T, db, owned_allocator);
}

pub const validateWhereRawFragment = guard.validateWhereRawFragment;
pub const validateOrderByRawFragment = guard.validateOrderByRawFragment;
