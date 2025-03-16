const std = @import("std");

const entities = @import("entities.zig");
const generate = @import("generate.zig");

fn validateEntitiesType(comptime E: type) void {
    if (!@hasDecl(E, "Name")) {
        @compileError(@typeName(E) ++ " missing 'pub const Name = .name;' declaration");
    }

    if (@typeInfo(@TypeOf(E.Name)) != .EnumLiteral) {
        @compileError(@typeName(E.Name) ++ " 'pub const Name = .name;' must be a enum literal");
    }
}

fn entitiesTagName(comptime E: type) [:0]const u8 {
    return @tagName(E.Name);
}

fn systemTagName(comptime S: type) [:0]const u8 {
    return @tagName(S.Name);
}

pub fn Space(
    comptime EntitiesTypes: anytype,
    comptime SystemTypes: anytype,
) type {
    inline for (EntitiesTypes) |E| {
        validateEntitiesType(E);
    }

    return struct {
        const Self = @This();

        pub const EntitiesByName = generate.GenerateStructByName(EntitiesTypes, entitiesTagName);
        const EntitiesFieldNames = std.meta.fieldNames(EntitiesByName);

        pub const SystemsByName = generate.GenerateStructByName(SystemTypes, systemTagName);
        const SystemsFieldNames = std.meta.fieldNames(SystemsByName);

        machinery: struct {
            allocator: std.mem.Allocator,
        } = undefined,

        entities: EntitiesByName = .{},
        systems: SystemsByName = .{},

        pub fn init(self: *Self, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
            self.*.machinery = .{ .allocator = allocator };
            self.*.entities = .{};
            self.*.systems = .{};

            inline for (EntitiesFieldNames) |Name| {
                try @field(self.*.entities, Name).init(allocator);
            }

            inline for (SystemsFieldNames) |Name| {
                try @field(self.*.systems, Name).init(allocator);
            }
        }

        pub fn denit(self: *Self) void {
            inline for (EntitiesFieldNames) |Name| {
                @field(self.*.entities, Name).deinit();
                @field(self.*.entities, Name) = undefined;
            }

            inline for (SystemsFieldNames) |Name| {
                @field(self.*.systems, Name).deinit();
                @field(self.*.systems, Name) = undefined;
            }

            self.*.entities = undefined;
            self.*.systems = undefined;
            self.*.machinery = undefined;
        }

        pub fn run(self: *Self) !void {
            inline for (EntitiesFieldNames) |Name| {
                try @field(self.entities, Name).ensureFresh();
            }

            inline for (SystemsFieldNames) |Name| {
                const S = @TypeOf(@field(self.systems, Name));

                if (@hasDecl(S, "Filter")) {
                    try self.runSystemWithFilter(S, Name);
                } else if (@hasDecl(S, "NoFilter")) {
                    try self.runSystemNoFilter(Name);
                } else {
                    @compileError("invalid");
                }
            }
        }

        fn runSystemWithFilter(
            self: *Self,
            comptime S: type,
            comptime Name: [:0]const u8,
        ) !void {
            const Filter = S.Filter;

            inline for (EntitiesFieldNames) |EntitiesName| {
                if (@field(self.entities, EntitiesName).hasComponents(Filter)) {
                    var slice = @field(self.entities, EntitiesName).slice(Filter);
                    const slicer: EntitySlicer(Filter) = EntitySlicer(Filter).from(
                        &slice,
                        @TypeOf(slice),
                    );

                    try @field(self.systems, Name).run(self, &slicer);
                }
            }
        }

        fn runSystemNoFilter(self: *Self, comptime Name: [:0]const u8) !void {
            try @field(self.systems, Name).run(self);
        }
    };
}

pub fn EntitySlicer(comptime C: anytype) type {
    return struct {
        const Self = @This();

        ptr: *anyopaque,
        impl: *const Interface,

        const Interface = struct {
            next: *const fn (ctx: *anyopaque) ?entities.Entity(C),
            update: *const fn (ctx: *anyopaque, entity: entities.Entity(C)) void,
            remove: *const fn (ctx: *anyopaque, id: entities.EntityID) std.mem.Allocator.Error!void,

            pub fn init(T: type) *const Interface {
                return &.{
                    .next = &struct {
                        fn next(ctx: *anyopaque) ?entities.Entity(C) {
                            const self: *T = @ptrCast(@alignCast(ctx));

                            return self.next();
                        }
                    }.next,
                    .update = &struct {
                        fn update(ctx: *anyopaque, entity: entities.Entity(C)) void {
                            const self: *T = @ptrCast(@alignCast(ctx));

                            return self.update(entity);
                        }
                    }.update,
                    .remove = &struct {
                        fn remove(ctx: *anyopaque, id: entities.EntityID) std.mem.Allocator.Error!void {
                            const self: *T = @ptrCast(@alignCast(ctx));

                            return try self.remove(id);
                        }
                    }.remove,
                };
            }
        };

        pub fn from(ctx: *anyopaque, T: type) EntitySlicer(C) {
            return .{
                .ptr = ctx,
                .impl = Interface.init(T),
            };
        }

        pub fn next(self: *const Self) ?entities.Entity(C) {
            return self.impl.next(self.ptr);
        }

        pub fn update(self: *const Self, entity: entities.Entity(C)) void {
            return self.impl.update(self.ptr, entity);
        }

        pub fn remove(self: *const Self, id: entities.EntityID) std.mem.Allocator.Error!void {
            return self.impl.remove(self.ptr, id);
        }
    };
}
