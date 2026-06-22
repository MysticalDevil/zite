const std = @import("std");
const Driver = @import("../driver/sqlite3.zig");
const Stmt = @import("../db/stmt.zig").Stmt(Driver);
const meta = @import("../core/meta.zig");
const errors = @import("../core/errors.zig");
const reflect = @import("../core/reflect.zig");
const engine = @import("engine.zig");

pub fn RowView(comptime T: type) type {
    return struct {
        owner: *RowCursor(T),
        row_generation: usize,

        pub const __zite_async_guard: void = {};

        const Self = @This();
        const m = meta.getMeta(T);

        pub fn get(self: Self, comptime field: []const u8) errors.RowReadError!ViewFieldType(T, field) {
            try self.owner.ensureRowAlive(self.row_generation);
            const col = comptime fieldColumnIndex(field);
            const FieldT = comptime fieldType(field);
            return engine.row.readValueView(FieldT, &self.owner.st, @as(i32, @intCast(col)));
        }

        fn fieldType(comptime field: []const u8) type {
            const ti = @typeInfo(T);
            if (ti != .@"struct") {
                @compileError("RowView requires a struct model");
            }

            inline for (comptime reflect.structFields(T)) |f| {
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
                @compileError("RowView requires a struct model");
            }

            comptime var col: usize = 0;
            inline for (comptime reflect.structFields(T)) |f| {
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

pub fn ViewFieldType(comptime T: type, comptime field: []const u8) type {
    const m = meta.getMeta(T);
    const ti = @typeInfo(T);
    if (ti != .@"struct") {
        @compileError("ViewFieldType requires a struct model");
    }

    inline for (comptime reflect.structFields(T)) |f| {
        if (comptime std.mem.eql(u8, f.name, field)) {
            if (comptime meta.isSkipped(f.name, m)) {
                @compileError("Field " ++ field ++ " is skipped in Meta");
            }
            return engine.row.ViewFieldType(f.type);
        }
    }
    @compileError("Unknown field for " ++ @typeName(T) ++ ": " ++ field);
}

pub fn RowHandle(comptime T: type) type {
    return struct {
        rows: RowCursor(T),
        row_generation: usize,

        pub const __zite_async_guard: void = {};

        const Self = @This();

        pub fn get(self: *Self, comptime field: []const u8) errors.RowReadError!ViewFieldType(T, field) {
            return (RowView(T){
                .owner = &self.rows,
                .row_generation = self.row_generation,
            }).get(field);
        }

        pub fn deinit(self: *Self) void {
            self.rows.deinit();
        }
    };
}

pub fn RowCursor(comptime T: type) type {
    return struct {
        st: Stmt,
        done: bool = false,
        cursor_generation: usize = 0,

        pub const __zite_async_guard: void = {};

        const Self = @This();

        pub fn deinit(self: *Self) void {
            self.closeAndInvalidate();
        }

        pub fn next(self: *Self) errors.RowReadError!?RowView(T) {
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

        fn ensureRowAlive(self: *const Self, row_generation: usize) errors.RowReadError!void {
            if (self.st.isFinalized()) {
                return error.StatementFinalized;
            }
            if (self.cursor_generation != row_generation) {
                return error.RowViewStale;
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
