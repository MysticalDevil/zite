# Examples

Each example is a standalone Zig file that imports the module by name. Run them
with a module mapping and link sqlite3.
The `examples/build_options.zig` module selects the system sqlite backend for
direct `zig run` usage.

> [!IMPORTANT]
> Examples target Zig `0.17.x` and are not compatible with Zig `0.16.x`.

## Run Commands

**orm_basic.zig**  
ORM mapping flow with `OwnedText`/`OwnedBlob`.

```sh
zig run --dep zite -Mroot=examples/orm_basic.zig --dep build_options -Mzite=src/root.zig -Mbuild_options=examples/build_options.zig -lc -lsqlite3
```

**orm_find_one.zig**  
`findOne` with parameters.

```sh
zig run --dep zite -Mroot=examples/orm_find_one.zig --dep build_options -Mzite=src/root.zig -Mbuild_options=examples/build_options.zig -lc -lsqlite3
```

**orm_raw_sql_guard.zig**  
Guarded raw SQL (`whereSql`/`findOneSql`) vs explicit unsafe variants.

```sh
zig run --dep zite -Mroot=examples/orm_raw_sql_guard.zig --dep build_options -Mzite=src/root.zig -Mbuild_options=examples/build_options.zig -lc -lsqlite3
```

**orm_find_many.zig**  
`findManySql` iteration.

```sh
zig run --dep zite -Mroot=examples/orm_find_many.zig --dep build_options -Mzite=src/root.zig -Mbuild_options=examples/build_options.zig -lc -lsqlite3
```

**orm_meta_options.zig**  
`Meta` options (`rename`, `skip`, `unique`).

```sh
zig run --dep zite -Mroot=examples/orm_meta_options.zig --dep build_options -Mzite=src/root.zig -Mbuild_options=examples/build_options.zig -lc -lsqlite3
```

**stmt_basic.zig**  
Direct `Stmt` usage.

```sh
zig run --dep zite -Mroot=examples/stmt_basic.zig --dep build_options -Mzite=src/root.zig -Mbuild_options=examples/build_options.zig -lc -lsqlite3
```

**stmt_bind_all.zig**  
`bindAll` with typed params.

```sh
zig run --dep zite -Mroot=examples/stmt_bind_all.zig --dep build_options -Mzite=src/root.zig -Mbuild_options=examples/build_options.zig -lc -lsqlite3
```

**async_pool_basic.zig**  
Experimental `AsyncPool` usage with `main(init: std.process.Init)` and `init.io`.

```sh
zig run --dep zite -Mroot=examples/async_pool_basic.zig --dep build_options -Mzite=src/root.zig -Mbuild_options=examples/build_options.zig -lc -lsqlite3
```

This example creates `async_pool_basic.sqlite` in the current working directory.

**process_init_full.zig**  
`main(init: std.process.Init)` with `init.gpa` and `--name=...`.

```sh
zig run --dep zite -Mroot=examples/process_init_full.zig --dep build_options -Mzite=src/root.zig -Mbuild_options=examples/build_options.zig -lc -lsqlite3 -- --name=bob
```

**process_init_minimal.zig**  
`main(init: std.process.Init.Minimal)` with manual allocator policy.

```sh
zig run --dep zite -Mroot=examples/process_init_minimal.zig --dep build_options -Mzite=src/root.zig -Mbuild_options=examples/build_options.zig -lc -lsqlite3 -- "hello-from-argv"
```

**process_init_env.zig**  
`main(init: std.process.Init)` with `init.environ_map`.

```sh
ZITE_NOTE_BODY="from-env" zig run --dep zite -Mroot=examples/process_init_env.zig --dep build_options -Mzite=src/root.zig -Mbuild_options=examples/build_options.zig -lc -lsqlite3
```

## Notes

- SQLite must be available on the system (`sqlite3` headers and library).
- Most examples use `:memory:` databases for convenience; `async_pool_basic.zig` uses a file-backed database.
- Transactions support both `commit()` and explicit `rollback()`.
- `deleteWhereSql` requires a non-empty WHERE clause.
- `AsyncPool` is experimental and requires Zig `0.17.x` `std.Io`.
