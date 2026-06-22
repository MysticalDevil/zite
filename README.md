# Zite

Typed SQLite access for Zig with a small ORM layer and explicit ownership rules.

> [!IMPORTANT]
> This project targets Zig `0.17.x` on `main` and is not compatible with Zig `0.16.x`.

## Highlights

- Strong, explicit memory ownership for text/blob data (`OwnedText`, `OwnedBlob`).
- Simple ORM mapping via `struct` + `Meta`.
- Low-level statement API for direct SQL.
- Compact schema generation helpers.

## Install

This repo is a Zig module. Add it via the Zig package manager, then integrate it in `build.zig`.

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
    // Optional: defaults to .system (libsqlite3).
    // .sqlite_backend = .pure,
});
const zite = zite_dep.module("zite");

exe.root_module.addImport("zite", zite);
exe.root_module.linkSystemLibrary("sqlite3", .{ .needed = true });
```

### Notes

- Backend selection is build-time pluggable via `-Dsqlite_backend=system|pure`.
- Default backend is `system` (libsqlite3).
- For `system`, link system sqlite3 on your final executable/test target.
- For `pure`, do not link system sqlite3.

## API Quick Reference

| Area | Entry Point | Notes |
| --- | --- | --- |
| Database | `zite.Db(Driver).open` / `db.deinit` | Opens/closes a connection for selected driver. |
| Transactions (types) | `zite.Db(Driver).TxMode`, `zite.Db(Driver).Tx` | Driver-bound transaction mode/handle types. |
| Statements | `zite.Stmt(Driver).init` / `st.deinit` | Driver-bound prepared statement wrapper. |
| Async execution | `zite.AsyncPool(Driver).init` | Experimental `std.Io`-based execution layer. |
| ORM repository | `zite.orm(Driver).repository(User, &db, a)` | Creates a typed repository for `User`. |
| ORM insert | `repo.insert` | Returns last insert rowid. |
| ORM insert many | `repo.insertMany` | Inserts multiple rows and returns count. |
| ORM update | `repo.update` | Returns rows changed. |
| ORM upsert | `repo.upsert` | Returns `.inserted` or `.updated`. |
| Query builder | `repo.query()` | Builder with `whereEq/whereSql/orderBy/limit/offset`. |
| Guarded raw fragments | `repo.findOneSql`, `repo.findManySql`, `repo.deleteWhereSql` | Rejects unsafe fragments with `error.UnsafeSqlFragment`. |
| Explicit unchecked raw fragments | `repo.findOneSqlUnsafe`, `repo.findManySqlUnsafe`, `repo.deleteWhereSqlUnsafe` | Caller guarantees SQL fragment trustworthiness. |
| Find by id | `repo.findByIdOwned` | `OwnedRow(T)` or `null`. |
| Row handle | `repo.findByIdHandle` | `RowHandle(T)` for single-row zero-copy access. |
| Row cursor | `q.iterateViews()` | `RowCursor(T)` for zero-copy row views. |
| Transactions | `repo.beginTx(.deferred)` | `commit()` / `rollback()` or automatic rollback on `deinit()`. |
| Schema | `zite.schema.createTableSqlFromMeta` | CREATE TABLE from `Meta`. |
| Errors | `zite.errors.*Error` | Layered error sets by subsystem (`DbError`, `StmtError`, `OrmError`, ...). |

## API Stability

- Stable: `Db(Driver)`, `Stmt(Driver)`, `orm(Driver)`, `schema`, `types`, `errors`.
- Experimental: `AsyncPool` / `async_pool`. Built for Zig `0.17.x` `std.Io`; API may change.
- Advanced/Low-level: `drivers.sqlite3`, `sqlutil`, `meta`. These are exposed for power users
  but may change when internals evolve.
- Internal: `src/orm/engine.zig` and `src/orm/engine/*` are implementation details used by `orm` and are
  not part of the public API contract.

## Quick Start (ORM)

```zig
const std = @import("std");
const zite = @import("zite");
const Driver = zite.drivers.sqlite3;
const Db = zite.Db(Driver);
const Orm = zite.orm(Driver);

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

    var db = try Db.open(a, ":memory:");
    defer db.deinit();
    var repo = Orm.repository(User, &db, a);

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

## Allocator Guidance (Zig 0.17)

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
    .rename = &[_]zite.meta.Rename{
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

`whereSql` rebases placeholders relative to the current query parameter count.
That means `?1`, `?2`, or bare `?` inside the raw fragment are local to that
fragment, even when mixed with earlier `whereEq` calls.

Guarded raw APIs reject unsafe fragments such as statement separators, SQL
comments, and statement-level keywords.

- Query builder: `whereSql` (unsafe counterpart: `whereSqlUnsafe`)
- Repository: `findOneSql`, `findOneHandleSql`, `findManySql`,
  `findManySqlWithOptions`, `findManyOwnedSql`, `deleteWhereSql`
- Repository unsafe counterparts: `findOneSqlUnsafe`, `findOneHandleSqlUnsafe`,
  `findManySqlUnsafe`, `findManySqlWithOptionsUnsafe`,
  `findManyOwnedSqlUnsafe`, `deleteWhereSqlUnsafe`

`findManySqlWithOptions` validates both `where_clause` and `opts.order_by`.

```zig
var q = repo.query();
try q.whereEq("id", @as(i64, 1));
try q.whereSql("\"name\"=?1", .{"alice"});
try q.orderBy("id", .asc);
q.setLimit(20);
q.setOffset(40);
var rows = try q.iterateOwned();
defer rows.deinit();
```

## Zero-Copy Row Access

Use row views when you want zero-copy access to the current statement row.

- `q.iterateViews()` returns a `RowCursor(T)`.
- `cursor.next()` returns a `RowView(T)` for the current row.
- `repo.findByIdHandle(...)` and `repo.findOneHandleSql(...)` return a `RowHandle(T)` for single-row access.

Lifecycle rules:

- `RowView` is valid only until the cursor advances or is deinitialized.
- `RowHandle` owns the underlying statement and remains valid until `deinit()`.
- Access after cursor advance returns `error.RowViewStale`.
- Access after handle/cursor teardown returns `error.StatementFinalized`.

```zig
var q = repo.query();
defer q.deinit();
try q.orderBy("id", .asc);

var cursor = try q.iterateViews();
defer cursor.deinit();

while (try cursor.next()) |row| {
    std.debug.print("{s}\n", .{try row.get("name")});
}
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

`AsyncPool` is an experimental execution layer for Zig `0.17.x`. It uses
`std.Io.concurrent` to run blocking sqlite work on independent connections.

Important constraints:

- It does not make sqlite itself non-blocking; it schedules blocking work.
- Each task opens its own `Db`.
- `RowView` / `RowHandle` / `RowCursor` values are not allowed across the async boundary.
- `AsyncPool.findOne` returns an owned value; free it with `zite.AsyncPool.freeOwnedRow`.
- SQLite still behaves like SQLite: a single file-backed database supports many
  readers, but write concurrency is still limited by database locking.

```zig
const Driver = zite.drivers.sqlite3;
const AsyncPool = zite.AsyncPool(Driver);

pub fn main(init: std.process.Init) !void {
    var pool = try AsyncPool.init(init.gpa, "app.sqlite", .{});
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
const Driver = zite.drivers.sqlite3;
const Stmt = zite.Stmt(Driver);
var st = try Stmt.init(&db, "SELECT body FROM notes WHERE id=?1;");
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

## Guarded SQL Fragments (ORM)

Repository raw-fragment helpers use paired APIs:

- Guarded: `findOneSql`, `findManySql`, `findManySqlWithOptions`, `findManyOwnedSql`, `deleteWhereSql`
- Explicit escape hatch: corresponding `...SqlUnsafe` variants

Guarded variants validate raw SQL fragments and return `error.UnsafeSqlFragment`
when unsafe constructs are detected. `findManySqlWithOptions` validates both
`where_clause` and `opts.order_by`.

Use `...SqlUnsafe` only when the fragment is fully trusted (for example,
internal constant SQL that cannot be influenced by external input).

## Errors

Public APIs now return layered error sets instead of one catch-all set.

- `errors.DbError`: database open/exec/transaction/lifecycle failures.
- `errors.StmtError`: statement prepare/bind/step/finalize failures.
- `errors.RowReadError`: row-view lifecycle and column decoding failures.
- `errors.OrmError`: ORM/query invariants layered on top of row/statement failures.
- `errors.AsyncOrmError`: async boundary failures plus propagated ORM errors.
- `errors.SchemaError`: schema SQL generation allocation failures.

Driver return codes are mapped to specific errors such as
`error.DriverBusy`, `error.DriverConstraint`, and `error.DriverIo`.

Notable behavior-specific errors:

- `error.StatementFinalized`: statement or row-backed handle used after `deinit()`/`finalize()`.
- `error.RowViewStale`: a `RowView` was accessed after its cursor advanced.
- `error.UnsafeSqlFragment`: guarded raw SQL fragment rejected by ORM safety checks.
- `error.EmptyWhereClause`: `deleteWhereSql` called with empty WHERE.
- `error.UnexpectedExtraRows`: `findOne`/`findById` observed more rows than expected.

## Tests

- `zig build test` runs unit tests.
- `zig build itest` runs integration tests.
- `tests/integration/async_pool.zig` covers `insert`, `update`, `deleteById`,
  `upsert`, concurrent reads, empty-result paths, and representative error propagation.

## Zig Version

- The project targets Zig `0.17.x` on the `main` branch.

## Examples

- `examples/orm_basic.zig`
- `examples/orm_find_many.zig`
- `examples/orm_find_one.zig`
- `examples/orm_raw_sql_guard.zig`
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

- Detailed architecture doc: `docs/ARCHITECTURE.md`

## Project Layout

- `src/raw/` low-level sqlite3 bindings.
- `src/db/` DB/statement wrappers.
- `src/core/` types/meta/sql helpers.
- `src/orm/` repository/query ORM and schema.
- `src/orm/engine.zig` internal engine namespace entrypoint.
- `src/orm/engine/` internal ORM engine (SQL assembly, row decoding, exec helpers).
- `scripts/generate_test_db.sh` generates a small file-backed SQLite database for manual testing.
- `tests/` integration tests.
