const std = @import("std");
const db_mod = @import("db.zig");
const root = @import("root.zig");

pub const c = db_mod.c;
pub const Db = db_mod.Db;
const db_ok = c.SQLITE_OK;
const types = root.types;

pub const StepResult = enum { row, done };

/// sqlite3_bind_text/blob destructor parameters:
/// SQLITE_TRANSIENT == (sqlite3_destructor_type)-1 => SQLite will copy the data
const SQLITE_TRANSIENT: c.sqlite3_destructor_type = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

pub const Stmt = struct {
    db: *Db,
    stmt: *c.sqlite3_stmt,

    const Self = @This();

    pub fn init(db: *Db, sql: []const u8) !Self {
        var stmt_opt: ?*c.sqlite3_stmt = null;

        const n: c_int = @intCast(sql.len);
        const rc = c.sqlite3_prepare_v2(
            db.handle,
            sql.ptr,
            n,
            &stmt_opt,
            null,
        );
        if (rc != db_ok or stmt_opt == null)
            return error.SqlitePrepareFailed;

        return .{ .db = db, .stmt = stmt_opt.? };
    }

    pub fn finalize(self: *Self) void {
        _ = c.sqlite3_finalize(self.stmt);
    }

    pub fn deinit(self: *Self) void {
        self.finalize();
    }

    pub fn reset(self: *Self) !void {
        const rc = c.sqlite3_reset(self.stmt);
        if (rc != db_ok)
            return error.SqliteResetFailed;
    }

    pub fn clearbindings(self: *Self) !void {
        const rc = c.sqlite3_clear_bindings(self.stmt);
        if (rc != db_ok)
            return error.SqliteClearBindingsFailed;
    }

    pub fn step(self: *Stmt) !StepResult {
        const rc = c.sqlite3_step(self.stmt);
        return switch (rc) {
            c.SQLITE_ROW => .row,
            c.SQLITE_DONE => .done,
            else => error.SqliteStepFailed,
        };
    }

    // ---------- bind (1-based index) ----------
    pub fn bindNull(self: *Self, idx: c_int) !void {
        const rc = c.sqlite3_bind_null(self.stmt, idx);
        if (rc != db_ok)
            return error.SqliteBindFailed;
    }

    pub fn bindInt(self: *Self, idx: c_int, value: i64) !void {
        const rc = c.sqlite3_bind_int64(self.stmt, idx, value);
        if (rc != db_ok)
            return error.SqliteBindFailed;
    }

    pub fn bindFloat(self: *Self, idx: c_int, value: i64) !void {
        const rc = c.sqlite3_bind_double(self.stmt, idx, @as(f64, @floatCast(value)));
        if (rc != db_ok)
            return error.SqliteBindFailed;
    }

    pub fn bindBool(self: *Self, idx: c_int, value: bool) !void {
        const rc = c.sqlite3_bind_int(self.stmt, idx, if (value) 1 else 0);
        if (rc != db_ok)
            return error.SqliteBindFailed;
    }

    pub fn bindText(self: *Self, idx: c_int, value: []const u8) !void {
        const n: c_int = @intCast(value.len);
        const rc = c.sqlite3_bind_text(self.stmt, idx, value.ptr, n, SQLITE_TRANSIENT);
        if (rc != db_ok)
            return error.SqliteBindFailed;
    }

    pub fn bindBlob(self: *Self, idx: c_int, value: []const u8) !void {
        const n: c_int = @intCast(value.len);
        const rc = c.sqlite3_bind_blob(self.stmt, idx, value.ptr, n, SQLITE_TRANSIENT);
        if (rc != db_ok)
            return error.SqliteBindFailed;
    }

    /// General Binding: Supports int/uint/bool/float/enum/[]const u8/[]u8/optional(?T)
    pub fn bindOne(self: *Self, idx: c_int, value: anytype) !void {
        const T = @TypeOf(value);

        if (T == types.UnixMillis) {
            return self.bindInt(idx, value.value);
        }

        switch (@typeInfo(T)) {
            .optional => |_| {
                if (value == null)
                    return self.bindNull(idx);
                return self.bindOne(idx, value.?);
            },
            .bool => return self.bindBool(idx, value),
            .int, .comptime_int => return self.bindInt(idx, value),
            .float, .comptime_float => return self.bindFloat(idx, value),
            .@"enum" => return self.bindInt(idx, @as(i64, @intCast(@intFromEnum(value)))),
            .pointer => |p| {
                switch (p.size) {
                    .slice => if (p.child == u8) return self.bindText(idx, value),
                    .one => {
                        const child_info = @typeInfo(p.child);
                        if (child_info == .array and child_info.array.child == u8) {
                            const arr = value.*;
                            return self.bindText(idx, arr[0..]);
                        }
                    },
                    .many, .c => {
                        if (p.child == u8 and p.sentinel != null) {
                            const s = std.mem.sliceTo(value, 0);
                            return self.bindText(idx, s);
                        }
                    },
                }
                return error.UnsupportedBindType;
            },
            .array => |a| {
                if (a.child == u8)
                    return self.bindBlob(idx, value[0..]);
                return error.UnsupportedBindType;
            },
            else => return error.UnsupportedBindType,
        }
    }

    /// Bind multiple parameters at once: params should be passed as a tuple (anonymous struct): .{ a, b, c }
    /// Rules:
    /// - Parameter indices start at 1 (SQLite convention)
    /// - Supports tuples / regular structs (field order matters)
    pub fn bindAll(self: *Self, params: anytype) !void {
        const P = @TypeOf(params);
        const ti = @typeInfo(P);

        if (ti != .@"struct")
            return error.BindAllExpecteStructOrTuple;

        const s = ti.@"struct";
        inline for (s.fields, 0..) |f, i| {
            const v = @field(params, f.name);
            try self.bindOne(@as(c_int, @intCast(i + 1)), v);
        }
    }

    // --------- column (0-based index, valid when setp()==.row) ----------
    pub fn colInt(self: *Self, col: c_int) i64 {
        return c.sqlite3_column_int64(self.stmt, col);
    }

    pub fn colBool(self: *Self, col: c_int) bool {
        return c.sqlite3_column_int(self.stmt, col) != 0;
    }

    pub fn colDouble(self: *Stmt, col: c_int) f64 {
        return c.sqlite3_column_double(self.stmt, col);
    }

    /// NOTE: The returned slice points to an internal SQLite buffer; it may become invalid after the next step/reset/finalize operation.
    pub fn colText(self: *Self, col: c_int) ?[]const u8 {
        const p = c.sqlite3_column_text(self.stmt, col);
        if (p == null)
            return null;
        const n = c.sqlite3_column_bytes(self.stmt, col);
        const len: usize = @intCast(n);
        const bytes: [*]const u8 = @ptrCast(p);
        return bytes[0..len];
    }

    pub fn colBlob(self: *Self, col: c_int) ?[]const u8 {
        const p = c.sqlite3_column_blob(self.stmt, col);
        if (p == null)
            return null;
        const n = c.sqlite3_column_bytes(self.stmt, col);
        const len: usize = @intCast(n);
        const bytes: [*]const u8 = @ptrCast(p);
        return bytes[0..len];
    }

    pub fn colIsNull(self: *Self, col: c_int) bool {
        return c.sqlite3_column_type(self.stmt, col) == c.SQLITE_NULL;
    }

    pub fn colTextOwned(self: *Self, a: std.mem.Allocator, col: c_int) !?[]u8 {
        const p = c.sqlite3_column_text(self.stmt, col);
        if (p == null) return null;

        const n = c.sqlite3_column_bytes(self.stmt, col);
        const len: usize = @intCast(n);

        const src: [*]const u8 = @ptrCast(p);
        const out = try a.alloc(u8, len);
        if (len != 0) std.mem.copyForwards(u8, out, src[0..len]);
        return out;
    }
};
