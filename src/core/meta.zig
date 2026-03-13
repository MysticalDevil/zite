const std = @import("std");

/// Declarative metadata for ORM mapping.
pub const Meta = struct {
    /// Table name.
    table: []const u8,
    /// Primary key field name.
    primary_key: []const u8 = "id",
    /// When true, omit PK from INSERTs (for AUTOINCREMENT).
    skip_primary_key_on_insert: bool = true,
    /// Field names to skip from mapping.
    skip: []const []const u8 = &.{},
    /// Field-to-column renames.
    rename: []const Rename = &.{},
    /// Unique constraints (each entry is a list of field names).
    unique: []const []const []const u8 = &.{},
    /// Default ORDER BY clause used by findMany.
    order_by: []const u8 = "",
};

/// Field rename mapping.
pub const Rename = struct {
    /// Struct field name.
    field: []const u8,
    /// Column name in database.
    column: []const u8,
};

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r';
}

fn skipSpaces(s: []const u8, i: *usize) void {
    while (i.* < s.len and isSpace(s[i.*])) : (i.* += 1) {}
}

fn parseQuotedIdent(s: []const u8, i: *usize) bool {
    if (i.* >= s.len or s[i.*] != '"') {
        return false;
    }
    i.* += 1;
    while (i.* < s.len) {
        if (s[i.*] != '"') {
            i.* += 1;
            continue;
        }
        if (i.* + 1 < s.len and s[i.* + 1] == '"') {
            i.* += 2;
            continue;
        }
        i.* += 1;
        return true;
    }
    return false;
}

fn asciiEqIgnoreCase(a: u8, b: u8) bool {
    if (a == b) return true;
    const la = if (a >= 'A' and a <= 'Z') a + 32 else a;
    const lb = if (b >= 'A' and b <= 'Z') b + 32 else b;
    return la == lb;
}

fn parseKeywordIgnoreCase(s: []const u8, i: *usize, kw: []const u8) bool {
    if (i.* + kw.len > s.len) return false;
    for (kw, 0..) |k, off| {
        if (!asciiEqIgnoreCase(s[i.* + off], k)) return false;
    }
    i.* += kw.len;
    return true;
}

fn isValidOrderByClauseList(order_by: []const u8) bool {
    var i: usize = 0;
    skipSpaces(order_by, &i);
    if (i == order_by.len) return true;

    while (true) {
        if (!parseQuotedIdent(order_by, &i)) return false;

        // Require at least one whitespace between identifier and direction.
        if (i >= order_by.len or !isSpace(order_by[i])) return false;
        skipSpaces(order_by, &i);

        const dir_start = i;
        if (!parseKeywordIgnoreCase(order_by, &i, "ASC") and !parseKeywordIgnoreCase(order_by, &i, "DESC")) {
            return false;
        }
        if (i == dir_start) return false;

        skipSpaces(order_by, &i);
        if (i == order_by.len) return true;
        if (order_by[i] != ',') return false;
        i += 1;
        skipSpaces(order_by, &i);
        if (i == order_by.len) return false;
    }
}

/// Returns true when the field name matches the primary key.
pub fn isPk(comptime name: []const u8, comptime pk: []const u8) bool {
    return std.mem.eql(u8, name, pk);
}

/// Reads Meta from a struct type, with defaults.
pub fn getMeta(comptime T: type) Meta {
    if (!@hasDecl(T, "Meta")) {
        @compileError("Type" ++ @typeName(T) ++ " must declare `pub const Meta = .{ .table = \"...\"}`");
    }

    const m = T.Meta;
    const MT = @TypeOf(m);

    if (!@hasField(MT, "table")) {
        @compileError("Type" ++ @typeName(T) ++ " Meta must contain field `.table`");
    }

    const table: []const u8 = m.table;
    const pk: []const u8 = if (@hasField(MT, "primary_key")) m.primary_key else "id";
    const skip_pk: bool = if (@hasField(MT, "skip_primary_key_on_insert")) m.skip_primary_key_on_insert else true;
    const skip: []const []const u8 = if (@hasField(MT, "skip")) m.skip else &.{};
    const rename: []const Rename = if (@hasField(MT, "rename")) m.rename else &.{};
    const unique: []const []const []const u8 = if (@hasField(MT, "unique")) m.unique else &.{};
    const order_by: []const u8 = if (@hasField(MT, "order_by")) m.order_by else "";

    comptime {
        if (!isValidOrderByClauseList(order_by)) {
            @compileError(
                "Type " ++ @typeName(T) ++ " Meta.order_by must be in form " ++
                    "\"\\\"col\\\" ASC|DESC[, ...]\"",
            );
        }
    }

    return .{
        .table = table,
        .primary_key = pk,
        .skip_primary_key_on_insert = skip_pk,
        .skip = skip,
        .rename = rename,
        .unique = unique,
        .order_by = order_by,
    };
}

/// True if the type defines a field matching the primary key.
pub fn hasPrimaryKeyField(comptime T: type, comptime m: Meta) bool {
    const ti = @typeInfo(T);
    if (ti != .@"struct") {
        @compileError("hasPrimaryKeyField expects a struct type");
    }
    const fields = ti.@"struct".fields;

    inline for (fields) |f| {
        if (comptime isPk(f.name, m.primary_key)) {
            return true;
        }
    }
    return false;
}

/// Returns true if the field is marked as skipped.
pub fn isSkipped(comptime name: []const u8, comptime m: Meta) bool {
    inline for (m.skip) |s| {
        if (comptime std.mem.eql(u8, name, s)) {
            return true;
        }
    }
    return false;
}

/// Returns column name for a field, honoring renames.
pub fn columnName(comptime name: []const u8, comptime m: Meta) []const u8 {
    inline for (m.rename) |r| {
        if (comptime std.mem.eql(u8, name, r.field)) {
            return r.column;
        }
    }
    return name;
}

/// Returns the column name for the primary key field.
pub fn pkColumnName(comptime m: Meta) []const u8 {
    return columnName(m.primary_key, m);
}

/// Number of fields insertable for the given Meta.
pub fn insertableCount(comptime T: type, comptime m: Meta) usize {
    const ti = @typeInfo(T);
    if (ti != .@"struct") {
        @compileError("insertableCount expects a struct type");
    }
    const fields = ti.@"struct".fields;

    comptime var n: usize = 0;
    inline for (fields) |f| {
        if (comptime isSkipped(f.name, m)) {
            continue;
        }
        const skip = comptime (m.skip_primary_key_on_insert and isPk(f.name, m.primary_key));
        if (!skip) {
            n += 1;
        }
    }
    return n;
}

/// Number of fields included in UPDATE SET clause.
pub fn updateSetCount(comptime T: type, comptime m: Meta) usize {
    const ti = @typeInfo(T);
    if (ti != .@"struct") {
        @compileError("updateSetCount expects a struct type");
    }
    const fields = ti.@"struct".fields;

    comptime var n: usize = 0;
    inline for (fields) |f| {
        if (comptime isSkipped(f.name, m)) {
            continue;
        }
        if (comptime isPk(f.name, m.primary_key)) {
            continue;
        }
        n += 1;
    }
    return n;
}

test "meta: getMeta defaults and overrides" {
    const A = struct {
        id: i64,
        name: i64,

        pub const Meta = .{
            .table = "items",
        };
    };
    const B = struct {
        id: i64,
        name: i64,
        skip_me: i64,

        pub const Meta = .{
            .table = "users",
            .primary_key = "id",
            .skip_primary_key_on_insert = false,
            .skip = &.{"skip_me"},
            .rename = &[_]Rename{
                .{ .field = "name", .column = "full_name" },
            },
            .unique = &.{
                &.{"name"},
            },
            .order_by = "\"id\" DESC",
        };
    };

    const ma = comptime getMeta(A);
    try std.testing.expectEqualStrings("items", ma.table);
    try std.testing.expectEqualStrings("id", ma.primary_key);
    try std.testing.expect(ma.skip_primary_key_on_insert);
    try std.testing.expectEqual(@as(usize, 0), ma.skip.len);
    try std.testing.expectEqual(@as(usize, 0), ma.rename.len);
    try std.testing.expectEqual(@as(usize, 0), ma.unique.len);

    const mb = comptime getMeta(B);
    try std.testing.expectEqualStrings("users", mb.table);
    try std.testing.expectEqualStrings("id", mb.primary_key);
    try std.testing.expect(!mb.skip_primary_key_on_insert);
    try std.testing.expectEqual(@as(usize, 1), mb.skip.len);
    try std.testing.expectEqual(@as(usize, 1), mb.rename.len);
    try std.testing.expectEqual(@as(usize, 1), mb.unique.len);
    try std.testing.expectEqualStrings("\"id\" DESC", mb.order_by);
}

test "meta: columnName, pkColumnName, isSkipped" {
    const S = struct {
        id: i64,
        name: i64,
        skip_me: i64,

        pub const Meta = .{
            .table = "t",
            .primary_key = "id",
            .skip = &.{"skip_me"},
            .rename = &[_]Rename{
                .{ .field = "name", .column = "full_name" },
            },
        };
    };

    const m = comptime getMeta(S);
    try std.testing.expectEqualStrings("full_name", columnName("name", m));
    try std.testing.expectEqualStrings("id", pkColumnName(m));
    try std.testing.expect(isSkipped("skip_me", m));
    try std.testing.expect(!isSkipped("name", m));
}

test "meta: insertableCount/updateSetCount/hasPrimaryKeyField" {
    const S = struct {
        id: i64,
        name: i64,
        skip_me: i64,

        pub const Meta = .{
            .table = "t",
            .primary_key = "id",
            .skip_primary_key_on_insert = true,
            .skip = &.{"skip_me"},
        };
    };

    const m = comptime getMeta(S);
    try std.testing.expect(hasPrimaryKeyField(S, m));
    try std.testing.expectEqual(@as(usize, 1), insertableCount(S, m));
    try std.testing.expectEqual(@as(usize, 1), updateSetCount(S, m));
}

test "meta: order_by validator accepts expected forms" {
    try std.testing.expect(isValidOrderByClauseList(""));
    try std.testing.expect(isValidOrderByClauseList("\"id\" DESC"));
    try std.testing.expect(isValidOrderByClauseList("\"id\" ASC, \"created_at\" DESC"));
    try std.testing.expect(isValidOrderByClauseList("  \"id\" ASC  ,  \"name\" DESC "));
}

test "meta: order_by validator rejects invalid forms" {
    try std.testing.expect(!isValidOrderByClauseList("id DESC"));
    try std.testing.expect(!isValidOrderByClauseList("\"id\""));
    try std.testing.expect(!isValidOrderByClauseList("\"id\" DOWN"));
    try std.testing.expect(!isValidOrderByClauseList("\"id\" ASC,"));
    try std.testing.expect(!isValidOrderByClauseList("\"id\"ASC"));
}
