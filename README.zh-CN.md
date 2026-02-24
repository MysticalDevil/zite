# zite

一个面向 Zig 的轻量 SQLite 封装 + 结构体映射库。

语言：简体中文 | [English](README.md)

`zite` 提供：
- 对 `sqlite3` 的薄封装（`Db`、`Stmt`、bind/step/column API）
- 基于结构体的建表 SQL 生成（`schema.createTableSql*`）
- 基础 mapper API（`insert`、`update`、`getById`、`findOne`、`findMany`）
- 面向 TEXT 字段的 owned 结果辅助（`Owned(T)`、`freeOwned`）

## 依赖要求

- Zig `0.15.2+`（见 `build.zig.zon`）
- 系统安装 `sqlite3` 开发库（`sqlite3.h` + 链接库）

`sqlite3` 安装方式（常见平台）：

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

## 集成到项目

推荐先远程拉取依赖：

```bash
zig fetch --save git+https://github.com/MysticalDevil/zite.git
```

执行后 Zig 会自动把依赖（`url` + `hash`）写入你的 `build.zig.zon`。
也可以手动写成：

```zig
.dependencies = .{
    .zite = .{
        .url = "git+https://github.com/MysticalDevil/zite.git",
        .hash = "zite-0.0.1-...",
    },
},
```

也可以使用 tarball 链接（可选）：

```bash
zig fetch --save https://github.com/MysticalDevil/zite/archive/refs/tags/<tag>.tar.gz
```

本地联调（可选）：

```zig
.dependencies = .{
    .zite = .{
        .path = "../zite",
    },
},
```

`build.zig`：

```zig
const zite_dep = b.dependency("zite", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zite", zite_dep.module("zite"));
```

## 快速开始

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

## 核心 API

- `orm.Db`
- `open(allocator, path)`、`exec(sql)`、`errmsg()`、`lastInsertRowId()`、`changes()`、`close()/deinit()`
- `close()` 后，`exec` 和 `Stmt.init` 会返回 `error.DbClosed`

- `orm.Stmt`
- `init(&db, sql)`、`bindOne(idx, value)`、`bindAll(.{...})`、`step()`、`reset()`、`clearbindings()`、`deinit()`
- 取列 API：`colInt`、`colBool`、`colDouble`、`colText`、`colBlob`、`colIsNull`、`colTextOwned`

- `orm.schema`
- `createTableSql(allocator, T, opts)`
- `createTableSqlFromMeta(allocator, T)`

- `orm.mapper`
- 写操作：`insert`、`update`
- 读操作：`getById`、`findOne`、`findMany`
- owned 封装：`getByIdOwned`、`findOneOwned`、`findManyOwned`
- 内存释放：`Owned(T)`、`freeOwned(T, allocator, &value)`

## 内存模型

- `Stmt.colText()` 返回 SQLite 内部缓冲区视图（在下一次 `step/reset/finalize` 后可能失效）
- mapper 读 API 会为 TEXT 切片字段分配内存（`[]u8`/`[]const u8` 场景）
- 释放方式：
  - `orm.mapper.freeOwned(T, allocator, &value)`，或
  - 使用 owned 包装并调用 `Owned(T).deinit()`

## 当前类型映射

建表生成（`schema.createTableSql*`）：
- int/uint/bool/enum -> `INTEGER`
- float -> `REAL`
- `[]u8`/`[]const u8` -> `TEXT`
- `[N]u8` -> `BLOB`
- `types.UnixMillis` -> `INTEGER`

绑定/读取当前覆盖了测试里使用的常见类型路径（int/float/bool/enum/optional/string slice）。

## 诊断日志

非测试构建默认启用 SQL 诊断日志。

测试中可显式开启：

```bash
zig build test -Ddiag_enable_in_tests=true
zig build itest -Ddiag_enable_in_tests=true
```

## 运行测试

```bash
zig build test
zig build itest
```

## 当前限制

- 不是全功能 ORM（无关系映射、迁移系统、查询构造器、连接池）
- `findOne/findMany` 仍接收原始 `where_clause` SQL 片段
- 表名/字段名应保持为受控代码输入（不要直接拼接不可信输入）

## 许可证

MIT（`LICENSE`）
