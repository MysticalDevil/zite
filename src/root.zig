pub const raw = @import("raw/sqlite3.zig");

const db = struct {
    pub const Db = @import("db/db.zig").Db;
    pub const Stmt = @import("db/stmt.zig").Stmt;
    pub const StepResult = @import("db/stmt.zig").StepResult;
    pub const diag = @import("db/diag.zig");
};

pub const Db = db.Db;
pub const Stmt = db.Stmt;
pub const StepResult = db.StepResult;

pub const mapper = @import("orm/mapper.zig");
pub const types = @import("core/types.zig");
pub const meta = @import("core/meta.zig");
pub const sqlutil = @import("core/sqlutil.zig");
pub const schema = @import("orm/schema.zig");

pub const Owned = mapper.Owned;
