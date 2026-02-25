# Examples

Each example is a standalone Zig file that imports the module by name. Run them
with a module mapping and link sqlite3.

## Run Commands

**orm_basic.zig**  
ORM mapping flow with `OwnedText`/`OwnedBlob`.
```sh
zig run examples/orm_basic.zig -M zite=src/root.zig -lc -lsqlite3
```

**orm_find_one.zig**  
`findOne` with parameters.
```sh
zig run examples/orm_find_one.zig -M zite=src/root.zig -lc -lsqlite3
```

**orm_find_many.zig**  
`findMany` iteration.
```sh
zig run examples/orm_find_many.zig -M zite=src/root.zig -lc -lsqlite3
```

**orm_meta_options.zig**  
`Meta` options (`rename`, `skip`, `unique`).
```sh
zig run examples/orm_meta_options.zig -M zite=src/root.zig -lc -lsqlite3
```

**stmt_basic.zig**  
Direct `Stmt` usage.
```sh
zig run examples/stmt_basic.zig -M zite=src/root.zig -lc -lsqlite3
```

**stmt_bind_all.zig**  
`bindAll` with typed params.
```sh
zig run examples/stmt_bind_all.zig -M zite=src/root.zig -lc -lsqlite3
```

## Notes

- SQLite must be available on the system (`sqlite3` headers and library).
- Examples use `:memory:` databases for convenience.
