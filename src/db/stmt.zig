const std = @import("std");
const types = @import("../core/types.zig");
const diag = @import("diag.zig");
const errors = @import("../core/errors.zig");
const driver_root = @import("../driver/root.zig");
const driver_errors = @import("driver_errors.zig");

/// Result of stepping a statement.
pub const StepResult = enum {
    /// A row is available to read.
    row,
    /// No more rows are available.
    done,
};

/// Prepared statement wrapper for selected driver statements.
pub fn Stmt(comptime Driver: type) type {
    comptime driver_root.assertDriver(Driver);
    const DbT = @import("db.zig").Db(Driver);

    return struct {
        /// Back-reference to the owning Db (for diagnostics and tracking).
        db: *DbT,
        /// Opaque statement handle.
        stmt: Driver.StmtHandle,
        /// Prevents double-finalize and enables Db tracking.
        finalized: bool = false,

        const Self = @This();

        /// Prepares a SQL statement. Must be finalized when no longer used.
        /// Caller owns the statement and must call `deinit()`.
        pub fn init(db: *DbT, sql: []const u8) errors.StmtError!Self {
            var stmt_opt: ?Driver.StmtHandle = null;

            const n: i32 = @intCast(sql.len);
            const rc = Driver.stmt.prepare(
                db.handle,
                sql.ptr,
                n,
                &stmt_opt,
            );
            if (rc != Driver.OK or stmt_opt == null) {
                diag.logSqlite(Driver, db, rc, "driver_prepare", sql);
                return driver_errors.mapDriverRc(Driver, rc, error.DriverPrepareFailed);
            }

            db.registerStmt();
            return .{ .db = db, .stmt = stmt_opt.? };
        }

        /// Finalizes the underlying statement (idempotent).
        pub fn finalize(self: *Self) errors.StmtError!void {
            if (self.finalized) {
                return;
            }

            const rc = Driver.stmt.finalize(self.stmt);
            self.finalized = true;
            var unregister_err: ?errors.DbError = null;
            self.db.unregisterStmt() catch |err| {
                unregister_err = err;
            };

            if (rc != Driver.OK) {
                diag.logSqlite(Driver, self.db, rc, "driver_finalize", null);
                return driver_errors.mapDriverRc(Driver, rc, error.DriverFinalizeFailed);
            }
            if (unregister_err) |err| {
                return err;
            }
        }

        /// Alias for finalize() to match deinit patterns.
        pub fn deinit(self: *Self) void {
            self.finalize() catch |err| {
                // Cleanup paths must stay quiet for expected statement failures
                // (for example, constraint errors already observed by callers).
                // Only log lifecycle bookkeeping corruption.
                if (err == error.StatementCountUnderflow) {
                    std.log.warn("driver warning what=stmt_unregister_failed err={}", .{err});
                }
            };
        }

        /// Returns whether this statement has been finalized.
        pub fn isFinalized(self: *const Self) bool {
            return self.finalized;
        }

        /// Resets the statement so it can be re-executed.
        pub fn reset(self: *Self) errors.StmtError!void {
            try self.ensureOpen();
            const rc = Driver.stmt.reset(self.stmt);
            if (rc != Driver.OK) {
                diag.logSqlite(Driver, self.db, rc, "driver_reset", null);
                return driver_errors.mapDriverRc(Driver, rc, error.DriverResetFailed);
            }
        }

        /// Steps the statement. Returns .row for a row, .done when complete.
        /// The caller must read columns before stepping again.
        pub fn step(self: *Self) errors.StmtError!StepResult {
            try self.ensureOpen();
            const rc = Driver.stmt.step(self.stmt);
            return switch (rc) {
                Driver.ROW => .row,
                Driver.DONE => .done,
                else => blk: {
                    diag.logSqlite(Driver, self.db, rc, "driver_step", null);
                    break :blk driver_errors.mapDriverRc(Driver, rc, error.DriverStepFailed);
                },
            };
        }

        // ---------- bind (1-based index) ----------
        /// Binds NULL to a 1-based parameter index.
        pub fn bindNull(self: *Self, idx: i32) errors.StmtError!void {
            try self.ensureOpen();
            const rc = Driver.stmt.bindNull(self.stmt, idx);
            if (rc != Driver.OK) {
                diag.logSqlite(Driver, self.db, rc, "driver_bind_null", null);
                diag.logBind("null", idx);
                return driver_errors.mapDriverRc(Driver, rc, error.DriverBindFailed);
            }
        }

        /// Binds an integer to a 1-based parameter index.
        pub fn bindInt(self: *Self, idx: i32, value: i64) errors.StmtError!void {
            try self.ensureOpen();
            const rc = Driver.stmt.bindInt64(self.stmt, idx, value);
            if (rc != Driver.OK) {
                diag.logSqlite(Driver, self.db, rc, "driver_bind_int64", null);
                diag.logBind("int64", idx);
                return driver_errors.mapDriverRc(Driver, rc, error.DriverBindFailed);
            }
        }

        /// Binds a double to a 1-based parameter index.
        pub fn bindFloat(self: *Self, idx: i32, value: f64) errors.StmtError!void {
            try self.ensureOpen();
            const rc = Driver.stmt.bindDouble(self.stmt, idx, @as(f64, @floatCast(value)));
            if (rc != Driver.OK) {
                diag.logSqlite(Driver, self.db, rc, "driver_bind_double", null);
                diag.logBind("double", idx);
                return driver_errors.mapDriverRc(Driver, rc, error.DriverBindFailed);
            }
        }

        /// Binds a boolean to a 1-based parameter index.
        pub fn bindBool(self: *Self, idx: i32, value: bool) errors.StmtError!void {
            try self.ensureOpen();
            const rc = Driver.stmt.bindInt(self.stmt, idx, if (value) 1 else 0);
            if (rc != Driver.OK) {
                diag.logSqlite(Driver, self.db, rc, "driver_bind_int", null);
                diag.logBind("int", idx);
                return driver_errors.mapDriverRc(Driver, rc, error.DriverBindFailed);
            }
        }

        /// Binds a UTF-8 string to a 1-based parameter index.
        pub fn bindText(self: *Self, idx: i32, value: []const u8) errors.StmtError!void {
            try self.ensureOpen();
            const n: i32 = @intCast(value.len);
            const rc = Driver.stmt.bindText(self.stmt, idx, value.ptr, n);
            if (rc != Driver.OK) {
                diag.logSqlite(Driver, self.db, rc, "driver_bind_text", null);
                diag.logBind("text", idx);
                return driver_errors.mapDriverRc(Driver, rc, error.DriverBindFailed);
            }
        }

        /// Binds a blob to a 1-based parameter index.
        pub fn bindBlob(self: *Self, idx: i32, value: []const u8) errors.StmtError!void {
            try self.ensureOpen();
            const n: i32 = @intCast(value.len);
            const rc = Driver.stmt.bindBlob(self.stmt, idx, value.ptr, n);
            if (rc != Driver.OK) {
                diag.logSqlite(Driver, self.db, rc, "driver_bind_blob", null);
                diag.logBind("blob", idx);
                return driver_errors.mapDriverRc(Driver, rc, error.DriverBindFailed);
            }
        }

        /// General Binding: Supports int/uint/bool/float/enum/optional(?T)
        /// plus types.OwnedText/types.OwnedBlob and types.EpochMillis.
        /// For TEXT/BLOB, use Owned* types (borrowed slices are not accepted).
        pub fn bindOne(self: *Self, idx: i32, value: anytype) errors.StmtError!void {
            const T = @TypeOf(value);

            if (T == types.EpochMillis) {
                return self.bindInt(idx, value.value);
            }
            if (T == types.OwnedText) {
                return self.bindText(idx, value.value);
            }
            if (T == types.OwnedBlob) {
                return self.bindBlob(idx, value.value);
            }

            switch (@typeInfo(T)) {
                .optional => {
                    if (value == null) {
                        return self.bindNull(idx);
                    }
                    return self.bindOne(idx, value.?);
                },
                .bool => return self.bindBool(idx, value),
                .int, .comptime_int => return self.bindInt(idx, value),
                .float, .comptime_float => return self.bindFloat(idx, value),
                .@"enum" => return self.bindInt(idx, @as(i64, @intCast(@intFromEnum(value)))),
                .pointer, .array => return error.UnsupportedBindType,
                else => return error.UnsupportedBindType,
            }
        }

        /// Bind multiple parameters at once: params should be passed as a tuple (anonymous struct): .{ a, b, c }
        /// Rules:
        /// - Parameter indices start at 1 (SQLite convention)
        /// - Supports tuples / regular structs (field order matters)
        pub fn bindAll(self: *Self, params: anytype) errors.StmtError!void {
            const P = @TypeOf(params);
            const ti = @typeInfo(P);

            if (ti != .@"struct") {
                return error.BindAllExpectedStructOrTuple;
            }

            const s = ti.@"struct";
            inline for (s.fields, 0..) |f, i| {
                const v = @field(params, f.name);
                try self.bindOne(@as(i32, @intCast(i + 1)), v);
            }
        }

        // --------- column (0-based index, valid when step()==.row) ----------
        /// Reads an integer column value.
        pub fn colInt(self: *Self, col: i32) errors.RowReadError!i64 {
            try self.ensureOpen();
            return Driver.stmt.columnInt64(self.stmt, col);
        }

        /// Reads a boolean column value (0/1).
        pub fn colBool(self: *Self, col: i32) errors.RowReadError!bool {
            try self.ensureOpen();
            return Driver.stmt.columnInt(self.stmt, col) != 0;
        }

        /// Reads a double column value.
        pub fn colDouble(self: *Self, col: i32) errors.RowReadError!f64 {
            try self.ensureOpen();
            return Driver.stmt.columnDouble(self.stmt, col);
        }

        /// Returns true if the column is NULL.
        pub fn colIsNull(self: *Self, col: i32) errors.RowReadError!bool {
            try self.ensureOpen();
            return Driver.stmt.columnType(self.stmt, col) == Driver.NULL;
        }

        /// Returns an owned copy of TEXT data (caller frees with allocator).
        pub fn colTextOwned(self: *Self, a: std.mem.Allocator, col: i32) errors.RowReadError!?[]u8 {
            try self.ensureOpen();
            if (try self.colIsNull(col)) {
                return null;
            }

            const n = Driver.stmt.columnBytes(self.stmt, col);
            const len: usize = @intCast(n);
            if (len == 0) {
                return &.{};
            }

            const p = Driver.stmt.columnText(self.stmt, col) orelse return &.{};
            const src: [*]const u8 = @ptrCast(p);
            const out = try a.alloc(u8, len);
            if (len != 0) {
                std.mem.copyForwards(u8, out, src[0..len]);
            }
            return out;
        }

        /// Returns borrowed TEXT data without copying.
        /// The returned slice is valid only until the next step/reset/finalize.
        pub fn colTextBorrowed(self: *Self, col: i32) errors.RowReadError!?[]const u8 {
            if (try self.colIsNull(col)) {
                return null;
            }

            const n = Driver.stmt.columnBytes(self.stmt, col);
            const len: usize = @intCast(n);
            if (len == 0) {
                return &.{};
            }

            const p = Driver.stmt.columnText(self.stmt, col) orelse return &.{};
            const src: [*]const u8 = @ptrCast(p);
            return src[0..len];
        }

        /// Returns an owned copy of BLOB data (caller frees with allocator).
        pub fn colBlobOwned(self: *Self, a: std.mem.Allocator, col: i32) errors.RowReadError!?[]u8 {
            try self.ensureOpen();
            if (try self.colIsNull(col)) {
                return null;
            }

            const n = Driver.stmt.columnBytes(self.stmt, col);
            const len: usize = @intCast(n);
            if (len == 0) {
                return &.{};
            }

            const p = Driver.stmt.columnBlob(self.stmt, col) orelse return &.{};
            const src: [*]const u8 = @ptrCast(p);
            const out = try a.alloc(u8, len);
            if (len != 0) {
                std.mem.copyForwards(u8, out, src[0..len]);
            }
            return out;
        }

        /// Returns borrowed BLOB data without copying.
        /// The returned slice is valid only until the next step/reset/finalize.
        pub fn colBlobBorrowed(self: *Self, col: i32) errors.RowReadError!?[]const u8 {
            if (try self.colIsNull(col)) {
                return null;
            }

            const n = Driver.stmt.columnBytes(self.stmt, col);
            const len: usize = @intCast(n);
            if (len == 0) {
                return &.{};
            }

            const p = Driver.stmt.columnBlob(self.stmt, col) orelse return &.{};
            const src: [*]const u8 = @ptrCast(p);
            return src[0..len];
        }

        fn ensureOpen(self: *const Self) errors.StmtError!void {
            if (self.finalized) {
                return error.StatementFinalized;
            }
        }
    };
}

test "stmt: bindInt and reset" {
    const Driver = @import("../driver/sqlite3.zig");
    const DbT = @import("db.zig").Db(Driver);
    const StmtT = Stmt(Driver);
    const a = std.testing.allocator;
    var db = try DbT.open(a, ":memory:");
    defer db.deinit();

    var st = try StmtT.init(&db, "SELECT ?1;");
    defer st.deinit();

    try st.bindInt(1, 1);
    try std.testing.expectEqual(StepResult.row, try st.step());
    try std.testing.expect(try st.colBool(0));
    try std.testing.expectEqual(StepResult.done, try st.step());

    try st.reset();
    try st.bindInt(1, 0);
    try std.testing.expectEqual(StepResult.row, try st.step());
    try std.testing.expect(!(try st.colBool(0)));
    try std.testing.expectEqual(StepResult.done, try st.step());
}

test "stmt: bindAll requires struct/tuple" {
    const Driver = @import("../driver/sqlite3.zig");
    const DbT = @import("db.zig").Db(Driver);
    const StmtT = Stmt(Driver);
    const a = std.testing.allocator;
    var db = try DbT.open(a, ":memory:");
    defer db.deinit();

    var st = try StmtT.init(&db, "SELECT ?1;");
    defer st.deinit();

    try std.testing.expectError(error.BindAllExpectedStructOrTuple, st.bindAll(@as(i64, 1)));
}

test "stmt: bindOne supports OwnedText/OwnedBlob/EpochMillis/optional" {
    const Driver = @import("../driver/sqlite3.zig");
    const DbT = @import("db.zig").Db(Driver);
    const StmtT = Stmt(Driver);
    const a = std.testing.allocator;
    var db = try DbT.open(a, ":memory:");
    defer db.deinit();

    var st = try StmtT.init(&db, "SELECT ?1, ?2, ?3, ?4;");
    defer st.deinit();

    var text = try types.OwnedText.fromConst(a, "zig");
    defer text.deinit(a);
    var blob = try types.OwnedBlob.fromConst(a, &[_]u8{ 1, 2 });
    defer blob.deinit(a);

    try st.bindOne(1, text);
    try st.bindOne(2, blob);
    try st.bindOne(3, types.EpochMillis{ .value = 123 });
    try st.bindOne(4, @as(?i64, null));

    try std.testing.expectEqual(StepResult.row, try st.step());
    const got_text = (try st.colTextOwned(a, 0)).?;
    defer a.free(got_text);
    try std.testing.expectEqualStrings("zig", got_text);

    const got_blob = (try st.colBlobOwned(a, 1)).?;
    defer a.free(got_blob);
    try std.testing.expect(std.mem.eql(u8, &[_]u8{ 1, 2 }, got_blob));

    try std.testing.expectEqual(@as(i64, 123), try st.colInt(2));
    try std.testing.expect(try st.colIsNull(3));
    try std.testing.expectEqual(StepResult.done, try st.step());
}

test "stmt: bindText/blob and colTextOwned/colBlobOwned on empty" {
    const Driver = @import("../driver/sqlite3.zig");
    const DbT = @import("db.zig").Db(Driver);
    const StmtT = Stmt(Driver);
    const a = std.testing.allocator;
    var db = try DbT.open(a, ":memory:");
    defer db.deinit();

    var st = try StmtT.init(&db, "SELECT ?1, ?2;");
    defer st.deinit();

    try st.bindText(1, "");
    try st.bindBlob(2, &.{});

    try std.testing.expectEqual(StepResult.row, try st.step());
    const t = (try st.colTextOwned(a, 0)).?;
    defer a.free(t);
    try std.testing.expectEqual(@as(usize, 0), t.len);

    const b_opt = try st.colBlobOwned(a, 1);
    if (b_opt) |b| {
        defer a.free(b);
        try std.testing.expectEqual(@as(usize, 0), b.len);
    }
    try std.testing.expectEqual(StepResult.done, try st.step());
}

test "stmt: colTextOwned/colBlobOwned propagate OutOfMemory" {
    const Driver = @import("../driver/sqlite3.zig");
    const DbT = @import("db.zig").Db(Driver);
    const StmtT = Stmt(Driver);
    const a = std.testing.allocator;
    var db = try DbT.open(a, ":memory:");
    defer db.deinit();

    var st = try StmtT.init(&db, "SELECT ?1, ?2;");
    defer st.deinit();
    try st.bindText(1, "abc");
    try st.bindBlob(2, &[_]u8{ 1, 2, 3 });

    try std.testing.expectEqual(StepResult.row, try st.step());

    var fail_text_state = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    try std.testing.expectError(
        error.OutOfMemory,
        st.colTextOwned(fail_text_state.allocator(), 0),
    );

    var fail_blob_state = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    try std.testing.expectError(
        error.OutOfMemory,
        st.colBlobOwned(fail_blob_state.allocator(), 1),
    );
}

test "stmt: colTextBorrowed/colBlobBorrowed zero-copy reads" {
    const Driver = @import("../driver/sqlite3.zig");
    const DbT = @import("db.zig").Db(Driver);
    const StmtT = Stmt(Driver);
    const a = std.testing.allocator;
    var db = try DbT.open(a, ":memory:");
    defer db.deinit();

    var st = try StmtT.init(&db, "SELECT ?1, ?2, ?3, ?4;");
    defer st.deinit();
    try st.bindText(1, "abc");
    try st.bindBlob(2, &[_]u8{ 7, 8, 9 });
    try st.bindText(3, "");
    try st.bindNull(4);

    try std.testing.expectEqual(StepResult.row, try st.step());

    const t = (try st.colTextBorrowed(0)).?;
    try std.testing.expectEqualStrings("abc", t);
    const b = (try st.colBlobBorrowed(1)).?;
    try std.testing.expect(std.mem.eql(u8, &[_]u8{ 7, 8, 9 }, b));
    try std.testing.expectEqual(@as(usize, 0), (try st.colTextBorrowed(2)).?.len);
    try std.testing.expect((try st.colBlobBorrowed(3)) == null);
}

test "stmt: operations after deinit return StatementFinalized" {
    const Driver = @import("../driver/sqlite3.zig");
    const DbT = @import("db.zig").Db(Driver);
    const StmtT = Stmt(Driver);
    const a = std.testing.allocator;
    var db = try DbT.open(a, ":memory:");
    defer db.deinit();

    var st = try StmtT.init(&db, "SELECT 1;");
    st.deinit();

    try std.testing.expectError(error.StatementFinalized, st.step());
    try std.testing.expectError(error.StatementFinalized, st.reset());
    try std.testing.expectError(error.StatementFinalized, st.bindInt(1, 1));
    try std.testing.expectError(error.StatementFinalized, st.colInt(0));
    try std.testing.expectError(error.StatementFinalized, st.colTextBorrowed(0));
}
