const build_options = @import("build_options");

pub const sqlite3 = switch (build_options.sqlite_backend) {
    .system => @import("sqlite3.zig"),
    .pure => @import("unavailable.zig"),
};

pub const pocket = switch (build_options.sqlite_backend) {
    .system => @import("unavailable.zig"),
    .pure => @import("pocket.zig"),
};

pub const default = switch (build_options.sqlite_backend) {
    .system => sqlite3,
    .pure => pocket,
};

pub fn assertDriver(comptime Driver: type) void {
    _ = Driver.DbHandle;
    _ = Driver.StmtHandle;
    _ = Driver.OK;
    _ = Driver.ROW;
    _ = Driver.DONE;
    _ = Driver.NULL;
    _ = Driver.BUSY;
    _ = Driver.CONSTRAINT;
    _ = Driver.MISUSE;
    _ = Driver.IOERR;
    _ = Driver.READONLY;
    _ = Driver.CANTOPEN;
    _ = Driver.RANGE;
    _ = Driver.TOOBIG;
    _ = Driver.NOMEM;
    _ = Driver.db.open;
    _ = Driver.db.closeImmediate;
    _ = Driver.db.closeDeferred;
    _ = Driver.db.errmsg;
    _ = Driver.db.exec;
    _ = Driver.db.lastInsertRowId;
    _ = Driver.db.changes;
    _ = Driver.stmt.prepare;
    _ = Driver.stmt.finalize;
    _ = Driver.stmt.step;
    _ = Driver.stmt.reset;
    _ = Driver.stmt.bindNull;
    _ = Driver.stmt.bindInt64;
    _ = Driver.stmt.bindDouble;
    _ = Driver.stmt.bindInt;
    _ = Driver.stmt.bindText;
    _ = Driver.stmt.bindBlob;
    _ = Driver.stmt.columnType;
    _ = Driver.stmt.columnInt;
    _ = Driver.stmt.columnInt64;
    _ = Driver.stmt.columnDouble;
    _ = Driver.stmt.columnText;
    _ = Driver.stmt.columnBlob;
    _ = Driver.stmt.columnBytes;
}
