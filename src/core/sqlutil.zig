const std = @import("std");
const meta = @import("meta.zig");
const errors = @import("errors.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList(u8);

/// Helper for building SQL strings with fewer reallocations.
pub const SqlBuilder = struct {
    /// Target buffer to append into.
    list: *ArrayList,
    /// Allocator used by the underlying ArrayList.
    gpa: Allocator,

    /// Initializes a builder that appends into the provided ArrayList.
    pub fn init(list: *ArrayList, gpa: Allocator) SqlBuilder {
        return .{ .list = list, .gpa = gpa };
    }

    /// Reserves additional capacity to reduce reallocations.
    pub fn reserve(self: *SqlBuilder, extra: usize) errors.ZiteError!void {
        try self.list.ensureUnusedCapacity(self.gpa, extra);
    }

    /// Appends a literal SQL fragment.
    pub fn lit(self: *SqlBuilder, s: []const u8) errors.ZiteError!void {
        try self.list.appendSlice(self.gpa, s);
    }

    /// Appends a single byte.
    pub fn byte(self: *SqlBuilder, b: u8) errors.ZiteError!void {
        try self.list.append(self.gpa, b);
    }

    /// Appends formatted text.
    pub fn print(self: *SqlBuilder, comptime fmt: []const u8, args: anytype) errors.ZiteError!void {
        try self.list.print(self.gpa, fmt, args);
    }

    /// Appends an escaped SQL identifier.
    pub fn ident(self: *SqlBuilder, name: []const u8) errors.ZiteError!void {
        try writeIdent(self.list, self.gpa, name);
    }

    /// Appends numbered placeholders (?1, ?2, ...).
    pub fn placeholders(self: *SqlBuilder, comptime count: usize) errors.ZiteError!void {
        try writePlaceholders(self.list, self.gpa, count);
    }

    /// Appends insertable column list (skipping PK when configured).
    pub fn insertColumnList(self: *SqlBuilder, comptime T: type, comptime m: meta.Meta) errors.ZiteError!void {
        try writeInsertColumnList(self.list, self.gpa, T, m);
    }

    /// Appends "col1=?1, col2=?2, ..." update set clause.
    pub fn updateSetClause(self: *SqlBuilder, comptime T: type, comptime m: meta.Meta) errors.ZiteError!void {
        try writeUpdateSetClause(self.list, self.gpa, T, m);
    }
};

/// Writes a quoted SQL identifier, escaping embedded quotes.
pub fn writeIdent(list: *ArrayList, gpa: Allocator, name: []const u8) errors.ZiteError!void {
    try list.append(gpa, '"');
    for (name) |ch| {
        if (ch == '"') {
            try list.appendSlice(gpa, "\"\"");
        } else {
            try list.append(gpa, ch);
        }
    }
    try list.append(gpa, '"');
}

/// Writes numbered placeholders (?1, ?2, ...).
pub fn writePlaceholders(list: *ArrayList, gpa: Allocator, comptime count: usize) errors.ZiteError!void {
    comptime var i: usize = 1;
    inline while (i <= count) : (i += 1) {
        if (i != 1) try list.appendSlice(gpa, ", ");
        try list.append(gpa, '?');
        try list.print(gpa, "{}", .{i});
    }
}

/// Writes insertable column list for T, skipping PK if configured.
pub fn writeInsertColumnList(list: *ArrayList, gpa: Allocator, comptime T: type, comptime m: meta.Meta) errors.ZiteError!void {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("writeInsertColumnList expects a struct type");
    const fields = ti.@"struct".fields;

    comptime var col_i: usize = 0;
    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) continue;
        const skip = comptime (m.skip_primary_key_on_insert and meta.isPk(f.name, m.primary_key));
        if (skip) continue;

        if (col_i != 0) try list.appendSlice(gpa, ", ");
        try writeIdent(list, gpa, meta.columnName(f.name, m));
        col_i += 1;
    }
}

/// Writes UPDATE SET clause for T (excluding PK).
pub fn writeUpdateSetClause(list: *ArrayList, gpa: Allocator, comptime T: type, comptime m: meta.Meta) errors.ZiteError!void {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("writeUpdateSetClause expects a struct type");
    const fields = ti.@"struct".fields;

    comptime var set_i: usize = 0;
    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) continue;
        if (comptime meta.isPk(f.name, m.primary_key)) continue;

        if (set_i != 0) try list.appendSlice(gpa, ", ");
        try writeIdent(list, gpa, meta.columnName(f.name, m));
        try list.appendSlice(gpa, "=?");
        try list.print(gpa, "{}", .{set_i + 1});
        set_i += 1;
    }
}

fn fieldNameLen(comptime T: type) usize {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("fieldNameLen expects a struct type");
    const fields = ti.@"struct".fields;
    comptime var total: usize = 0;
    inline for (fields) |f| total += f.name.len;
    return total;
}

/// Estimates SQL length for INSERT statements of T.
pub fn estInsertLen(comptime T: type, comptime m: meta.Meta) usize {
    const field_count = @typeInfo(T).@"struct".fields.len;
    const col_count = comptime meta.insertableCount(T, m);
    const names_len = comptime fieldNameLen(T);
    const base = "INSERT INTO ".len + m.table.len + " (".len + ") VALUES (".len + ");".len;
    const name_quotes = col_count * 2;
    const separators = if (col_count > 0) (col_count - 1) * ", ".len else 0;
    const placeholders = col_count * 2;
    return base + names_len + name_quotes + separators + placeholders + field_count;
}

/// Estimates SQL length for UPDATE statements of T.
pub fn estUpdateLen(comptime T: type, comptime m: meta.Meta) usize {
    const field_count = @typeInfo(T).@"struct".fields.len;
    const set_count = comptime meta.updateSetCount(T, m);
    const names_len = comptime fieldNameLen(T);
    const base = "UPDATE ".len + m.table.len + " SET ".len + " WHERE ".len + m.primary_key.len + "=?".len + ";".len;
    const name_quotes = field_count * 2;
    const separators = if (set_count > 0) (set_count - 1) * ", ".len else 0;
    const placeholders = set_count * 2 + 2;
    return base + names_len + name_quotes + separators + placeholders + field_count;
}

/// Estimates SQL length for SELECT statements of T.
pub fn estSelectLen(comptime T: type, comptime m: meta.Meta, where_len: usize, limit_one: bool) usize {
    const fields = @typeInfo(T).@"struct".fields;
    const names_len = comptime fieldNameLen(T);
    const base = "SELECT ".len + " FROM ".len + m.table.len + ";".len;
    const name_quotes = fields.len * 2;
    const separators = if (fields.len > 0) (fields.len - 1) * ", ".len else 0;
    const where_part = if (where_len > 0) " WHERE ".len + where_len else 0;
    const limit_part = if (limit_one) " LIMIT 1".len else 0;
    return base + names_len + name_quotes + separators + where_part + limit_part;
}

/// Estimates SQL length for CREATE TABLE statements of T.
pub fn estCreateTableLen(comptime T: type, table_name: []const u8) usize {
    const names_len = comptime fieldNameLen(T);
    const field_count = @typeInfo(T).@"struct".fields.len;
    const base = "CREATE TABLE ".len + " (".len + ");".len + table_name.len;
    const name_quotes = field_count * 2;
    const separators = if (field_count > 0) (field_count - 1) * ",\n".len else 0;
    const per_field_overhead = field_count * ("  ".len + " ".len + " NOT NULL".len + " PRIMARY KEY".len);
    return base + names_len + name_quotes + separators + per_field_overhead;
}

test "sqlutil insert/update clauses honor meta" {
    const Sample = struct {
        id: i64,
        name: i64,
        skip_me: i64,

        pub const Meta = .{
            .table = "samples",
            .primary_key = "id",
            .skip_primary_key_on_insert = true,
            .skip = &.{ "skip_me" },
            .rename = &.{
                .{ .field = "name", .column = "full_name" },
            },
        };
    };

    const gpa = std.testing.allocator;
    const m = meta.getMeta(Sample);

    var insert_buf: ArrayList = .empty;
    defer insert_buf.deinit(gpa);
    var insert_builder = SqlBuilder.init(&insert_buf, gpa);
    try insert_builder.insertColumnList(Sample, m);
    try std.testing.expectEqualStrings("\"full_name\"", insert_buf.items);

    var update_buf: ArrayList = .empty;
    defer update_buf.deinit(gpa);
    var update_builder = SqlBuilder.init(&update_buf, gpa);
    try update_builder.updateSetClause(Sample, m);
    try std.testing.expectEqualStrings("\"full_name\"=?1", update_buf.items);
}
