const std = @import("std");

pub fn GenerateEnum(comptime Types: anytype, tagFn: *const fn (comptime T: type) [:0]const u8) type {
    var fields: []const std.builtin.Type.EnumField = &[0]std.builtin.Type.EnumField{};

    for (Types, 0..) |T, i| {
        fields = fields ++ [_]std.builtin.Type.EnumField{.{
            .name = tagFn(T),
            .value = i,
        }};
    }

    return @Type(.{
        .Enum = .{
            .tag_type = std.math.IntFittingRange(0, fields.len - 1),
            .fields = fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_exhaustive = true,
        },
    });
}

pub fn GenerateStructByName(comptime Types: anytype, tagFn: *const fn (comptime T: type) [:0]const u8) type {
    var fields: []const std.builtin.Type.StructField = &[0]std.builtin.Type.StructField{};

    for (Types) |T| {
        fields = fields ++ [_]std.builtin.Type.StructField{.{
            .name = tagFn(T),
            .type = T,
            .default_value = &@as(T, undefined),
            .is_comptime = false,
            .alignment = @alignOf(T),
        }};
    }

    return @Type(.{
        .Struct = .{
            .layout = .auto,
            .is_tuple = false,
            .fields = fields,
            .decls = &[_]std.builtin.Type.Declaration{},
        },
    });
}
