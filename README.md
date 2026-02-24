# Zite

Typed SQLite access for Zig with a small ORM layer and explicit ownership rules.

## Highlights

- Strong, explicit memory ownership for text/blob data (`OwnedText`, `OwnedBlob`).
- Simple ORM mapping via `struct` + `Meta`.
- Low-level statement API for direct SQL.
- Compact schema generation helpers.

## Install

This repo is a Zig module. Add it to your `build.zig` and link sqlite:

```zig
const zite = b.addModule("zite", .{
    .root_source_file = b.path("path/to/zite/src/root.zig"),
    .target = target,
    .optimize = optimize,
    .link_libc = true,
});
zite.linkSystemLibrary("sqlite3", .{ .needed = true });
```

## Quick Start (ORM)

```zig
const std = @import("std");
const zite = @import("zite");

const OwnedText = zite.types.OwnedText;
const EpochMillis = zite.types.EpochMillis;

const User = struct {
    id: i64,
    name: OwnedText,
    created_at: EpochMillis,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
    };
};

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    var db = try zite.Db.open(gpa, ":memory:");
    defer db.deinit();

    const ddl = try zite.schema.createTableSqlFromMeta(gpa, User);
    defer gpa.free(ddl);
    try db.exec(ddl);

    var user = User{
        .id = 1,
        .name = try OwnedText.fromConst(gpa, "Alice"),
        .created_at = .{ .value = 1700000000000 },
    };
    defer zite.mapper.freeOwnedRow(User, gpa, &user);

    _ = try zite.mapper.insert(User, &db, user);

    if (try zite.mapper.findByIdOwned(User, &db, gpa, 1)) |row| {
        defer row.deinit();
        std.debug.print("name={s}\n", .{row.value.name.value});
    }
}
```

## Meta Options

`Meta` controls table/column mapping and SQL generation.

```zig
pub const Meta = .{
    .table = "users",
    .primary_key = "id",
    .skip_primary_key_on_insert = true,
    .rename = &.{
        .{ .field = "created_at", .column = "createdAt" },
    },
    .skip = &.{ "transient_field" },
    .unique = &.{
        &.{ "email" },
    },
};
```

## Owned Types

`OwnedText`/`OwnedBlob` carry owned buffers and must be freed. ORM mapping and
`bindOne` only accept these types for text/blob fields.

```zig
var name = try zite.types.OwnedText.fromConst(gpa, "Alice");
defer gpa.free(name.value);
```

## Manual SQL (Stmt API)

```zig
var st = try zite.Stmt.init(&db, "SELECT body FROM notes WHERE id=?1;");
defer st.deinit();
try st.bindInt(1, 1);
if (try st.step() == .row) {
    if (try st.colTextOwned(gpa, 0)) |body| {
        defer gpa.free(body);
        std.debug.print("{s}\n", .{body});
    }
}
```

## Errors

All public APIs return `errors.ZiteError`. SQLite return codes are mapped to
specific errors (busy, constraint, io, etc.) where possible.

## Tests

- `zig build test` runs unit tests.
- `zig build itest` runs integration tests.
- `zig build itest -Ddiag_enable_in_tests=true` enables sqlite diagnostics.

## Examples

- `examples/orm_basic.zig`
- `examples/stmt_basic.zig`

## Project Layout

- `src/raw/` low-level sqlite3 bindings.
- `src/db/` DB/statement wrappers.
- `src/core/` types/meta/sql helpers.
- `src/orm/` mapper and schema.
- `tests/` integration tests.
