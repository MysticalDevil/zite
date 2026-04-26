const std = @import("std");
const orm_root = @import("root.zig");
const Driver = @import("../driver/sqlite3.zig");
const Db = @import("../db/db.zig").Db(Driver);
const meta = @import("../core/meta.zig");
const errors = @import("../core/errors.zig");
const mapper = @import("mapper.zig");

const UpsertResult = orm_root.UpsertResult;
const FindManyOptions = orm_root.FindManyOptions;
const query_mod = @import("query.zig");
const cursor = @import("cursor.zig");
const guard = @import("guard.zig");

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

        pub fn insert(self: *Self, entity: T) errors.OrmError!i64 {
            return mapper.insert(T, self.db, entity);
        }

        pub fn insertMany(self: *Self, entities: []const T) errors.OrmError!usize {
            return mapper.insertMany(T, self.db, entities);
        }

        pub fn update(self: *Self, entity: T) errors.OrmError!i32 {
            return mapper.update(T, self.db, entity);
        }

        pub fn upsert(self: *Self, entity: T) errors.OrmError!UpsertResult {
            return mapper.upsert(T, self.db, entity);
        }

        pub fn deleteById(self: *Self, id: mapper.pkFieldType(T, meta.getMeta(T))) errors.OrmError!i32 {
            return mapper.deleteById(T, self.db, id);
        }

        /// Deletes rows using a guarded SQL WHERE fragment.
        /// Rejects unsafe fragments (e.g. comments/semicolon/subquery keywords).
        pub fn deleteWhereSql(self: *Self, where_clause: []const u8, params: anytype) errors.OrmError!i32 {
            try guard.validateWhereRawFragment(where_clause);
            return self.deleteWhereSqlUnsafe(where_clause, params);
        }

        /// Deletes rows using an unchecked SQL WHERE fragment.
        /// Caller must ensure `where_clause` is trusted.
        pub fn deleteWhereSqlUnsafe(self: *Self, where_clause: []const u8, params: anytype) errors.OrmError!i32 {
            return mapper.deleteWhere(T, @TypeOf(params), self.db, where_clause, params);
        }

        pub fn beginTx(self: *Self, mode: Db.TxMode) errors.DbError!Db.Tx {
            return self.db.beginTx(mode);
        }

        pub fn findById(self: *Self, id: mapper.pkFieldType(T, meta.getMeta(T))) errors.OrmError!?T {
            return mapper.findById(T, self.db, self.owned_allocator, id);
        }

        pub fn query(self: *Self) query_mod.Query(T) {
            return query_mod.Query(T).init(self.db, self.owned_allocator);
        }

        pub fn findByIdOwned(self: *Self, id: mapper.pkFieldType(T, meta.getMeta(T))) errors.OrmError!?mapper.OwnedRow(T) {
            if (try mapper.findById(T, self.db, self.owned_allocator, id)) |v| {
                return .{
                    .allocator = self.owned_allocator,
                    .value = v,
                };
            }
            return null;
        }

        pub fn findByIdHandle(self: *Self, id: mapper.pkFieldType(T, meta.getMeta(T))) errors.OrmError!?cursor.RowHandle(T) {
            const pk_field = comptime meta.getMeta(T).primary_key;
            var q = self.query();
            errdefer q.deinit();
            try q.whereEq(pk_field, id);
            const result = try q.firstHandle();
            q.deinit();
            return result;
        }

        pub fn findOneSql(self: *Self, where_clause: []const u8, params: anytype) errors.OrmError!?T {
            try guard.validateWhereRawFragment(where_clause);
            return mapper.findOne(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params);
        }

        pub fn findOneSqlUnsafe(self: *Self, where_clause: []const u8, params: anytype) errors.OrmError!?T {
            return mapper.findOne(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params);
        }

        pub fn findOneHandleSql(self: *Self, where_clause: []const u8, params: anytype) errors.OrmError!?cursor.RowHandle(T) {
            var q = self.query();
            errdefer q.deinit();
            try q.whereSql(where_clause, params);
            const result = try q.firstHandle();
            q.deinit();
            return result;
        }

        pub fn findOneHandleSqlUnsafe(self: *Self, where_clause: []const u8, params: anytype) errors.OrmError!?cursor.RowHandle(T) {
            var q = self.query();
            errdefer q.deinit();
            try q.whereSqlUnsafe(where_clause, params);
            const result = try q.firstHandle();
            q.deinit();
            return result;
        }

        /// Executes a guarded `findMany` using a SQL WHERE fragment.
        pub fn findManySql(self: *Self, where_clause: []const u8, params: anytype) errors.OrmError!mapper.Rows(T) {
            try guard.validateWhereRawFragment(where_clause);
            return self.findManySqlUnsafe(where_clause, params);
        }

        /// Executes an unchecked `findMany` using a SQL WHERE fragment.
        /// Caller must ensure `where_clause` is trusted.
        pub fn findManySqlUnsafe(self: *Self, where_clause: []const u8, params: anytype) errors.OrmError!mapper.Rows(T) {
            return mapper.findMany(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params);
        }

        /// Executes a guarded `findMany` with options.
        /// Validates both `where_clause` and `opts.order_by` (if provided).
        pub fn findManySqlWithOptions(self: *Self, where_clause: []const u8, params: anytype, opts: FindManyOptions) errors.OrmError!mapper.Rows(T) {
            try guard.validateWhereRawFragment(where_clause);
            if (opts.order_by) |order_by| {
                try guard.validateOrderByRawFragment(order_by);
            }
            return self.findManySqlWithOptionsUnsafe(where_clause, params, opts);
        }

        /// Executes an unchecked `findMany` with options.
        /// Caller must ensure both `where_clause` and `opts.order_by` are trusted.
        pub fn findManySqlWithOptionsUnsafe(self: *Self, where_clause: []const u8, params: anytype, opts: FindManyOptions) errors.OrmError!mapper.Rows(T) {
            return mapper.findManyWithOptions(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params, opts);
        }

        /// Executes a guarded `findManyOwned` using a SQL WHERE fragment.
        pub fn findManyOwnedSql(self: *Self, where_clause: []const u8, params: anytype) errors.OrmError!mapper.OwnedRows(T) {
            try guard.validateWhereRawFragment(where_clause);
            return self.findManyOwnedSqlUnsafe(where_clause, params);
        }

        /// Executes an unchecked `findManyOwned` using a SQL WHERE fragment.
        /// Caller must ensure `where_clause` is trusted.
        pub fn findManyOwnedSqlUnsafe(self: *Self, where_clause: []const u8, params: anytype) errors.OrmError!mapper.OwnedRows(T) {
            return mapper.findManyOwned(T, @TypeOf(params), self.db, self.owned_allocator, where_clause, params);
        }

        pub fn freeOwnedRow(self: *Self, value: *T) void {
            mapper.freeOwnedRow(T, self.owned_allocator, value);
        }
    };
}
