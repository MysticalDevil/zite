const std = @import("std");
const Driver = @import("driver/sqlite3.zig");
const Db = @import("db/db.zig").Db(Driver);
const Stmt = @import("db/stmt.zig").Stmt(Driver);
const orm = @import("orm/orm.zig");
const mapper = @import("orm/mapper.zig");
const errors = @import("core/errors.zig");
const types = @import("core/types.zig");

pub const AsyncPool = struct {
    allocator: std.mem.Allocator,
    db_path: []const u8,

    pub const Options = struct {};

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, db_path: []const u8, options: Options) errors.AllocError!Self {
        _ = options;
        return .{
            .allocator = allocator,
            .db_path = try allocator.dupe(u8, db_path),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.db_path);
        self.* = undefined;
    }

    pub fn withConnection(self: *const Self, io: std.Io, context: anytype, comptime function: anytype) AsyncCallResult(@TypeOf(function)) {
        const Function = @TypeOf(function);
        const Result = normalizedResultType(Function);
        comptime assertAsyncResultAllowed(payloadType(Result));

        const Context = @TypeOf(context);
        const Job = struct {
            pool: *const Self,
            context: Context,
        };
        const Runner = struct {
            fn run(job: Job) Result {
                var db = try Db.open(job.pool.allocator, job.pool.db_path);
                defer db.deinit();
                return @call(.auto, function, .{ &db, job.context });
            }
        };

        var future = std.Io.concurrent(io, Runner.run, .{.{ .pool = self, .context = context }}) catch {
            return error.ConcurrencyUnavailable;
        };
        return future.await(io);
    }

    pub fn insert(self: *const Self, io: std.Io, comptime T: type, entity: T) errors.AsyncOrmError!i64 {
        const Context = struct {
            entity: T,
        };
        const Runner = struct {
            fn run(db: *Db, ctx: Context) errors.OrmError!i64 {
                var repo = orm.repository(T, db, db.allocator);
                return repo.insert(ctx.entity);
            }
        };
        return self.withConnection(io, Context{ .entity = entity }, Runner.run);
    }

    pub fn update(self: *const Self, io: std.Io, comptime T: type, entity: T) errors.AsyncOrmError!i32 {
        const Context = struct {
            entity: T,
        };
        const Runner = struct {
            fn run(db: *Db, ctx: Context) errors.OrmError!i32 {
                var repo = orm.repository(T, db, db.allocator);
                return repo.update(ctx.entity);
            }
        };
        return self.withConnection(io, Context{ .entity = entity }, Runner.run);
    }

    pub fn upsert(self: *const Self, io: std.Io, comptime T: type, entity: T) errors.AsyncOrmError!orm.UpsertResult {
        const Context = struct {
            entity: T,
        };
        const Runner = struct {
            fn run(db: *Db, ctx: Context) errors.OrmError!orm.UpsertResult {
                var repo = orm.repository(T, db, db.allocator);
                return repo.upsert(ctx.entity);
            }
        };
        return self.withConnection(io, Context{ .entity = entity }, Runner.run);
    }

    pub fn deleteById(self: *const Self, io: std.Io, comptime T: type, id: anytype) errors.AsyncOrmError!i32 {
        const Context = struct {
            id: @TypeOf(id),
        };
        const Runner = struct {
            fn run(db: *Db, ctx: Context) errors.OrmError!i32 {
                var repo = orm.repository(T, db, db.allocator);
                return repo.deleteById(ctx.id);
            }
        };
        return self.withConnection(io, Context{ .id = id }, Runner.run);
    }

    pub fn findByIdOwned(
        self: *const Self,
        io: std.Io,
        comptime T: type,
        owned_allocator: std.mem.Allocator,
        id: anytype,
    ) errors.AsyncOrmError!?orm.OwnedRow(T) {
        const Context = struct {
            owned_allocator: std.mem.Allocator,
            id: @TypeOf(id),
        };
        const Runner = struct {
            fn run(db: *Db, ctx: Context) errors.OrmError!?orm.OwnedRow(T) {
                var repo = orm.repository(T, db, ctx.owned_allocator);
                return repo.findByIdOwned(ctx.id);
            }
        };
        return self.withConnection(io, Context{
            .owned_allocator = owned_allocator,
            .id = id,
        }, Runner.run);
    }

    pub fn findOne(
        self: *const Self,
        io: std.Io,
        comptime T: type,
        owned_allocator: std.mem.Allocator,
        where_clause: []const u8,
        params: anytype,
    ) errors.AsyncOrmError!?T {
        const Context = struct {
            owned_allocator: std.mem.Allocator,
            where_clause: []const u8,
            params: @TypeOf(params),
        };
        const Runner = struct {
            fn run(db: *Db, ctx: Context) errors.OrmError!?T {
                var repo = orm.repository(T, db, ctx.owned_allocator);
                return repo.findOneSql(ctx.where_clause, ctx.params);
            }
        };
        return self.withConnection(io, Context{
            .owned_allocator = owned_allocator,
            .where_clause = where_clause,
            .params = params,
        }, Runner.run);
    }

    pub fn freeOwnedRow(comptime T: type, allocator: std.mem.Allocator, value: *T) void {
        mapper.freeOwnedRow(T, allocator, value);
    }
};

fn AsyncCallResult(comptime Function: type) type {
    const Result = normalizedResultType(Function);
    return switch (@typeInfo(Result)) {
        .error_union => |eu| (eu.error_set || error{ConcurrencyUnavailable})!eu.payload,
        else => error{ConcurrencyUnavailable}!Result,
    };
}

fn normalizedResultType(comptime Function: type) type {
    const fn_info = @typeInfo(Function).@"fn";
    const Result = fn_info.return_type orelse @compileError("async_pool worker must have a return type");
    return switch (@typeInfo(Result)) {
        .error_union => Result,
        else => errors.OrmError!Result,
    };
}

fn payloadType(comptime MaybeErrorUnion: type) type {
    return switch (@typeInfo(MaybeErrorUnion)) {
        .error_union => |eu| eu.payload,
        else => MaybeErrorUnion,
    };
}

fn assertAsyncResultAllowed(comptime T: type) void {
    if (!isAsyncResultAllowed(T)) {
        @compileError("async_pool functions must not return row-view, cursor, stmt, or db state: " ++ @typeName(T));
    }
}

fn isAsyncResultAllowed(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .error_union => |eu| return isAsyncResultAllowed(eu.payload),
        .optional => |opt| return isAsyncResultAllowed(opt.child),
        .array => |a| return isAsyncResultAllowed(a.child),
        .vector => |v| return isAsyncResultAllowed(v.child),
        .@"struct" => |s| {
            if (forbiddenAsyncStructType(T)) {
                return false;
            }
            inline for (s.fields) |f| {
                if (!isAsyncResultAllowed(f.type)) {
                    return false;
                }
            }
            return true;
        },
        .pointer => |p| {
            if (p.size == .one and (p.child == Db or p.child == Stmt)) {
                return false;
            }
            return true;
        },
        else => return !forbiddenLeafType(T),
    }
}

fn forbiddenAsyncStructType(comptime T: type) bool {
    return @hasDecl(T, "__zite_async_guard");
}

fn forbiddenLeafType(comptime T: type) bool {
    if (T == Db or T == Stmt) {
        return true;
    }
    return false;
}

const GuardRow = struct {
    id: i64,
    name: types.OwnedText,

    pub const Meta = .{
        .table = "guard_rows",
        .primary_key = "id",
    };
};

test "async_pool: result type guard allows owned rows and rejects row views" {
    try std.testing.expect(isAsyncResultAllowed(orm.OwnedRow(GuardRow)));
    try std.testing.expect(!isAsyncResultAllowed(orm.RowHandle(GuardRow)));
    try std.testing.expect(!isAsyncResultAllowed(orm.RowView(GuardRow)));
}
