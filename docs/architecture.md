# Architecture

This document describes Zite's runtime architecture, module boundaries, and
critical execution paths.

## High-Level Design

Zite has a layered architecture:

- `src/raw/`: direct SQLite FFI bindings.
- `src/db/`: safe connection/statement wrappers (`Db`, `Stmt`, `Tx`).
- `src/core/`: shared types, metadata, SQL string helpers, unified errors.
- `src/orm/`: typed repository/query APIs.
- `src/orm/engine/`: internal SQL assembly, bind/step, row decoding.

The public API is intentionally small (`Db`, `Stmt`, `TxMode`, `Tx`, `orm`,
`schema`, `types`, `errors`) and the engine internals stay hidden behind `orm`.

## Detailed ASCII Diagram

```text
                                     Application Code
        +--------------------------------------------------------------------------------+
        |  zite.Db / zite.Stmt / zite.TxMode / zite.Tx / zite.orm / zite.schema / types |
        +-----------------------------------------------+--------------------------------+
                                                        |
                                                        v
                                   +--------------------+--------------------+
                                   |             src/root.zig                |
                                   | public API re-exports + module wiring   |
                                   +--------------------+--------------------+
                                                        |
                    +-----------------------------------+-----------------------------------+
                    |                                                                       |
                    v                                                                       v
      +-------------+-------------+                                          +--------------+--------------+
      |       src/db/*            |                                          |        src/orm/*            |
      | Db / Stmt / Tx wrappers   |                                          | repository + query builder  |
      | lifecycle + error mapping |                                          | typed CRUD + borrowed/owned |
      +-------------+-------------+                                          +--------------+--------------+
                    |                                                                       |
                    | uses                                                                  | delegates internals
                    v                                                                       v
      +-------------+-------------+                                          +--------------+--------------+
      |      src/raw/*            |<-----------------------------------------+   src/orm/engine/*          |
      | sqlite3_* FFI calls       |   prepares/steps/binds through Stmt      | sql + exec + row decoding   |
      +-------------+-------------+                                          +--------------+--------------+
                    ^                                                                       ^
                    |                                                                       |
                    +-----------------------------+-------------------------------+---------+
                                                  |                               |
                                                  v                               v
                                       +----------+-----------+       +-----------+----------+
                                       |     src/core/*       |       |     src/orm/schema   |
                                       | errors/meta/types/   |       | createTableSql*      |
                                       | sqlutil              |       | from struct + Meta   |
                                       +----------------------+       +-----------------------+

                                                   External Dependencies
                                                   ---------------------
                 +-------------------+        +-------------------+       +-------------------+
                 |  System sqlite3   |<-------|   src/raw FFI     |------>|  C ABI / libc     |
                 |  headers + lib    |  link  | sqlite3_* symbols |       |  (link_libc=true) |
                 +-------------------+        +-------------------+       +-------------------+
                           ^
                           |
                           +-----------------------------+
                                                         |
                                            +------------+------------+
                                            | Zig std/runtime/alloc   |
                                            | std.mem, allocators,    |
                                            | logging, testing        |
                                            +-------------------------+


Execution path: Repository findOneRaw (owned)
---------------------------------------------
repo.findOneRaw(...)
  -> orm.Repository.findOneRaw
  -> orm.mapper.findOne
  -> orm.engine.sql.buildFindOneSql
  -> orm.engine.sql.prepareOwnedSql
  -> db.Stmt.bindAll / step
  -> orm.engine.row.readStruct
  -> returns T or error.UnexpectedExtraRows

Execution path: Query borrowed iteration
----------------------------------------
repo.query().iterateBorrowed()
  -> orm.Query.iterateBorrowedWithLimit
  -> orm.engine.sql.buildFindManySql
  -> db.Stmt.prepare/bind
  -> orm.RowsBorrowed.next()
  -> orm.BorrowedRow.get(...)
  -> orm.engine.row.readValueBorrowed(...)
  -> lifecycle guard:
       - error.StatementFinalized if stmt closed
       - error.BorrowedRowStale if cursor advanced

Execution path: Transaction
---------------------------
repo.beginTx(mode)
  -> db.Db.beginTx(mode)
  -> returns db.Tx
  -> tx.commit() / tx.rollback()
  -> tx.deinit(): auto rollback if unfinished
```

## External Dependencies

- `sqlite3` system library: required at build and runtime (`linkSystemLibrary("sqlite3")`).
- `libc`: required because sqlite C ABI is linked via Zig (`link_libc = true`).
- Zig standard library/runtime: allocators, logging, testing, and utility APIs.

## Ownership and Safety Invariants

- `OwnedText`/`OwnedBlob` are explicitly owned and must be deinitialized.
- Borrowed query values are valid only for the current statement row.
- Statement operations after `deinit()`/`finalize()` return `error.StatementFinalized`.
- Destructive delete-with-where APIs reject empty where clauses (`error.EmptyWhereClause`).
- `findOne`/`findById` guard cardinality and return `error.UnexpectedExtraRows` if violated.

## Why This Shape

- Keeps low-level SQLite details isolated in `raw` + `db`.
- Keeps ORM API ergonomic while centralizing SQL/bind/read behavior in `engine`.
- Preserves explicit memory ownership and predictable error semantics in Zig 0.16.
