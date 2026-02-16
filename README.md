# zite

A lightweight SQLite wrapper + struct mapper for Zig.

Language: English | [简体中文](README.zh-CN.md)

`zite` provides:
- Thin wrapper around `sqlite3` (`Db`, `Stmt`, bind/step/column APIs)
- Struct-driven schema SQL generation (`schema.createTableSql*`)
- Basic mapper APIs (`insert`, `update`, `getById`, `findOne`, `findMany`)
- Owned result helpers for TEXT fields (`Owned(T)`, `freeOwned`)

## Requirements

- Zig `0.15.2+` (see `build.zig.zon`)
- System `sqlite3` development library (`sqlite3.h` + linker library)

Install `sqlite3` (common platforms):

```bash
# Debian / Ubuntu
sudo apt-get update && sudo apt-get install -y libsqlite3-dev

# Fedora
sudo dnf install -y sqlite-devel

# Arch Linux
sudo pacman -S --needed sqlite

# Gentoo
sudo emerge --ask dev-db/sqlite

# macOS (Homebrew)
brew install sqlite
```

## Add To Your Project

Fetch dependency (recommended):

```bash
zig fetch --save git+https://github.com/MysticalDevil/zite.git
```

After running the command above, Zig will write the dependency entry (`url` + `hash`) into your `build.zig.zon`.
You can also add it manually, like this:

```zig
.dependencies = .{
    .zite = .{
        .url = "git+https://github.com/MysticalDevil/zite.git",
        .hash = "zite-0.0.1-...",
    },
},
```

Tarball URL (optional):

```bash
zig fetch --save https://github.com/MysticalDevil/zite/archive/refs/tags/<tag>.tar.gz
```

Local development (optional):

```zig
.dependencies = .{
    .zite = .{
        .path = "../zite",
    },
},
```

`build.zig`:

```zig
const zite_dep = b.dependency("zite", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zite", zite_dep.module("zite"));
```

## Quick Start

```zig
const std = @import("std");
const orm = @import("zite");

const User = struct {
    id: i64,
    name: []const u8,
    age: ?i64,
    created_at: i64,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
        .skip_primary_key_on_insert = true,
    };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var db = try orm.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try orm.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    const id = try orm.mapper.insert(User, &db, .{
        .id = 0,
        .name = "alice",
        .age = null,
        .created_at = 123,
    });

    var user = (try orm.mapper.getById(User, &db, a, id)).?;
    defer orm.mapper.freeOwned(User, a, &user);

    user.age = 20;
    _ = try orm.mapper.update(User, &db, user);
}
```

## Core API

- `orm.Db`
- `open(allocator, path)`, `exec(sql)`, `errmsg()`, `lastInsertRowId()`, `changes()`, `close()/deinit()`
- after `close()`, `exec` and `Stmt.init` return `error.DbClosed`

- `orm.Stmt`
- `init(&db, sql)`, `bindOne(idx, value)`, `bindAll(.{...})`, `step()`, `reset()`, `clearbindings()`, `deinit()`
- columns: `colInt`, `colBool`, `colDouble`, `colText`, `colBlob`, `colIsNull`, `colTextOwned`

- `orm.schema`
- `createTableSql(allocator, T, opts)`
- `createTableSqlFromMeta(allocator, T)`

- `orm.mapper`
- writes: `insert`, `update`
- reads: `getById`, `findOne`, `findMany`
- owned wrappers: `getByIdOwned`, `findOneOwned`, `findManyOwned`
- memory helpers: `Owned(T)`, `freeOwned(T, allocator, &value)`

## Memory Model

- `Stmt.colText()` returns SQLite internal buffer view (invalid after next `step/reset/finalize`)
- mapper read APIs allocate memory for TEXT slice fields (`[]u8`/`[]const u8` cases)
- free returned struct values with:
  - `orm.mapper.freeOwned(T, allocator, &value)`, or
  - `Owned(T).deinit()` when using owned wrappers

## Type Mapping (Current)

Schema generation (`schema.createTableSql*`):
- int/uint/bool/enum -> `INTEGER`
- float -> `REAL`
- `[]u8`/`[]const u8` -> `TEXT`
- `[N]u8` -> `BLOB`
- `types.UnixMillis` -> `INTEGER`

Binding/reading supports common int/float/bool/enum/optional/string-slice paths used in tests.

## Diagnostics

SQL diagnostics logs are enabled by default in non-test builds.

For tests, you can enable diagnostics:

```bash
zig build test -Ddiag_enable_in_tests=true
zig build itest -Ddiag_enable_in_tests=true
```

## Run Tests

```bash
zig build test
zig build itest
```

## Limitations (Current)

- Not a full ORM (no relations, migrations, query builder, pooling)
- `findOne/findMany` still accept raw `where_clause` SQL fragment
- You should keep table/field identifiers controlled by code (not user input)

## License

MIT (`LICENSE`)
