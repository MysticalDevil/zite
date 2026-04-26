const std = @import("std");
const zite = @import("zite");
const Driver = zite.drivers.sqlite3;
const Db = zite.Db(Driver);

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

    var db = try Db.open(a, ":memory:");
    defer db.deinit();
    var repo = zite.repository(User, &db, a);

    const ddl = try zite.schema.createTableSqlFromMeta(a, User);
    defer a.free(ddl);
    try db.exec(ddl);

    var user = User{
        .id = 1,
        .name = try OwnedText.fromConst(a, name_value),
    };
    defer repo.freeOwnedRow(&user);
    _ = try repo.insert(user);

    if (try repo.findByIdOwned(@as(i64, 1))) |row| {
        var owned = row;
        defer owned.deinit();
        std.debug.print("user name={s}\n", .{owned.value.name.value});
    }
}
