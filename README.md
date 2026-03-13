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
| Transactions (types) | `zite.TxMode`, `zite.Tx` | Public transaction mode/handle types. |
| Statements | `zite.Stmt.init` / `st.deinit` | Prepared statement wrapper. |
| Async execution | `zite.AsyncPool.init` | Experimental `std.Io`-based execution layer. |
| ORM repository | `zite.orm.repository(User, &db, a)` | Creates a typed repository for `User`. |
| ORM insert | `repo.insert` | Returns last insert rowid. |
| ORM insert many | `repo.insertMany` | Inserts multiple rows and returns count. |
| ORM update | `repo.update` | Returns rows changed. |
| ORM upsert | `repo.upsert` | Returns `.inserted` or `.updated`. |
| Query builder | `repo.query()` | Builder with `whereEq/whereRaw/orderBy/limit/offset`. |
| Find by id | `repo.findByIdOwned` | `OwnedRow(T)` or `null`. |
| Transactions | `repo.beginTx(.deferred)` | `commit()` / `rollback()` or automatic rollback on `deinit()`. |
| Schema | `zite.schema.createTableSqlFromMeta` | CREATE TABLE from `Meta`. |
| Errors | `zite.errors.ZiteError` | Unified error set. |

## API Stability

- Stable: `Db`, `Stmt`, `orm`, `schema`, `types`, `errors`.
- Experimental: `AsyncPool` / `async_pool`. Built for Zig `0.16/master` `std.Io`; API may change.
- Advanced/Low-level: `raw`, `sqlutil`, `meta`. These are exposed for power users
  but may change when internals evolve.
- Internal: `src/orm/engine.zig` and `src/orm/engine/*` are implementation details used by `orm` and are
  not part of the public API contract.

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
    var repo = zite.orm.repository(User, &db, a);

    const ddl = try zite.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var user = User{
        .id = 1,
        .name = try OwnedText.fromConst(a, "Alice"),
        .created_at = .{ .value = 1700000000000 },
    };
    defer repo.freeOwnedRow(&user);

    _ = try repo.insert(user);

    if (try repo.findByIdOwned(@as(i64, 1))) |row| {
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
    // true => PK omitted from INSERT and CREATE TABLE emits AUTOINCREMENT for integer PKs.
    // false => PK must be provided by caller and CREATE TABLE omits AUTOINCREMENT.
    .skip_primary_key_on_insert = true,
    .order_by = "\"id\" DESC",
    .rename = &.{
        .{ .field = "created_at", .column = "createdAt" },
    },
    .skip = &.{ "transient_field" },
    .unique = &.{
        &.{ "email" },
    },
};
```

## Query Options

Use `repo.query()` for typed query building. `Meta.order_by` is used as the
default order when builder order is not explicitly set.

`whereRaw` rebases placeholders relative to the current query parameter count.
That means `?1`, `?2`, or bare `?` inside the raw fragment are local to that
fragment, even when mixed with earlier `whereEq` calls.

```zig
var q = repo.query();
try q.whereEq("id", @as(i64, 1));
try q.whereRaw("\"name\"=?1", .{"alice"});
try q.orderBy("id", .asc);
q.setLimit(20);
q.setOffset(40);
var rows = try q.iterateOwned();
defer rows.deinit();
```

## Bulk Insert

Use `insertMany` to insert multiple rows with one prepared statement.

```zig
const inserted = try repo.insertMany(&[_]User{
    .{ .id = 0, .name = n1, .age = 20 },
    .{ .id = 0, .name = n2, .age = null },
});
_ = inserted; // 2
```

## Transactions

```zig
var tx = try repo.beginTx(.deferred);
defer tx.deinit(); // auto rollback if not committed

_ = try repo.insert(.{ .id = 0, .name = n1, .age = 20 });
try tx.commit();
// try tx.rollback(); // explicit rollback is also supported
```

For multi-connection write contention, prefer wrapping related writes (including
`upsert`) in an explicit transaction to make behavior easier to reason about.
This is especially important when `Meta.skip_primary_key_on_insert = true`,
because that compatibility path still uses an existence check before `INSERT`.
That path is only safe for serial callers; concurrent access, even through a
shared connection, can still observe a race.

## AsyncPool

`AsyncPool` is an experimental execution layer for Zig `0.16/master`. It uses
`std.Io.concurrent` to run blocking sqlite work on independent connections.

Important constraints:
- It does not make sqlite itself non-blocking; it schedules blocking work.
- Each task opens its own `Db`.
- Borrowed results are not allowed across the async boundary.
- `AsyncPool.findOne` returns an owned value; free it with `zite.AsyncPool.freeOwnedRow`.
- SQLite still behaves like SQLite: a single file-backed database supports many
  readers, but write concurrency is still limited by database locking.

```zig
pub fn main(init: std.process.Init) !void {
    var pool = try zite.AsyncPool.init(init.gpa, "app.sqlite", .{});
    defer pool.deinit();

    _ = try pool.insert(init.io, User, .{ .id = 1, .name = name });

    if (try pool.findByIdOwned(init.io, User, init.gpa, @as(i64, 1))) |row| {
        var owned = row;
        defer owned.deinit();
        std.debug.print("{s}\n", .{owned.value.name.value});
    }
}
```

## Owned Types

`OwnedText`/`OwnedBlob` carry owned buffers and must be freed. ORM mapping and
`bindOne` only accept these types for text/blob fields.

```zig
var name = try zite.types.OwnedText.fromConst(a, "Alice");
defer name.deinit(a);
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

`colTextOwned` / `colBlobOwned` return `null` only for SQL `NULL`. Empty text or
blob values return a non-null empty slice.

`Stmt` enforces lifecycle validity. After `deinit()`/`finalize()`, all statement
operations return `error.StatementFinalized`.

## Errors

All public APIs return `errors.ZiteError`. SQLite return codes are mapped to
specific errors (busy, constraint, io, etc.) where possible.

Notable behavior-specific errors:
- `error.StatementFinalized`: statement used after `deinit()`/`finalize()`.
- `error.EmptyWhereClause`: `deleteWhereRaw` called with empty WHERE.
- `error.UnexpectedExtraRows`: `findOne`/`findById` observed more rows than expected.

## Tests

- `zig build test` runs unit tests.
- `zig build itest` runs integration tests.
- `tests/integration/async_pool.zig` covers `insert`, `update`, `deleteById`,
  `upsert`, concurrent reads, empty-result paths, and representative error propagation.

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
- `examples/async_pool_basic.zig` (`AsyncPool` with `init.io`)

### Run Examples

The examples are standalone Zig files. Run them with a module mapping and
link sqlite3:

```sh
zig run --dep zite -Mroot=examples/orm_basic.zig -Mzite=src/root.zig -lc -lsqlite3
```

See `examples/README.md` for more commands.

## Test Database Script

Generate a small file-backed SQLite database for manual testing:

```sh
./scripts/generate_test_db.sh /tmp/zite-test.sqlite
```

## Architecture

- Detailed architecture doc: `docs/architecture.md`

## Project Layout

- `src/raw/` low-level sqlite3 bindings.
- `src/db/` DB/statement wrappers.
- `src/core/` types/meta/sql helpers.
- `src/orm/` repository/query ORM and schema.
- `src/orm/engine.zig` internal engine namespace entrypoint.
- `src/orm/engine/` internal ORM engine (SQL assembly, row decoding, exec helpers).
- `scripts/generate_test_db.sh` generates a small file-backed SQLite database for manual testing.
- `tests/` integration tests.
