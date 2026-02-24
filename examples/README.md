# Examples

Each example is a standalone Zig file that imports the module by name. Run them
with a module mapping and link sqlite3.

## Run Commands

```sh
zig run examples/orm_basic.zig -M zite=src/root.zig -lc -lsqlite3
zig run examples/orm_find_one.zig -M zite=src/root.zig -lc -lsqlite3
zig run examples/orm_find_many.zig -M zite=src/root.zig -lc -lsqlite3
zig run examples/orm_meta_options.zig -M zite=src/root.zig -lc -lsqlite3
zig run examples/stmt_basic.zig -M zite=src/root.zig -lc -lsqlite3
zig run examples/stmt_bind_all.zig -M zite=src/root.zig -lc -lsqlite3
```

## Notes

- SQLite must be available on the system (`sqlite3` headers and library).
- Examples use `:memory:` databases for convenience.
