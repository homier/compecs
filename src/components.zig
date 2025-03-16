const std = @import("std");

const generate = @import("generate.zig");

fn validateIsComponentType(comptime C: anytype) void {
    if (!@hasDecl(C, "Name")) {
        @compileError(@typeName(C) ++ " missing 'pub const Name = .name;' declaration");
    }

    if (@typeInfo(@TypeOf(C.Name)) != .EnumLiteral) {
        @compileError(@typeName(C) ++ " 'Name' is not a .EnumLiteral");
    }
}

fn componentTagName(comptime C: type) [:0]const u8 {
    return @tagName(C.Name);
}

pub fn Components(comptime ComponentTypes: anytype) type {
    inline for (ComponentTypes) |component_type| {
        validateIsComponentType(component_type);
    }

    return struct {
        const Self = @This();

        pub const ComponentsEnum = generate.GenerateEnum(ComponentTypes, componentTagName);
        pub const ComponentsByName = generate.GenerateStructByName(ComponentTypes, componentTagName);

        comps: ComponentsByName,
    };
}

pub fn Component(comptime T: anytype, comptime N: anytype) type {
    return struct {
        pub const Name = N;

        v: T = undefined,
    };
}
