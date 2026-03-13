const std = @import("std");
const Db = @import("../db/db.zig").Db;
const Stmt = @import("../db/stmt.zig").Stmt;
const types = @import("../core/types.zig");
const meta = @import("../core/meta.zig");
const errors = @import("../core/errors.zig");
const mapper = @import("mapper.zig");
const engine = @import("engine.zig");

pub const UpsertResult = mapper.UpsertResult;
pub const TxMode = Db.TxMode;
pub const Tx = Db.Tx;
pub const OwnedRow = mapper.OwnedRow;
pub const OwnedRows = mapper.OwnedRows;

pub const OrderDir = enum {
    asc,
    desc,
};

pub fn BorrowedRow(comptime T: type) type {
    return struct {
        owner: *RowsBorrowed(T),
        row_generation: usize,

        const Self = @This();
        const m = meta.getMeta(T);

        pub fn get(self: Self, comptime field: []const u8) errors.ZiteError!BorrowedFieldType(T, field) {
            try self.owner.ensureRowAlive(self.row_generation);
            const col = comptime fieldColumnIndex(field);
            const FieldT = comptime fieldType(field);
            return engine.row.readValueBorrowed(FieldT, &self.owner.st, @as(i32, @intCast(col)));
        }

        fn fieldType(comptime field: []const u8) type {
            const ti = @typeInfo(T);
            if (ti != .@"struct") {
                @compileError("BorrowedRow requires a struct model");
            }

            inline for (ti.@"struct".fields) |f| {
                if (comptime std.mem.eql(u8, f.name, field)) {
                    if (comptime meta.isSkipped(f.name, m)) {
                        @compileError("Field " ++ field ++ " is skipped in Meta");
                    }
                    return f.type;
                }
            }
            @compileError("Unknown field for " ++ @typeName(T) ++ ": " ++ field);
        }

        fn fieldColumnIndex(comptime field: []const u8) usize {
            const ti = @typeInfo(T);
            if (ti != .@"struct") {
                @compileError("BorrowedRow requires a struct model");
            }

            comptime var col: usize = 0;
            inline for (ti.@"struct".fields) |f| {
                if (comptime meta.isSkipped(f.name, m)) {
                    continue;
                }
                if (comptime std.mem.eql(u8, f.name, field)) {
                    return col;
                }
                col += 1;
            }
            @compileError("Unknown field for " ++ @typeName(T) ++ ": " ++ field);
        }
    };
}

pub fn BorrowedFieldType(comptime T: type, comptime field: []const u8) type {
    const m = meta.getMeta(T);
    const ti = @typeInfo(T);
    if (ti != .@"struct") {
        @compileError("BorrowedFieldType requires a struct model");
    }

    inline for (ti.@"struct".fields) |f| {
        if (comptime std.mem.eql(u8, f.name, field)) {
            if (comptime meta.isSkipped(f.name, m)) {
                @compileError("Field " ++ field ++ " is skipped in Meta");
            }
            return engine.row.BorrowedFieldType(f.type);
        }
    }
    @compileError("Unknown field for " ++ @typeName(T) ++ ": " ++ field);
}

const QueryParam = union(enum) {
    null,
    int: i64,
    float: f64,
    bool: bool,
    text: []const u8,
    blob: []const u8,
};

const SqlScanState = enum {
    code,
    single_quote,
    double_quote,
    line_comment,
    block_comment,
};

pub fn BorrowedOne(comptime T: type) type {
    return struct {
        rows: RowsBorrowed(T),
        row_generation: usize,

        const Self = @This();

        pub fn get(self: *Self, comptime field: []const u8) errors.ZiteError!BorrowedFieldType(T, field) {
            return (BorrowedRow(T){
                .owner = &self.rows,
                .row_generation = self.row_generation,
            }).get(field);
        }

        pub fn deinit(self: *Self) void {
            self.rows.deinit();
        }
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

        pub fn beginTx(self: *Self, mode: Db.TxMode) errors.ZiteError!Db.Tx {
            return self.db.beginTx(mode);
        }

        pub fn findById(self: *Self, id: anytype) errors.ZiteError!?T {
            return mapper.findById(T, self.db, self.owned_allocator, id);
        }

        pub fn query(self: *Self) Query(T) {
            return Query(T).init(self.db, self.owned_allocator);
        }

        pub fn findByIdOwned(self: *Self, id: anytype) errors.ZiteError!?OwnedRow(T) {
            if (try mapper.findById(T, self.db, self.owned_allocator, id)) |v| {
                return .{
                    .allocator = self.owned_allocator,
                    .value = v,
                };
            }
            return null;
        }

        pub fn findByIdBorrowed(self: *Self, id: anytype) errors.ZiteError!?BorrowedOne(T) {
            const pk_field = comptime meta.getMeta(T).primary_key;
            var q = self.query();
            // Safe: q.deinit() only releases query builder buffers.
            // firstBorrowed() transfers a prepared statement into BorrowedOne.rows.
            defer q.deinit();
            try q.whereEq(pk_field, id);
            return q.firstBorrowed();
        }

        pub fn findOneRaw(self: *Self, where_clause: []const u8, params: anytype) errors.ZiteError!?T {
            return mapper.findOne(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params);
        }

        pub fn findOneBorrowedRaw(self: *Self, where_clause: []const u8, params: anytype) errors.ZiteError!?BorrowedOne(T) {
            var q = self.query();
            // Safe: q.deinit() does not touch the statement owned by returned BorrowedOne.
            defer q.deinit();
            try q.whereRaw(where_clause, params);
            return q.firstBorrowed();
        }

        pub fn findManyRaw(self: *Self, where_clause: []const u8, params: anytype) errors.ZiteError!mapper.Rows(T) {
            return mapper.findMany(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params);
        }

        pub fn findManyRawWithOptions(self: *Self, where_clause: []const u8, params: anytype, opts: mapper.FindManyOptions) errors.ZiteError!mapper.Rows(T) {
            return mapper.findManyWithOptions(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params, opts);
        }

        pub fn findManyOwnedRaw(self: *Self, where_clause: []const u8, params: anytype) errors.ZiteError!mapper.OwnedRows(T) {
            return mapper.findManyOwned(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params);
        }

        pub fn freeOwnedRow(self: *Self, value: *T) void {
            mapper.freeOwnedRow(T, self.owned_allocator, value);
        }
    };
}

pub fn RowsBorrowed(comptime T: type) type {
    return struct {
        st: Stmt,
        done: bool = false,
        cursor_generation: usize = 0,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            self.closeAndInvalidate();
        }

        pub fn next(self: *Self) errors.ZiteError!?BorrowedRow(T) {
            if (self.done) {
                return null;
            }

            errdefer {
                self.closeAndInvalidate();
            }

            const r = try self.st.step();
            if (r == .done) {
                self.closeAndInvalidate();
                return null;
            }

            self.cursor_generation +%= 1;
            return .{
                .owner = self,
                .row_generation = self.cursor_generation,
            };
        }

        fn ensureRowAlive(self: *const Self, row_generation: usize) errors.ZiteError!void {
            if (self.st.isFinalized()) {
                return error.StatementFinalized;
            }
            if (self.cursor_generation != row_generation) {
                return error.BorrowedRowStale;
            }
        }

        fn closeAndInvalidate(self: *Self) void {
            if (self.done) {
                return;
            }
            self.st.deinit();
            self.done = true;
            self.cursor_generation +%= 1;
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
            try self.appendParam(value);
        }

        /// Appends a raw WHERE fragment and binds params using fragment-local
        /// placeholder numbering. `?1`, `?2`, and bare `?` are rebased against
        /// the query's existing parameter count before prepare/bind.
        pub fn whereRaw(self: *Self, sql: []const u8, params: anytype) errors.ZiteError!void {
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

            const P = @TypeOf(params);
            const ti = @typeInfo(P);
            if (ti != .@"struct") {
                return error.BindAllExpectedStructOrTuple;
            }
            inline for (ti.@"struct".fields) |f| {
                try self.appendParam(@field(params, f.name));
            }
        }

        pub fn orderBy(self: *Self, comptime field: []const u8, dir: OrderDir) errors.ZiteError!void {
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

        pub fn firstOwned(self: *Self) errors.ZiteError!?OwnedRow(T) {
            var rows = try self.iterateOwnedWithLimit(1);
            defer rows.deinit();
            return rows.next();
        }

        pub fn firstBorrowed(self: *Self) errors.ZiteError!?BorrowedOne(T) {
            var rows = try self.iterateBorrowedWithLimit(1);
            if (try rows.next()) |row| {
                // Move rows (and its prepared statement) into BorrowedOne.
                return .{
                    .rows = rows,
                    .row_generation = row.row_generation,
                };
            }
            return null;
        }

        pub fn iterateOwned(self: *Self) errors.ZiteError!OwnedRows(T) {
            return self.iterateOwnedWithLimit(self.limit);
        }

        pub fn iterateBorrowed(self: *Self) errors.ZiteError!RowsBorrowed(T) {
            return self.iterateBorrowedWithLimit(self.limit);
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

        fn iterateOwnedWithLimit(self: *Self, limit_override: ?usize) errors.ZiteError!OwnedRows(T) {
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
                .rows = .{
                    .st = st,
                    .allocator = self.owned_allocator,
                    .done = false,
                },
            };
        }

        fn iterateBorrowedWithLimit(self: *Self, limit_override: ?usize) errors.ZiteError!RowsBorrowed(T) {
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

fn appendRebasedWhereSql(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    sql: []const u8,
    base_index: usize,
) errors.ZiteError!void {
    var state: SqlScanState = .code;
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
                try out.append(allocator, sql[i]);
                i += 1;
                if (sql[i - 1] == '\'') {
                    if (i < sql.len and sql[i] == '\'') {
                        try out.append(allocator, sql[i]);
                        i += 1;
                    } else {
                        state = .code;
                    }
                }
            },
            .double_quote => {
                try out.append(allocator, sql[i]);
                i += 1;
                if (sql[i - 1] == '"') {
                    if (i < sql.len and sql[i] == '"') {
                        try out.append(allocator, sql[i]);
                        i += 1;
                    } else {
                        state = .code;
                    }
                }
            },
            .line_comment => {
                try out.append(allocator, sql[i]);
                i += 1;
                if (sql[i - 1] == '\n') {
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

test "orm: appendRebasedWhereSql rebases positional placeholders" {
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

test "orm: appendRebasedWhereSql skips quoted text and comments" {
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
