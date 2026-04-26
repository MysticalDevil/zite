const std = @import("std");
const errors = @import("../core/errors.zig");

pub const SqlScanState = enum {
    code,
    single_quote,
    double_quote,
    line_comment,
    block_comment,
};

/// Validates that a raw SQL WHERE fragment does not contain unsafe constructs.
/// Blocks statement separators, comments, and dangerous standalone keywords.
/// Identifiers that merely contain a keyword (e.g. `select_count`) are safe
/// because the scanner checks whole-word equality.
pub fn validateWhereRawFragment(sql: []const u8) errors.OrmError!void {
    for (sql) |ch| {
        if (ch == 0) {
            return error.UnsafeSqlFragment;
        }
    }

    var state: SqlScanState = .code;
    var i: usize = 0;

    while (i < sql.len) {
        switch (state) {
            .code => {
                const ch = sql[i];
                if (ch == ';') {
                    return error.UnsafeSqlFragment;
                }
                if (ch == '-' and i + 1 < sql.len and sql[i + 1] == '-') {
                    return error.UnsafeSqlFragment;
                }
                if (ch == '/' and i + 1 < sql.len and sql[i + 1] == '*') {
                    return error.UnsafeSqlFragment;
                }
                if (ch == '*' and i + 1 < sql.len and sql[i + 1] == '/') {
                    return error.UnsafeSqlFragment;
                }
                if (ch == '\'') {
                    state = .single_quote;
                    i += 1;
                    continue;
                }
                if (ch == '"') {
                    state = .double_quote;
                    i += 1;
                    continue;
                }
                if (isIdentStart(ch)) {
                    const start = i;
                    i += 1;
                    while (i < sql.len and isIdentContinue(sql[i])) : (i += 1) {}
                    if (isDangerousSqlKeyword(sql[start..i])) {
                        return error.UnsafeSqlFragment;
                    }
                    continue;
                }
                i += 1;
            },
            .single_quote => {
                const ch = sql[i];
                i += 1;
                if (ch == '\'') {
                    if (i < sql.len and sql[i] == '\'') {
                        i += 1;
                    } else {
                        state = .code;
                    }
                }
            },
            .double_quote => {
                const ch = sql[i];
                i += 1;
                if (ch == '"') {
                    if (i < sql.len and sql[i] == '"') {
                        i += 1;
                    } else {
                        state = .code;
                    }
                }
            },
            .line_comment, .block_comment => unreachable,
        }
    }
}

pub fn validateOrderByRawFragment(sql: []const u8) errors.OrmError!void {
    // For now we share the same scanner policy as guarded WHERE fragments.
    // This blocks statement separators/comments/subquery-driving keywords.
    try validateWhereRawFragment(sql);
}

fn isIdentStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_';
}

fn isIdentContinue(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

fn isDangerousSqlKeyword(word: []const u8) bool {
    const blocked = [_][]const u8{
        "SELECT",
        "INSERT",
        "UPDATE",
        "DELETE",
        "DROP",
        "ALTER",
        "CREATE",
        "ATTACH",
        "DETACH",
        "PRAGMA",
        "VACUUM",
        "REINDEX",
        "ANALYZE",
        "WITH",
        "UNION",
    };

    inline for (blocked) |kw| {
        if (std.ascii.eqlIgnoreCase(word, kw)) {
            return true;
        }
    }
    return false;
}

test "guard: validateWhereRawFragment accepts simple predicates" {
    try validateWhereRawFragment("\"name\"=?1");
    try validateWhereRawFragment("\"age\" > ?1 AND \"name\" = ?2");
    try validateWhereRawFragment("\"age\" IS NULL");
}

test "guard: validateWhereRawFragment rejects unsafe fragments" {
    try std.testing.expectError(error.UnsafeSqlFragment, validateWhereRawFragment("1=1; DROP TABLE users"));
    try std.testing.expectError(error.UnsafeSqlFragment, validateWhereRawFragment("1=1 -- force"));
    try std.testing.expectError(error.UnsafeSqlFragment, validateWhereRawFragment("\"id\" IN (SELECT id FROM users)"));
    try std.testing.expectError(error.UnsafeSqlFragment, validateWhereRawFragment("\"id\" = ?1 UNION \"id\" = ?2"));
}

test "guard: validateWhereRawFragment does not reject keyword-containing identifiers" {
    // `select_count` is a single identifier and does not match the whole word "SELECT".
    try validateWhereRawFragment("\"select_count\" = ?1");
    try validateWhereRawFragment("\"union_flag\" > ?1");
}

test "guard: validateOrderByRawFragment rejects unsafe fragments" {
    try std.testing.expectError(error.UnsafeSqlFragment, validateOrderByRawFragment("\"id\" DESC; DROP TABLE users"));
    try std.testing.expectError(error.UnsafeSqlFragment, validateOrderByRawFragment("\"id\" DESC -- force"));
    try std.testing.expectError(error.UnsafeSqlFragment, validateOrderByRawFragment("\"id\" DESC, (SELECT 1)"));
}
