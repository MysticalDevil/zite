const Driver = @import("../../driver/sqlite3.zig");
const Stmt = @import("../../db/stmt.zig").Stmt(Driver);
const meta = @import("../../core/meta.zig");
const errors = @import("../../core/errors.zig");

/// Steps once and enforces SQLITE_DONE.
pub fn stepExpectDone(st: *Stmt, err_on_row: anytype) (errors.StmtError || @TypeOf(err_on_row))!void {
    const r = try st.step();
    if (r != .done) {
        return err_on_row;
    }
}

/// Steps once and reports whether a row was produced.
pub fn stepIsRow(st: *Stmt) errors.StmtError!bool {
    const r = try st.step();
    return r == .row;
}

/// Resets a reusable statement on iteration i>0.
pub fn resetForReuse(st: *Stmt, i: usize) errors.StmtError!void {
    if (i != 0) {
        try st.reset();
    }
}

pub fn bindInsertValues(comptime T: type, st: *Stmt, entity: T) errors.StmtError!void {
    const ti = @typeInfo(T);
    if (ti != .@"struct") {
        @compileError("bindInsertValues expects a struct type");
    }
    const m = comptime meta.getMeta(T);

    const fields = ti.@"struct".fields;
    var bind_i: i32 = 1;
    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) {
            continue;
        }
        const skip = comptime (m.skip_primary_key_on_insert and meta.isPk(f.name, m.primary_key));
        if (skip) {
            continue;
        }

        try st.bindOne(bind_i, @field(entity, f.name));
        bind_i += 1;
    }
}

pub fn bindUpdateValues(comptime T: type, st: *Stmt, entity: T) errors.StmtError!void {
    const ti = @typeInfo(T);
    if (ti != .@"struct") {
        @compileError("bindUpdateValues expects a struct type");
    }
    const m = comptime meta.getMeta(T);

    const fields = ti.@"struct".fields;
    var bind_i: i32 = 1;

    inline for (fields) |f| {
        if (comptime meta.isSkipped(f.name, m)) {
            continue;
        }
        if (comptime meta.isPk(f.name, m.primary_key)) {
            continue;
        }
        try st.bindOne(bind_i, @field(entity, f.name));
        bind_i += 1;
    }

    inline for (fields) |f| {
        if (comptime meta.isPk(f.name, m.primary_key)) {
            // The PK predicate is bound last and `bind_i` is not used after this.
            try st.bindOne(bind_i, @field(entity, f.name));
            break;
        }
    }
}
