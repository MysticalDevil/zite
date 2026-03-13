# Zite

Typed SQLite access for Zig with a small ORM layer and explicit ownership rules.

> [!IMPORTANT]
> This project targets Zig `0.16-dev` (`master`) on `main` and is not compatible with Zig `0.15.x`.

## Highlights

- Strong, explicit memory ownership for text/blob data (`OwnedText`, `OwnedBlob`).
- Simple ORM mapping via `struct` + `Meta`.
- Low-level statement API for direct SQL.
- Compact schema generation helpers.

## Install

This repo is a Zig module. Add it via the Zig package manager, then integrate it in `build.zig`
and link sqlite.

### 1. Add dependency

```sh
zig fetch --save git+https://github.com/MysticalDevil/zite.git
```

This creates an entry in `build.zig.zon` under `.dependencies.zite`.

### 2. Integrate in `build.zig`

```zig
const exe = b.addExecutable(.{
    .name = "app",
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .link_libc = true,
});

const zite_dep = b.dependency("zite", .{
    .target = target,
    .optimize = optimize,
});
const zite = zite_dep.module("zite");

exe.root_module.addImport("zite", zite);
exe.root_module.linkSystemLibrary("sqlite3", .{ .needed = true });
```

### Notes

- Requires system `sqlite3` development headers and library.
- The consuming executable/test must set `link_libc = true`.
- Add `linkSystemLibrary("sqlite3")` to the final executable/test target.

## API Quick Reference

| Area | Entry Point | Notes |
| --- | --- | --- |
| Database | `zite.Db.open` / `db.deinit` | Opens/closes a SQLite connection. |
| Statements | `zite.Stmt.init` / `st.deinit` | Prepared statement wrapper. |
| ORM insert | `zite.mapper.insert` | Returns last insert rowid. |
| ORM update | `zite.mapper.update` | Returns rows changed. |
| ORM upsert | `zite.mapper.upsert` | Returns `.inserted` or `.updated`. |
| Find by id | `zite.mapper.findByIdOwned` | `OwnedRow(T)` or `null`. |
| Find one | `zite.mapper.findOne` | WHERE + params, `T` or `null`. |
| ORM find many | `zite.mapper.findMany` | Iterates rows with `Rows(T)`. |
| ORM find many opts | `zite.mapper.findManyWithOptions` | Adds `order_by` / `limit` / `offset`. |
| Schema | `zite.schema.createTableSqlFromMeta` | CREATE TABLE from `Meta`. |
| Errors | `zite.errors.ZiteError` | Unified error set. |

## API Stability

- Stable: `Db`, `Stmt`, `mapper`, `schema`, `types`, `errors`.
- Advanced/Low-level: `raw`, `sqlutil`, `meta`. These are exposed for power users
  but may change when internals evolve.

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
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const a = debug_allocator.allocator();

    var db = try zite.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try zite.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var user = User{
        .id = 1,
        .name = try OwnedText.fromConst(a, "Alice"),
        .created_at = .{ .value = 1700000000000 },
    };
    defer zite.mapper.freeOwnedRow(User, a, &user);

    _ = try zite.mapper.insert(User, &db, user);

    if (try zite.mapper.findByIdOwned(User, &db, a, 1)) |row| {
        var owned = row;
        defer owned.deinit();
        std.debug.print("name={s}\n", .{owned.value.name.value});
    }
}
```

## Allocator Guidance (Zig 0.16)

- Debug/test scenarios: prefer `std.heap.DebugAllocator(.{})`.
- Throughput-oriented runtime paths: consider `std.heap.smp_allocator`.
- Public APIs in this library accept `std.mem.Allocator`, so allocator policy stays with the caller.

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
var name = try zite.types.OwnedText.fromConst(a, "Alice");
defer a.free(name.value);
```

## Manual SQL (Stmt API)

```zig
var st = try zite.Stmt.init(&db, "SELECT body FROM notes WHERE id=?1;");
defer st.deinit();
try st.bindInt(1, 1);
if (try st.step() == .row) {
    if (try st.colTextOwned(a, 0)) |body| {
        defer a.free(body);
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

## Zig Version

- The project targets Zig `0.16-dev` (`master`) on the `main` branch.

## Examples

- `examples/orm_basic.zig`
- `examples/orm_find_many.zig`
- `examples/orm_find_one.zig`
- `examples/orm_meta_options.zig`
- `examples/stmt_bind_all.zig`
- `examples/stmt_basic.zig`
- `examples/process_init_full.zig` (`main(init: std.process.Init)`)
- `examples/process_init_minimal.zig` (`main(init: std.process.Init.Minimal)`)
- `examples/process_init_env.zig` (`init.environ_map`)

### Run Examples

The examples are standalone Zig files. Run them with a module mapping and
link sqlite3:

```sh
zig run --dep zite -Mroot=examples/orm_basic.zig -Mzite=src/root.zig -lc -lsqlite3
```

See `examples/README.md` for more commands.

## Project Layout

- `src/raw/` low-level sqlite3 bindings.
- `src/db/` DB/statement wrappers.
- `src/core/` types/meta/sql helpers.
- `src/orm/` mapper and schema.
- `tests/` integration tests.
