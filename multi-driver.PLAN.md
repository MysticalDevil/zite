# Multi-Driver Support Plan

## Overview

支持多种 SQLite 后端驱动（系统 libsqlite3、纯 Zig 实现如 pocket.io），保持现有 API 稳定。

## Design Principles

1. **Zig 风格优先**：避免 Rust 风格的 `mod.zig`，使用 Zig 惯用的命名
2. **编译时抽象**：使用 `comptime` 泛型而非运行时 vtable
3. **零开销**：选择驱动在编译期确定，无运行时开销
4. **渐进式迁移**：保持现有 `Db`/`Stmt` API 不变

---

## Phase 1: Rename `mod.zig` → Zig Conventions

当前 `src/raw/mod.zig` 使用 Rust 风格命名，改为 Zig 惯用方式。

### Changes

| Before | After |
|--------|-------|
| `src/raw/mod.zig` | `src/raw/root.zig` |

### Rationale

Zig 标准库使用 `root.zig` 作为模块入口，`mod` 是 Rust 惯例。

### Affected Files

- `src/raw/mod.zig` → `src/raw/root.zig`
- `src/db/db.zig`: `@import("../raw/mod.zig")` → `@import("../raw/root.zig")`
- `src/db/stmt.zig`: 同上
- `src/root.zig`: `@import("raw/mod.zig")` → `@import("raw/root.zig")`

---

## Phase 2: Define Driver Interface

在 `src/driver/` 创建驱动抽象层。

### New Files

```
src/driver/
├── root.zig          # 入口，导出 Driver trait
├── sqlite3.zig       # libsqlite3 系统库驱动
└── traits.zig        # Driver 接口定义
```

### `src/driver/traits.zig`

```zig
/// 数据库句柄抽象 - 不同驱动实现自己的 opaque 类型。
pub fn DbHandle(comptime Self: type) type {
    return struct {
        ptr: *Self,
    };
}

/// 语句句柄抽象。
pub fn StmtHandle(comptime Self: type) type {
    return struct {
        ptr: *Self,
    };
}

/// 驱动接口 - 使用 struct 静态函数表。
/// 
/// 每个 driver 必须提供以下函数：
/// - open(path: [*:0]const u8, out: *?DbHandle) Rc
/// - closeDeferred(handle: DbHandle) Rc
/// - closeImmediate(handle: DbHandle) Rc
/// - exec(handle: DbHandle, sql: [*:0]const u8) Rc
/// - errmsg(handle: DbHandle) ?[*:0]const u8
/// - lastInsertRowId(handle: DbHandle) i64
/// - changes(handle: DbHandle) i32
/// - prepare(db: DbHandle, sql: [*]const u8, n: i32, out: *?StmtHandle) Rc
/// - finalize(stmt: StmtHandle) Rc
/// - step(stmt: StmtHandle) Rc
/// - reset(stmt: StmtHandle) Rc
/// - bindNull/Int64/Double/Int/Text/Blob(...)
/// - columnType/Int/Int64/Double/Text/Blob/Bytes(...)
/// 
/// 返回码约定（Rc = i32）：
/// - OK = 0
/// - ROW = 100
/// - DONE = 101
/// - NULL = 5
/// - 其他错误码由各驱动定义
pub fn Driver(
    comptime DbH: type,
    comptime StmtH: type,
    comptime impl: any type,
) type {
    return struct {
        pub const DbHandleType = DbH;
        pub const StmtHandleType = StmtH;
        
        pub const open = impl.open;
        pub const closeDeferred = impl.closeDeferred;
        pub const closeImmediate = impl.closeImmediate;
        // ... 其他函数转发
    };
}
```

### `src/driver/sqlite3.zig`

将 `src/raw/` 现有代码迁移至此，作为 sqlite3 驱动实现：

```zig
const c = @cImport({ @cInclude("sqlite3.h"); });

pub const sqlite3 = c.sqlite3;
pub const sqlite3_stmt = c.sqlite3_stmt;

pub const DbHandle = struct { ptr: *sqlite3 };
pub const StmtHandle = struct { ptr: *sqlite3_stmt };

pub const Rc = i32;
pub const OK: Rc = c.SQLITE_OK;
pub const ROW: Rc = c.SQLITE_ROW;
pub const DONE: Rc = c.SQLITE_DONE;
pub const NULL: Rc = c.SQLITE_NULL;

// ... 其他常量

pub fn open(path: [*:0]const u8, out: *?DbHandle) Rc { ... }
pub fn closeDeferred(h: DbHandle) Rc { ... }
pub fn closeImmediate(h: DbHandle) Rc { ... }
// ... 所有 raw/db.zig 和 raw/stmt.zig 的函数合并
```

---

## Phase 3: Generic Db/Stmt

将 `Db` 和 `Stmt` 改为泛型，接受 driver 参数。

### `src/db/db.zig`

```zig
const std = @import("std");
const Driver = @import("../driver/traits.zig");

pub fn Db(comptime driver: type) type {
    return struct {
        allocator: std.mem.Allocator,
        handle: driver.DbHandle,
        active_stmts: i32 = 0,

        const Self = @This();

        pub fn open(allocator: std.mem.Allocator, path: []const u8) !Self {
            const path_z = try allocator.dupeZ(u8, path);
            defer allocator.free(path_z);

            var db_handle: ?driver.DbHandle = null;
            const rc = driver.open(path_z.ptr, &db_handle);
            if (rc != driver.OK or db_handle == null) {
                // ... 错误处理
            }
            return .{ .allocator = allocator, .handle = db_handle.? };
        }

        pub fn close(self: *Self) void {
            _ = driver.closeDeferred(self.handle);
        }

        // ... 其他方法
    };
}
```

### `src/db/stmt.zig`

类似重构为泛型：

```zig
pub fn Stmt(comptime driver: type) type {
    return struct {
        db: *Db(driver),
        handle: driver.StmtHandle,
        // ...
    };
}
```

---

## Phase 4: Convenience Types

为保持现有 API 兼容，提供默认类型别名。

### `src/root.zig`

```zig
const driver = @import("driver/root.zig");
const sqlite3 = @import("driver/sqlite3.zig");

/// 默认使用 libsqlite3 驱动。
pub const DefaultDriver = sqlite3;

/// 数据库连接（使用默认驱动）。
pub const Db = @import("db/db.zig").Db(DefaultDriver);

/// 预编译语句（使用默认驱动）。
pub const Stmt = @import("db/stmt.zig").Stmt(DefaultDriver);

/// 纯 Zig 驱动（如果可用）。
pub const pocket = @import("driver/pocket.zig");
```

---

## Phase 5: Add Pure Zig Backend (Optional)

在 `src/driver/pocket.zig` 添加纯 Zig SQLite 实现绑定：

```zig
const pocket = @import("pocket-io"); // 假设的纯 Zig SQLite 库

pub const DbHandle = struct { ptr: *pocket.Database };
pub const StmtHandle = struct { ptr: *pocket.Statement };

pub const Rc = i32;
pub const OK: Rc = 0;
pub const ROW: Rc = 100;
pub const DONE: Rc = 101;
pub const NULL: Rc = 5;

pub fn open(path: [*:0]const u8, out: *?DbHandle) Rc { ... }
// ... 实现所有驱动接口函数
```

### 使用方式

```zig
const zite = @import("zite");
const pocket = zite.pocket;

// 使用默认驱动（libsqlite3）
var db = try zite.Db.open(alloc, ":memory:");

// 使用纯 Zig 驱动
const PocketDb = zite.Db(pocket);
var db2 = try PocketDb.open(alloc, ":memory:");
```

---

## Phase 6: Update build.zig

支持编译时选择驱动：

```zig
const DriverOption = enum {
    sqlite3,
    pocket,
};

pub fn build(b: *std.Build) void {
    const driver: DriverOption = b.option(DriverOption, "driver", "Database driver") 
        orelse .sqlite3;

    const zite_mod = b.addModule("zite", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    switch (driver) {
        .sqlite3 => zite_mod.linkSystemLibrary("sqlite3", .{ .needed = true }),
        .pocket => {
            // 编译时注入 pocket 驱动选项
            // 可能需要不同的构建配置
        },
    }

    // ...
}
```

---

## Phase 7: Error Handling Unification

错误码需要统一映射：

### `src/core/errors.zig`

已有 `SqliteMappedError`，可重命名为更通用的名称：

```zig
/// 数据库驱动错误码映射。
pub const DriverError = error{
    DriverError,
    DriverBusy,
    DriverConstraint,
    // ...
};

/// 别名保持向后兼容。
pub const SqliteMappedError = DriverError;
```

---

## Migration Steps Summary

1. **Phase 1**: 重命名 `mod.zig` → `root.zig`
2. **Phase 2**: 创建 `src/driver/` 目录，定义 `traits.zig`
3. **Phase 3**: 将 `src/raw/` 迁移到 `src/driver/sqlite3.zig`
4. **Phase 4**: `Db`/`Stmt` 改为编译时泛型
5. **Phase 5**: 添加其他驱动（可选）
6. **Phase 6**: 更新 `build.zig`
7. **Phase 7**: 统一错误命名

---

## Breaking Changes

| 变更 | 影响 | 迁移方案 |
|------|------|----------|
| `raw` 模块移至 `driver/sqlite3` | 使用 `raw` 的代码需改为 `driver.sqlite3` | 保持 `raw` 作为别名一段时间 |
| `mod.zig` 重命名 | `@import("raw/mod.zig")` 失效 | 搜索替换为 `raw/root.zig` |
| 错误类型重命名 | `SqliteMappedError` 改名 | 提供别名 |

---

## Non-Goals

- 不支持运行时切换驱动（编译时确定）
- 不支持多驱动同时使用（可以，但需要显式类型参数）
- 不抽象 SQL 方言差异（仅针对 SQLite 兼容实现）
