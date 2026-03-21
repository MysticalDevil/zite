pub const Rc = i32;
pub const OK: Rc = 0;
pub const ROW: Rc = 100;
pub const DONE: Rc = 101;
pub const NULL: Rc = 5;
pub const BUSY: Rc = 5;
pub const CONSTRAINT: Rc = 19;
pub const MISUSE: Rc = 21;
pub const IOERR: Rc = 10;
pub const READONLY: Rc = 8;
pub const CANTOPEN: Rc = 14;
pub const RANGE: Rc = 25;
pub const TOOBIG: Rc = 18;
pub const NOMEM: Rc = 7;

pub const SQLITE_OK = OK;
pub const SQLITE_ROW = ROW;
pub const SQLITE_DONE = DONE;
pub const SQLITE_NULL = NULL;

pub const DbHandle = struct {
    _dummy: u8 = 0,
};

pub const StmtHandle = struct {
    _dummy: u8 = 0,
};

pub const db = struct {
    pub fn open(_: [*]const u8, _: *?DbHandle) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn closeImmediate(_: DbHandle) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn closeDeferred(_: DbHandle) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn errmsg(_: DbHandle) ?[*:0]const u8 {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn exec(_: DbHandle, _: [*]const u8) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn lastInsertRowId(_: DbHandle) i64 {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn changes(_: DbHandle) i32 {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
};

pub const stmt = struct {
    pub fn prepare(_: DbHandle, _: [*]const u8, _: i32, _: *?StmtHandle) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn finalize(_: StmtHandle) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn step(_: StmtHandle) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn reset(_: StmtHandle) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn bindNull(_: StmtHandle, _: i32) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn bindInt64(_: StmtHandle, _: i32, _: i64) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn bindDouble(_: StmtHandle, _: i32, _: f64) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn bindInt(_: StmtHandle, _: i32, _: i32) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn bindText(_: StmtHandle, _: i32, _: [*]const u8, _: i32) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn bindBlob(_: StmtHandle, _: i32, _: [*]const u8, _: i32) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn columnType(_: StmtHandle, _: i32) Rc {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn columnInt(_: StmtHandle, _: i32) i32 {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn columnInt64(_: StmtHandle, _: i32) i64 {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn columnDouble(_: StmtHandle, _: i32) f64 {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn columnText(_: StmtHandle, _: i32) ?[*]const u8 {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn columnBlob(_: StmtHandle, _: i32) ?*const anyopaque {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
    pub fn columnBytes(_: StmtHandle, _: i32) i32 {
        @compileError("This driver is unavailable in current build. Check -Dsqlite_backend.");
    }
};
