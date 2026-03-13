const std = @import("std");
const zite = @import("zite");

const OwnedText = zite.types.OwnedText;

const User = struct {
    id: i64,
    name: OwnedText,

    pub const Meta = .{
        .table = "users",
        .primary_key = "id",
    };
};

pub fn main(init: std.process.Init) !void {
    const a = init.gpa;

    var name_value: []const u8 = "alice";
    var it = std.process.Args.Iterator.init(init.minimal.args);
    defer it.deinit();
    _ = it.skip();
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--name=")) {
            name_value = arg["--name=".len..];
        }
    }

    var db = try zite.Db.open(a, ":memory:");
    defer db.deinit();

    const ddl = try zite.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var user = User{
        .id = 1,
        .name = try OwnedText.fromConst(a, name_value),
    };
    defer zite.mapper.freeOwnedRow(User, a, &user);
    _ = try zite.mapper.insert(User, &db, user);

    if (try zite.mapper.findByIdOwned(User, &db, a, 1)) |row| {
        var owned = row;
        defer owned.deinit();
        std.debug.print("user name={s}\n", .{owned.value.name.value});
    }
}
