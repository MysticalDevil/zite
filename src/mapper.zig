const std = @import("std");
const root = @import("root.zig");

const Db = root.Db;
const Stmt = root.Stmt;

const meta = @import("meta.zig");
const sqlutil = @import("sqlutil.zig");

pub fn insert(comptime T: type, db: *Db, entity: T) !i64 {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("insert expects a struct type");

    const m = comptime meta.getMeta(T);
    const ncols = comptime meta.insertableCount(T, m);
    if (ncols == 0) return error.NoInsertableFields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    const w0 = buf.writer(db.allocator);
    const w = w0.any();

    try w.writeAll("INSERT INTO ");
    try sqlutil.writeIdent(w, m.table);
    try w.writeAll(" (");
    try sqlutil.writeInsertColumnList(w, T, m);
    try w.writeAll(") VALUES (");
    try sqlutil.writePlaceholders(w, ncols);
    try w.writeAll(");");

    const sql = try buf.toOwnedSlice(db.allocator);
    defer db.allocator.free(sql);

    var st = try Stmt.init(db, sql);
    defer st.deinit();

    const fields = ti.@"struct".fields;
    var bind_i: c_int = 1;

    inline for (fields) |f| {
        const skip = comptime (m.skip_primary_key_on_insert and meta.isPk(f.name, m.primary_key));
        if (skip) continue;

        try st.bindOne(bind_i, @field(entity, f.name));
        bind_i += 1;
    }

    const r = try st.step();
    if (r != .done) return error.UnexpectedRowOnInsert;

    return db.lastInsertRowId();
}

pub fn update(comptime T: type, db: *Db, entity: T) !c_int {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("update expects a struct type");

    const m = comptime meta.getMeta(T);

    comptime {
        if (!meta.hasPrimaryKeyField(T, m)) {
            @compileError("Type " ++ @typeName(T) ++ " does not contain primary key field: " ++ m.primary_key);
        }
    }

    const set_count = comptime meta.updateSetCount(T, m);
    if (set_count == 0) return error.NoUpdatableFields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    const w0 = buf.writer(db.allocator);
    const w = w0.any();

    try w.writeAll("UPDATE ");
    try sqlutil.writeIdent(w, m.table);
    try w.writeAll(" SET ");
    try sqlutil.writeUpdateSetClause(w, T, m);

    try w.writeAll(" WHERE ");
    try sqlutil.writeIdent(w, m.primary_key);
    try w.writeAll("=?");
    try w.print("{}", .{set_count + 1});
    try w.writeAll(";");

    const sql = try buf.toOwnedSlice(db.allocator);
    defer db.allocator.free(sql);

    var st = try Stmt.init(db, sql);
    defer st.deinit();

    const fields = ti.@"struct".fields;
    var bind_i: c_int = 1;

    inline for (fields) |f| {
        if (comptime meta.isPk(f.name, m.primary_key)) continue;
        try st.bindOne(bind_i, @field(entity, f.name));
        bind_i += 1;
    }

    // pk 最后一个参数
    inline for (fields) |f| {
        if (comptime meta.isPk(f.name, m.primary_key)) {
            try st.bindOne(bind_i, @field(entity, f.name));
            break;
        }
    }

    const r = try st.step();
    if (r != .done) return error.UnexpectedRowOnUpdate;

    return db.changes();
}
