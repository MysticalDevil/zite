const std = @import("std");

const root = @import("root.zig");
const Db = root.Db;
const Stmt = root.Stmt;

fn writeIdent(w: anytype, name: []const u8) !void {
    try w.writeByte('"');
    try w.writeAll(name);
    try w.writeByte('"');
}

pub const InsertConfig = struct {
    primary_key: []const u8 = "id",
    skip_primary_key: bool = true,
};

pub const UpdateConfig = struct {
    primary_key: []const u8 = "id",
};

fn isPk(comptime name: []const u8, comptime pk: []const u8) bool {
    return std.mem.eql(u8, name, pk);
}

/// Insert a record: Returns the rowid (typically an auto-incrementing ID)
/// Convention: field_name=column_name; primary key fields (id) are skipped by default
pub fn insert(comptime T: type, db: *Db, table_name: []const u8, entity: T, comptime cfg: InsertConfig) !i64 {
    const ti = @typeInfo(T);
    if (ti != .@"struct") @compileError("insert expects a struct type");

    const fields = ti.@"struct".fields;

    comptime var insertable_count: usize = 0;
    inline for (fields) |f| {
        const skip = comptime (cfg.skip_primary_key and isPk(f.name, cfg.primary_key));
        if (!skip) insertable_count += 1;
    }
    if (insertable_count == 0) return error.NoInsertableFields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    const w = buf.writer(db.allocator);

    try w.writeAll("INSERT INTO ");
    try writeIdent(w, table_name);
    try w.writeAll(" (");

    comptime var col_i: usize = 0;
    inline for (fields) |f| {
        const skip = comptime (cfg.skip_primary_key and isPk(f.name, cfg.primary_key));
        if (skip) continue;

        if (col_i != 0) try w.writeAll(", ");
        try writeIdent(w, f.name);
        col_i += 1;
    }

    try w.writeAll(") VALUES (");

    comptime var param_index: usize = 1;
    inline while (param_index <= insertable_count) : (param_index += 1) {
        if (param_index != 1)
            try w.writeAll(", ");
        try w.writeByte('?');
        try w.print("{}", .{param_index});
    }

    try w.writeAll(");");

    const sql = try buf.toOwnedSlice(db.allocator);
    defer db.allocator.free(sql);

    var st = try Stmt.init(db, sql);
    defer st.deinit();

    var bind_i: c_int = 1;
    inline for (fields) |f| {
        const skip = comptime (cfg.skip_primary_key and isPk(f.name, cfg.primary_key));
        if (skip) continue;

        const v = @field(entity, f.name);
        try st.bindOne(bind_i, v);
        bind_i += 1;
    }

    const r = try st.step();
    if (r != .done)
        return error.UnexpectedRowOnInsert;

    return db.lastInsertRowId();
}

/// Update a record: Returns changes() (number of affected rows)
/// SQL: UPDATE “t” SET “a”=?1, ‘b’=?2 WHERE “id”=?N;
pub fn update(comptime T: type, db: *Db, table_name: []const u8, entity: T, comptime cfg: UpdateConfig) !c_int {
    const ti = @typeInfo(T);
    if (ti != .@"struct")
        @compileError("update expects a struct type");

    const fields = ti.@"struct".fields;

    comptime var has_pk: bool = false;
    comptime var set_count: usize = 0;

    inline for (fields) |f| {
        if (comptime isPk(f.name, cfg.primary_key)) {
            has_pk = true;
        } else {
            set_count += 1;
        }
    }

    if (!has_pk)
        return error.PrimaryKeyFieldNotFound;
    if (set_count == 0)
        return error.NoUpdatableFields;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(db.allocator);
    const w = buf.writer(db.allocator);

    try w.writeAll("UPDATE ");
    try writeIdent(w, table_name);
    try w.writeAll(" SET ");

    comptime var set_i: usize = 0;
    inline for (fields) |f| {
        if (comptime isPk(f.name, cfg.primary_key))
            continue;

        if (set_i != 0)
            try w.writeAll(", ");
        try writeIdent(w, f.name);
        try w.writeAll("=?");
        try w.print("{}", .{set_i + 1});
        set_i += 1;
    }

    try w.writeAll(" WHERE ");
    try writeIdent(w, cfg.primary_key);
    try w.writeAll("=?");
    try w.print("{}", .{set_count + 1});
    try w.writeAll(";");

    const sql = try buf.toOwnedSlice(db.allocator);
    defer db.allocator.free(sql);

    var st = try Stmt.init(db, sql);
    defer st.deinit();

    var bind_i: c_int = 1;
    inline for (fields) |f| {
        if (comptime isPk(f.name, cfg.primary_key))
            continue;
        const v = @field(entity, f.name);
        try st.bindOne(bind_i, v);
        bind_i += 1;
    }

    inline for (fields) |f| {
        if (comptime isPk(f.name, cfg.primary_key)) {
            const pkv = @field(entity, f.name);
            try st.bindOne(bind_i, pkv);
            break;
        }
    }

    const r = try st.step();
    if (r != .done)
        return error.UnexpectedRowOnUpdate;

    return db.changes();
}
