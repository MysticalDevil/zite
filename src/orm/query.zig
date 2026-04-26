const std = @import("std");
const orm_root = @import("root.zig");
const Driver = @import("../driver/sqlite3.zig");
const Db = @import("../db/db.zig").Db(Driver);
const Stmt = @import("../db/stmt.zig").Stmt(Driver);
const meta = @import("../core/meta.zig");
const errors = @import("../core/errors.zig");
const types = @import("../core/types.zig");
const OrderDir = orm_root.OrderDir;
const QueryParam = orm_root.QueryParam;
const FindManyOptions = orm_root.FindManyOptions;
const engine = @import("engine.zig");
const mapper = @import("mapper.zig");
const cursor = @import("cursor.zig");
const guard = @import("guard.zig");

pub fn Query(comptime T: type) type {
    return struct {
        db: *Db,
        owned_allocator: std.mem.Allocator,
        where_buf: std.ArrayList(u8) = .empty,
        params: std.ArrayList(QueryParam) = .empty,
        order_buf: std.ArrayList(u8) = .empty,
        limit: ?usize = null,
        offset: ?usize = null,

        const Self = @This();
        const m = meta.getMeta(T);

        pub fn init(db: *Db, owned_allocator: std.mem.Allocator) Self {
            return .{
                .db = db,
                .owned_allocator = owned_allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.where_buf.deinit(self.db.allocator);
            self.params.deinit(self.db.allocator);
            self.order_buf.deinit(self.db.allocator);
        }

        pub fn whereEq(self: *Self, comptime field: []const u8, value: fieldValueType(field)) errors.OrmError!void {
            const column = comptime columnForField(field);
            const idx = self.params.items.len + 1;
            const where_len_before = self.where_buf.items.len;
            const params_len_before = self.params.items.len;
            errdefer {
                self.where_buf.shrinkRetainingCapacity(where_len_before);
                self.params.shrinkRetainingCapacity(params_len_before);
            }

            try self.appendWherePrefix();
            try self.where_buf.append(self.db.allocator, '"');
            try self.where_buf.appendSlice(self.db.allocator, column);
            try self.where_buf.appendSlice(self.db.allocator, "\"=?");
            try self.where_buf.print(self.db.allocator, "{}", .{idx});
            const p = try toQueryParam(value);
            try self.params.append(self.db.allocator, p);
        }

        /// Appends a SQL WHERE fragment and binds params using fragment-local
        /// placeholder numbering. `?1`, `?2`, and bare `?` are rebased against
        /// the query's existing parameter count before prepare/bind.
        pub fn whereSql(self: *Self, sql: []const u8, params_arg: anytype) errors.OrmError!void {
            try guard.validateWhereRawFragment(sql);
            return self.whereSqlUnsafe(sql, params_arg);
        }

        /// Appends an unchecked SQL WHERE fragment and binds params.
        /// Callers must guarantee `sql` is trusted.
        pub fn whereSqlUnsafe(self: *Self, sql: []const u8, params_arg: anytype) errors.OrmError!void {
            const trimmed = std.mem.trim(u8, sql, " \t\r\n");
            const where_len_before = self.where_buf.items.len;
            const params_len_before = self.params.items.len;
            errdefer {
                self.where_buf.shrinkRetainingCapacity(where_len_before);
                self.params.shrinkRetainingCapacity(params_len_before);
            }

            if (trimmed.len != 0) {
                try self.appendWherePrefix();
                try appendRebasedWhereSql(
                    self.db.allocator,
                    &self.where_buf,
                    trimmed,
                    params_len_before,
                );
            }

            const P = @TypeOf(params_arg);
            const ti = @typeInfo(P);
            if (ti != .@"struct") {
                return error.BindAllExpectedStructOrTuple;
            }
            inline for (ti.@"struct".fields) |f| {
                const p = try toQueryParam(@field(params_arg, f.name));
                try self.params.append(self.db.allocator, p);
            }
        }

        pub fn orderBy(self: *Self, comptime field: []const u8, dir: OrderDir) errors.OrmError!void {
            const column = comptime columnForField(field);

            if (self.order_buf.items.len != 0) {
                try self.order_buf.appendSlice(self.db.allocator, ", ");
            }
            try self.order_buf.append(self.db.allocator, '"');
            try self.order_buf.appendSlice(self.db.allocator, column);
            try self.order_buf.appendSlice(self.db.allocator, "\" ");
            switch (dir) {
                .asc => try self.order_buf.appendSlice(self.db.allocator, "ASC"),
                .desc => try self.order_buf.appendSlice(self.db.allocator, "DESC"),
            }
        }

        pub fn setLimit(self: *Self, n: usize) void {
            self.limit = n;
        }

        pub fn setOffset(self: *Self, n: usize) void {
            self.offset = n;
        }

        pub fn firstOwned(self: *Self) errors.OrmError!?mapper.OwnedRow(T) {
            var rows = try self.iterateOwnedWithLimit(1);
            defer rows.deinit();
            return rows.next();
        }

        pub fn firstHandle(self: *Self) errors.OrmError!?cursor.RowHandle(T) {
            var rows = try self.iterateViewsWithLimit(1);
            if (try rows.next()) |row| {
                // Move rows (and its prepared statement) into RowHandle.
                return .{
                    .rows = rows,
                    .row_generation = row.row_generation,
                };
            }
            return null;
        }

        pub fn iterateOwned(self: *Self) errors.OrmError!mapper.OwnedRows(T) {
            return self.iterateOwnedWithLimit(self.limit);
        }

        pub fn iterateViews(self: *Self) errors.OrmError!cursor.RowCursor(T) {
            return self.iterateViewsWithLimit(self.limit);
        }

        pub fn allOwned(self: *Self) errors.OrmError![]mapper.OwnedRow(T) {
            var rows = try self.iterateOwned();
            defer rows.deinit();

            var out: std.ArrayList(mapper.OwnedRow(T)) = .empty;
            defer out.deinit(self.owned_allocator);

            while (try rows.next()) |row| {
                try out.append(self.owned_allocator, row);
            }

            return try out.toOwnedSlice(self.owned_allocator);
        }

        fn iterateOwnedWithLimit(self: *Self, limit_override: ?usize) errors.OrmError!mapper.OwnedRows(T) {
            const opts: FindManyOptions = .{
                .order_by = if (self.order_buf.items.len == 0) null else self.order_buf.items,
                .limit = if (limit_override) |n| n else self.limit,
                .offset = self.offset,
            };

            const sql = try engine.sql.buildFindManySql(T, self.db, self.where_buf.items, opts);
            var st = try engine.sql.prepareOwnedSql(self.db, sql);
            errdefer st.deinit();

            for (self.params.items, 0..) |p, i| {
                try bindQueryParam(&st, @as(i32, @intCast(i + 1)), p);
            }

            return .{
                .rows = .{
                    .st = st,
                    .allocator = self.owned_allocator,
                    .done = false,
                },
            };
        }

        fn iterateViewsWithLimit(self: *Self, limit_override: ?usize) errors.OrmError!cursor.RowCursor(T) {
            const opts: FindManyOptions = .{
                .order_by = if (self.order_buf.items.len == 0) null else self.order_buf.items,
                .limit = if (limit_override) |n| n else self.limit,
                .offset = self.offset,
            };

            const sql = try engine.sql.buildFindManySql(T, self.db, self.where_buf.items, opts);
            var st = try engine.sql.prepareOwnedSql(self.db, sql);
            errdefer st.deinit();

            for (self.params.items, 0..) |p, i| {
                try bindQueryParam(&st, @as(i32, @intCast(i + 1)), p);
            }

            return .{
                .st = st,
                .done = false,
            };
        }

        fn appendWherePrefix(self: *Self) errors.OrmError!void {
            if (self.where_buf.items.len != 0) {
                try self.where_buf.appendSlice(self.db.allocator, " AND ");
            }
        }

        fn fieldValueType(comptime field: []const u8) type {
            inline for (@typeInfo(T).@"struct".fields) |f| {
                if (comptime std.mem.eql(u8, f.name, field)) {
                    if (comptime meta.isSkipped(f.name, m)) {
                        @compileError("Field " ++ field ++ " is skipped in Meta");
                    }
                    return f.type;
                }
            }
            @compileError("Unknown field for " ++ @typeName(T) ++ ": " ++ field);
        }

        fn columnForField(comptime field: []const u8) []const u8 {
            inline for (@typeInfo(T).@"struct".fields) |f| {
                if (comptime std.mem.eql(u8, f.name, field)) {
                    if (comptime meta.isSkipped(f.name, m)) {
                        @compileError("Field " ++ field ++ " is skipped in Meta");
                    }
                    return meta.columnName(f.name, m);
                }
            }
            @compileError("Unknown field for " ++ @typeName(T) ++ ": " ++ field);
        }
    };
}

pub fn toQueryParam(value: anytype) errors.OrmError!QueryParam {
    const V = @TypeOf(value);

    if (V == types.EpochMillis) {
        return .{ .int = value.value };
    }
    if (V == types.OwnedText) {
        return .{ .text = value.value };
    }
    if (V == types.OwnedBlob) {
        return .{ .blob = value.value };
    }

    switch (@typeInfo(V)) {
        .optional => {
            if (value == null) {
                return .null;
            }
            return toQueryParam(value.?);
        },
        .bool => return .{ .bool = value },
        .int, .comptime_int => return .{ .int = @as(i64, @intCast(value)) },
        .float, .comptime_float => return .{ .float = @as(f64, @floatCast(value)) },
        .@"enum" => return .{ .int = @as(i64, @intCast(@intFromEnum(value))) },
        .pointer => |p| switch (p.size) {
            .slice => {
                if (p.child == u8) {
                    return .{ .text = value };
                }
                return error.UnsupportedBindType;
            },
            .one => {
                const Child = p.child;
                const cti = @typeInfo(Child);
                if (cti == .array and cti.array.child == u8) {
                    return .{ .text = value[0..] };
                }
                return error.UnsupportedBindType;
            },
            else => return error.UnsupportedBindType,
        },
        .array => |a| {
            if (a.child == u8) {
                return .{ .text = value[0..] };
            }
            return error.UnsupportedBindType;
        },
        else => return error.UnsupportedBindType,
    }
}

/// Binds a QueryParam to a statement index.
/// Uses SQLITE_STATIC for text/blob to avoid an extra copy; the caller is
/// responsible for keeping the referenced data alive until stepping.
pub fn bindQueryParam(st: *Stmt, idx: i32, p: QueryParam) errors.OrmError!void {
    switch (p) {
        .null => try st.bindNull(idx),
        .int => |v| try st.bindInt(idx, v),
        .float => |v| try st.bindFloat(idx, v),
        .bool => |v| try st.bindBool(idx, v),
        .text => |v| try st.bindTextStatic(idx, v),
        .blob => |v| try st.bindBlobStatic(idx, v),
    }
}

pub fn appendRebasedWhereSql(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    sql: []const u8,
    base_index: usize,
) errors.OrmError!void {
    var state: guard.SqlScanState = .code;
    var i: usize = 0;
    var next_relative_index: usize = 1;

    while (i < sql.len) {
        switch (state) {
            .code => {
                if (sql[i] == '\'') {
                    state = .single_quote;
                    try out.append(allocator, sql[i]);
                    i += 1;
                    continue;
                }
                if (sql[i] == '"') {
                    state = .double_quote;
                    try out.append(allocator, sql[i]);
                    i += 1;
                    continue;
                }
                if (sql[i] == '-' and i + 1 < sql.len and sql[i + 1] == '-') {
                    state = .line_comment;
                    try out.appendSlice(allocator, sql[i .. i + 2]);
                    i += 2;
                    continue;
                }
                if (sql[i] == '/' and i + 1 < sql.len and sql[i + 1] == '*') {
                    state = .block_comment;
                    try out.appendSlice(allocator, sql[i .. i + 2]);
                    i += 2;
                    continue;
                }
                if (sql[i] == '?') {
                    var j = i + 1;
                    while (j < sql.len and std.ascii.isDigit(sql[j])) {
                        j += 1;
                    }

                    if (j == i + 1) {
                        try out.print(allocator, "?{}", .{base_index + next_relative_index});
                        next_relative_index += 1;
                    } else {
                        var local_index: usize = 0;
                        var k = i + 1;
                        while (k < j) : (k += 1) {
                            local_index = (local_index * 10) + (sql[k] - '0');
                        }
                        try out.print(allocator, "?{}", .{base_index + local_index});
                        if (local_index >= next_relative_index) {
                            next_relative_index = local_index + 1;
                        }
                    }
                    i = j;
                    continue;
                }

                try out.append(allocator, sql[i]);
                i += 1;
            },
            .single_quote => {
                const ch = sql[i];
                try out.append(allocator, ch);
                i += 1;
                if (ch == '\'') {
                    if (i < sql.len and sql[i] == '\'') {
                        try out.append(allocator, sql[i]);
                        i += 1;
                    } else {
                        state = .code;
                    }
                }
            },
            .double_quote => {
                const ch = sql[i];
                try out.append(allocator, ch);
                i += 1;
                if (ch == '"') {
                    if (i < sql.len and sql[i] == '"') {
                        try out.append(allocator, sql[i]);
                        i += 1;
                    } else {
                        state = .code;
                    }
                }
            },
            .line_comment => {
                const ch = sql[i];
                try out.append(allocator, ch);
                i += 1;
                if (ch == '\n') {
                    state = .code;
                }
            },
            .block_comment => {
                try out.append(allocator, sql[i]);
                i += 1;
                if (i >= 2 and sql[i - 2] == '*' and sql[i - 1] == '/') {
                    state = .code;
                }
            },
        }
    }
}

test "query: appendRebasedWhereSql rebases positional placeholders" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);

    try appendRebasedWhereSql(
        std.testing.allocator,
        &out,
        "\"age\" > ?1 AND \"name\" = ? AND note = '?9'",
        2,
    );

    try std.testing.expectEqualStrings(
        "\"age\" > ?3 AND \"name\" = ?4 AND note = '?9'",
        out.items,
    );
}

test "query: appendRebasedWhereSql skips quoted text and comments" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);

    try appendRebasedWhereSql(
        std.testing.allocator,
        &out,
        "\"name\" = ?1 /* ?2 */ AND note = '?3' -- ?4\nAND \"age\" = ?",
        4,
    );

    try std.testing.expectEqualStrings(
        "\"name\" = ?5 /* ?2 */ AND note = '?3' -- ?4\nAND \"age\" = ?6",
        out.items,
    );
}

test "query: appendRebasedWhereSql keeps question marks inside live quotes untouched" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);

    try appendRebasedWhereSql(
        std.testing.allocator,
        &out,
        "'ab?cd' = note AND \"co?l\" = ?1 AND name = 'x''?''y'",
        3,
    );

    try std.testing.expectEqualStrings(
        "'ab?cd' = note AND \"co?l\" = ?4 AND name = 'x''?''y'",
        out.items,
    );
}
