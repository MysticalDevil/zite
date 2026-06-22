const std = @import("std");

pub const StructField = struct {
    name: [:0]const u8,
    type: type,
};

pub fn structFields(comptime T: type) []const StructField {
    const ti = @typeInfo(T);
    if (ti != .@"struct") {
        @compileError("structFields expects a struct type");
    }

    const info = ti.@"struct";
    const Fields = struct {
        pub const data: [info.field_names.len]StructField = blk: {
            var fields: [info.field_names.len]StructField = undefined;
            for (info.field_names, info.field_types, 0..) |name, FieldT, i| {
                fields[i] = .{
                    .name = name,
                    .type = FieldT,
                };
            }
            break :blk fields;
        };
    };
    return &Fields.data;
}

test "reflect: structFields exposes names and types" {
    const Sample = struct {
        id: i64,
        name: []const u8,
    };

    const fields = comptime structFields(Sample);
    try std.testing.expectEqual(@as(usize, 2), fields.len);
    try std.testing.expectEqualStrings("id", fields[0].name);
    try std.testing.expect(fields[0].type == i64);
    try std.testing.expectEqualStrings("name", fields[1].name);
    try std.testing.expect(fields[1].type == []const u8);
}
