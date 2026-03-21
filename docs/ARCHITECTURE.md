# Architecture

This document describes Zite's runtime architecture, module boundaries, and
critical execution paths.

## High-Level Design

Zite has a layered architecture:

- `src/raw/`: direct SQLite FFI bindings.
- `src/db/`: safe connection/statement wrappers (`Db`, `Stmt`, `Tx`).
- `src/core/`: shared types, metadata, SQL string helpers, layered errors.
- `src/async_pool.zig`: experimental `std.Io`-based task execution layer.
- `src/orm/`: typed repository/query APIs.
- `src/orm/engine/`: internal SQL assembly, bind/step, row decoding.

The public API is intentionally small (`Db`, `Stmt`, `TxMode`, `Tx`, `orm`,
`schema`, `types`, `errors`) with `AsyncPool` kept explicitly experimental; the
engine internals stay hidden behind `orm`.

## Detailed ASCII Diagram

```text
                                Application Code
    +----------------------------------------------------------------------------------+
    | zite.Db / zite.Stmt / zite.TxMode / zite.Tx / zite.orm / zite.schema / types    |
    | zite.AsyncPool (experimental) / advanced: zite.raw, zite.meta, zite.sqlutil      |
    +---------------------------------------------+------------------------------------+
                                                  |
                                                  v
                                 +----------------+----------------+
                                 |            src/root.zig         |
                                 |      public API + module wiring |
                                 +----------------+----------------+
                                                  |
      +----------------------------+--------------+---------------+-------------------------+
      |                            |                              |                         |
      v                            v                              v                         v
 +----+------------------+   +-----+----------------+   +---------+----------------+  +----+----------------+
 | src/db/*              |   | src/orm/*            |   | src/async_pool.zig       |  | src/orm/schema.zig |
 | Db / Stmt / Tx        |   | repository + query   |   | std.Io task execution    |  | createTableSql*    |
 | lifecycle + bind/step |   | guarded/unsafe SQL   |   | per-task Db connection   |  | from struct + Meta |
 +----+------------------+   +-----+----------------+   +---------+----------------+  +--------------------+
      |                            |                              |
      | prepares / binds / steps   | delegates execution          | opens connection
      v                            v                              v
 +----+------------------+   +-----+----------------+         +---+------------------+
 | src/raw/*             |<--| src/orm/engine/*     |         | src/db/* + src/raw/* |
 | sqlite3_* FFI         |   | sql/exec/row internals|         | inside task closure  |
 +----+------------------+   +-----+----------------+         +----------------------+
      ^                            ^
      |                            |
      +-------------+--------------+
                    |
                    v
              +-----+-----------------------------+
              | src/core/*                        |
              | errors / meta / types / sqlutil   |
              +-----------------------------------+

                                    External Dependencies
                                    ---------------------
          +---------------------+      +------------------------+      +---------------------+
          | System sqlite3 lib  |<-----| src/raw sqlite3_* FFI  |----->| C ABI / libc        |
          | headers + runtime   | link | symbol bindings        |       | (link_libc = true)  |
          +---------------------+      +------------------------+      +---------------------+
                         ^
                         |
              +----------+-----------+
              | Zig std/runtime/alloc|
              | alloc, io, testing   |
              +----------------------+


Execution path: Repository guarded raw fragment query
-----------------------------------------------------
repo.findOneSql(...)
  -> orm.Repository.findOneSql
  -> orm.validateWhereRawFragment
  -> orm.mapper.findOne
  -> orm.engine.sql.buildFindOneSql
  -> orm.engine.sql.prepareOwnedSql
  -> db.Stmt.bindAll / step
  -> orm.engine.row.readStruct
  -> returns T or error.UnexpectedExtraRows

repo.findManySqlWithOptions(...)
  -> orm.Repository.findManySqlWithOptions
  -> orm.validateWhereRawFragment
  -> orm.validateOrderByRawFragment (when opts.order_by != null)
  -> orm.mapper.findManyWithOptions
  -> orm.engine.sql.buildFindManySql
  -> orm.engine.sql.prepareOwnedSql
  -> db.Stmt.bindAll / step
  -> row iterator (`Rows(T)`/`OwnedRows(T)`)

repo.deleteWhereSql(...)
  -> orm.Repository.deleteWhereSql
  -> orm.validateWhereRawFragment
  -> orm.mapper.deleteWhere
  -> orm.engine.sql.buildDeleteWhereSql
  -> orm.engine.sql.prepareOwnedSql
  -> db.Stmt.bindAll / step
  -> db.Db.changes()

Execution path: Query row-view iteration
----------------------------------------
repo.query().iterateViews()
  -> orm.Query.iterateViewsWithLimit
  -> orm.engine.sql.buildFindManySql
  -> db.Stmt.prepare/bind
  -> orm.RowCursor.next()
  -> orm.RowView.get(...)
  -> orm.engine.row.readValueView(...)
  -> lifecycle guard:
       - error.StatementFinalized if stmt closed
       - error.RowViewStale if cursor advanced

Execution path: Transaction
---------------------------
repo.beginTx(mode)
  -> db.Db.beginTx(mode)
  -> returns db.Tx
  -> tx.commit() / tx.rollback()
  -> tx.deinit(): auto rollback if unfinished

Execution path: AsyncPool findByIdOwned
---------------------------------------
pool.findByIdOwned(io, T, allocator, id)
  -> std.Io.concurrent(...)
  -> async_pool.withConnection
  -> db.Db.open(file_path)
  -> orm.repository(T, &db, allocator)
  -> repo.findByIdOwned(id)
  -> result materialized before await returns
  -> db.deinit()
```

## External Dependencies

- `sqlite3` system library: required at build and runtime (`linkSystemLibrary("sqlite3")`).
- `libc`: required because sqlite C ABI is linked via Zig (`link_libc = true`).
- Zig standard library/runtime: allocators, logging, testing, and utility APIs.

## Ownership and Safety Invariants

- `OwnedText`/`OwnedBlob` are explicitly owned and must be deinitialized.
- `RowView` values are valid only for the current statement row on the current cursor generation.
- `RowHandle` owns a prepared statement and exposes field access through an internal `RowView`.
- Statement operations after `deinit()`/`finalize()` return `error.StatementFinalized`.
- Destructive delete-with-where APIs reject empty where clauses (`error.EmptyWhereClause`).
- Guarded raw-fragment APIs reject unsafe SQL fragments (`error.UnsafeSqlFragment`);
  explicit `...SqlUnsafe` variants skip this validation.
- `findOne`/`findById` guard cardinality and return `error.UnexpectedExtraRows` if violated.
- `AsyncPool` never returns `RowView`, `RowCursor`, or `RowHandle`; async boundaries are owned-only.

## Why This Shape

- Keeps low-level SQLite details isolated in `raw` + `db`.
- Keeps ORM API ergonomic while centralizing SQL/bind/read behavior in `engine`.
- Preserves explicit memory ownership and predictable error semantics in Zig 0.16.
