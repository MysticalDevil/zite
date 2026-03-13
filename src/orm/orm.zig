const std = @import("std");
const Db = @import("../db/db.zig").Db;
const Stmt = @import("../db/stmt.zig").Stmt;
const types = @import("../core/types.zig");
const meta = @import("../core/meta.zig");
const errors = @import("../core/errors.zig");
const mapper = @import("mapper.zig");
const engine = @import("engine.zig");

pub const UpsertResult = mapper.UpsertResult;

pub const OrderDir = enum {
    asc,
    desc,
};

const QueryParam = union(enum) {
    null,
    int: i64,
    float: f64,
    bool: bool,
    text: []const u8,
    blob: []const u8,
};

pub fn OwnedRow(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        value: T,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            engine.row.freeOwnedRow(T, self.allocator, &self.value);
        }
    };
}

fn wrapOwnedRow(comptime T: type, allocator: std.mem.Allocator, v: T) OwnedRow(T) {
    return .{
        .allocator = allocator,
        .value = v,
    };
}

pub fn repository(comptime T: type, db: *Db, owned_allocator: std.mem.Allocator) Repository(T) {
    return .{
        .db = db,
        .owned_allocator = owned_allocator,
    };
}

pub fn Repository(comptime T: type) type {
    return struct {
        db: *Db,
        owned_allocator: std.mem.Allocator,

        const Self = @This();

        pub fn insert(self: *Self, entity: T) errors.ZiteError!i64 {
            return mapper.insert(T, self.db, entity);
        }

        pub fn insertMany(self: *Self, entities: []const T) errors.ZiteError!usize {
            return mapper.insertMany(T, self.db, entities);
        }

        pub fn update(self: *Self, entity: T) errors.ZiteError!i32 {
            return mapper.update(T, self.db, entity);
        }

        pub fn upsert(self: *Self, entity: T) errors.ZiteError!UpsertResult {
            return mapper.upsert(T, self.db, entity);
        }

        pub fn deleteById(self: *Self, id: anytype) errors.ZiteError!i32 {
            return mapper.deleteById(T, self.db, id);
        }

        pub fn deleteWhereRaw(self: *Self, where_clause: []const u8, params: anytype) errors.ZiteError!i32 {
            return mapper.deleteWhere(T, @TypeOf(params), self.db, where_clause, params);
        }

        pub fn findById(self: *Self, id: anytype) errors.ZiteError!?T {
            return mapper.findById(T, self.db, self.owned_allocator, id);
        }

        pub fn query(self: *Self) Query(T) {
            return Query(T).init(self.db, self.owned_allocator);
        }

        pub fn findByIdOwned(self: *Self, id: anytype) errors.ZiteError!?OwnedRow(T) {
            if (try mapper.findById(T, self.db, self.owned_allocator, id)) |v| {
                return wrapOwnedRow(T, self.owned_allocator, v);
            }
            return null;
        }

        pub fn findOneRaw(self: *Self, where_clause: []const u8, params: anytype) errors.ZiteError!?T {
            return mapper.findOne(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params);
        }

        pub fn findManyRaw(self: *Self, where_clause: []const u8, params: anytype) errors.ZiteError!mapper.Rows(T) {
            return mapper.findMany(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params);
        }

        pub fn findManyRawWithOptions(self: *Self, where_clause: []const u8, params: anytype, opts: mapper.FindManyOptions) errors.ZiteError!mapper.Rows(T) {
            return mapper.findManyWithOptions(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params, opts);
        }

        pub fn findManyOwnedRaw(self: *Self, where_clause: []const u8, params: anytype) errors.ZiteError!mapper.RowsOwned(T) {
            return mapper.findManyOwned(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params);
        }

        pub fn freeOwnedRow(self: *Self, value: *T) void {
            mapper.freeOwnedRow(T, self.owned_allocator, value);
        }
    };
}

pub fn RowsOwned(comptime T: type) type {
    return struct {
        st: Stmt,
        allocator: std.mem.Allocator,
        done: bool = false,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            if (!self.done) {
                self.st.deinit();
                self.done = true;
            }
        }

        pub fn next(self: *Self) errors.ZiteError!?OwnedRow(T) {
            if (self.done) return null;

            errdefer {
                self.st.deinit();
                self.done = true;
            }

            const r = try self.st.step();
            if (r == .done) {
                self.st.deinit();
                self.done = true;
                return null;
            }

            const value = try engine.row.readStruct(T, &self.st, self.allocator);
            return wrapOwnedRow(T, self.allocator, value);
        }
    };
}

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

        pub fn whereEq(self: *Self, comptime field: []const u8, value: anytype) errors.ZiteError!void {
            const column = comptime columnForField(field);
            const idx = self.params.items.len + 1;

            try self.appendWherePrefix();
            try self.where_buf.append(self.db.allocator, '"');
            try self.where_buf.appendSlice(self.db.allocator, column);
            try self.where_buf.appendSlice(self.db.allocator, "\"=?");
            try self.where_buf.print(self.db.allocator, "{}", .{idx});
            try self.appendParam(value);
        }

        pub fn whereRaw(self: *Self, sql: []const u8, params: anytype) errors.ZiteError!void {
            const trimmed = std.mem.trim(u8, sql, " \t\r\n");
            if (trimmed.len != 0) {
                try self.appendWherePrefix();
                try self.where_buf.appendSlice(self.db.allocator, trimmed);
            }

            const P = @TypeOf(params);
            const ti = @typeInfo(P);
            if (ti != .@"struct") return error.BindAllExpectedStructOrTuple;
            inline for (ti.@"struct".fields) |f| {
                try self.appendParam(@field(params, f.name));
            }
        }

        pub fn orderBy(self: *Self, comptime field: []const u8, dir: OrderDir) errors.ZiteError!void {
            const column = comptime columnForField(field);

            self.order_buf.clearRetainingCapacity();
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

        pub fn firstOwned(self: *Self) errors.ZiteError!?OwnedRow(T) {
            var rows = try self.iterateOwnedWithLimit(1);
            defer rows.deinit();
            return rows.next();
        }

        pub fn firstBorrowed(self: *Self) errors.ZiteError!?OwnedRow(T) {
            return self.firstOwned();
        }

        pub fn iterateOwned(self: *Self) errors.ZiteError!RowsOwned(T) {
            return self.iterateOwnedWithLimit(self.limit);
        }

        pub fn iterateBorrowed(self: *Self) errors.ZiteError!RowsOwned(T) {
            return self.iterateOwned();
        }

        pub fn allOwned(self: *Self) errors.ZiteError![]OwnedRow(T) {
            var rows = try self.iterateOwned();
            defer rows.deinit();

            var out: std.ArrayList(OwnedRow(T)) = .empty;
            defer out.deinit(self.owned_allocator);

            while (try rows.next()) |row| {
                try out.append(self.owned_allocator, row);
            }

            return try out.toOwnedSlice(self.owned_allocator);
        }

        fn iterateOwnedWithLimit(self: *Self, limit_override: ?usize) errors.ZiteError!RowsOwned(T) {
            const opts: engine.sql.FindManyOptions = .{
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
                .allocator = self.owned_allocator,
                .done = false,
            };
        }

        fn appendWherePrefix(self: *Self) errors.ZiteError!void {
            if (self.where_buf.items.len != 0) {
                try self.where_buf.appendSlice(self.db.allocator, " AND ");
            }
        }

        fn appendParam(self: *Self, value: anytype) errors.ZiteError!void {
            const p = try toQueryParam(value);
            try self.params.append(self.db.allocator, p);
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

fn toQueryParam(value: anytype) errors.ZiteError!QueryParam {
    const V = @TypeOf(value);

    if (V == types.EpochMillis) return .{ .int = value.value };
    if (V == types.OwnedText) return .{ .text = value.value };
    if (V == types.OwnedBlob) return .{ .blob = value.value };

    switch (@typeInfo(V)) {
        .optional => {
            if (value == null) return .null;
            return toQueryParam(value.?);
        },
        .bool => return .{ .bool = value },
        .int, .comptime_int => return .{ .int = @as(i64, @intCast(value)) },
        .float, .comptime_float => return .{ .float = @as(f64, @floatCast(value)) },
        .@"enum" => return .{ .int = @as(i64, @intCast(@intFromEnum(value))) },
        else => return error.UnsupportedBindType,
    }
}

fn bindQueryParam(st: *Stmt, idx: i32, p: QueryParam) errors.ZiteError!void {
    switch (p) {
        .null => try st.bindNull(idx),
        .int => |v| try st.bindInt(idx, v),
        .float => |v| try st.bindFloat(idx, v),
        .bool => |v| try st.bindBool(idx, v),
        .text => |v| try st.bindText(idx, v),
        .blob => |v| try st.bindBlob(idx, v),
    }
}
