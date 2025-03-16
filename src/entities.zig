const std = @import("std");
const uuid = @import("uuid");

const components = @import("components.zig");
const generate = @import("generate.zig");

pub const EntityID = u64;

pub fn Entity(comptime ComponentTypes: anytype) type {
    return struct {
        id: EntityID,
        comps: components.Components(ComponentTypes).ComponentsByName,
    };
}

pub fn Entities(comptime ComponentTypes: anytype, comptime EntityName: anytype) type {
    if (@typeInfo(@TypeOf(EntityName)) != .EnumLiteral) {
        @compileError(@typeName(EntityName) ++ " 'EntityName' must be a .EnumLiteral");
    }

    return struct {
        const Self = @This();

        pub const Name = EntityName;
        pub const Components = ComponentTypes.ComponentsByName;
        pub const ComponentsField = std.meta.FieldEnum(Components);

        const NewQueue = std.DoublyLinkedList(Components);

        machinery: struct {
            allocator: std.mem.Allocator,
            new: NewQueue = .{},
            dead: std.bit_set.DynamicBitSetUnmanaged = .{},
        } = undefined,

        data: std.MultiArrayList(Components) = undefined,

        pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
            self.* = .{
                .data = .{},
                .machinery = .{
                    .allocator = allocator,
                    .new = .{},
                    .dead = .{},
                },
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit(self.machinery.allocator);
            self.machinery.dead.deinit(self.machinery.allocator);

            while (self.machinery.new.popFirst()) |node| {
                self.machinery.allocator.destroy(node);
            }
        }

        pub fn new(self: *Self) std.mem.Allocator.Error!EntityID {
            const allocator = self.machinery.allocator;

            // Check if we have at least one dead entity,
            // and if yes, we mark it as non-dead at zero its value
            if (self.machinery.dead.findFirstSet()) |idx| {
                if (idx < self.data.len) {
                    self.machinery.dead.unset(idx);
                    self.data.set(idx, .{});

                    return idx;
                }
            }

            try self.data.ensureUnusedCapacity(allocator, 1);
            try self.machinery.dead.resize(allocator, self.data.capacity, false);

            self.data.appendAssumeCapacity(.{});

            return self.data.len - 1;
        }

        pub fn append(self: *Self, comps: Components) std.mem.Allocator.Error!void {
            const allocator = self.machinery.allocator;

            const node = try allocator.create(NewQueue.Node);
            node.*.data = comps;

            self.machinery.new.append(node);
        }

        pub fn ensureFresh(self: *Self) std.mem.Allocator.Error!void {
            const allocator = self.machinery.allocator;
            var requestedCapacity: usize = self.machinery.new.len;

            if (requestedCapacity == 0) {
                return;
            }

            while (self.machinery.new.popFirst()) |node| {
                // If we've got a dead item, we simply replace that item
                // in data array and mark its index as non-dead.
                if (self.machinery.dead.toggleFirstSet()) |idx| {
                    // Reducing an amount of future-requesting capacity for the main array,
                    // since we set the new item in the dead index, which exists.
                    requestedCapacity -= 1;

                    self.data.set(idx, node.*.data);

                    allocator.destroy(node);
                    continue;
                }

                // No dead entities found, so we return new item to the queue
                // to append it in main data array.
                self.machinery.new.prepend(node);
                break;
            }

            // We reused dead items
            if (requestedCapacity == 0) {
                return;
            }

            // Ensuing that data array has enough capacity to add new items
            try self.data.ensureUnusedCapacity(allocator, requestedCapacity);

            while (self.machinery.new.popFirst()) |node| {
                defer allocator.destroy(node);

                self.data.appendAssumeCapacity(node.data);
            }
        }

        pub fn set(
            self: *Self,
            id: EntityID,
            comptime component: ComponentsField,
            value: std.meta.FieldType(Components, component),
        ) void {
            self.data.items(component)[id] = value;
        }

        pub fn setFull(self: *Self, id: EntityID, comps: Components) void {
            self.data.set(id, comps);
        }

        pub fn get(
            self: *const Self,
            id: EntityID,
            comptime component: ComponentsField,
        ) ?std.meta.FieldType(Components, component) {
            if (id > self.data.len - 1) {
                return null;
            }

            return self.data.items(component)[id];
        }

        pub fn getFull(self: *const Self, id: EntityID) ?Components {
            if (id > self.data.len - 1) {
                return null;
            }

            return self.data.get(id);
        }

        pub fn remove(self: *Self, id: EntityID) std.mem.Allocator.Error!void {
            if (self.machinery.dead.bit_length > id) {
                if (self.machinery.dead.isSet(id)) {
                    return;
                }
            }

            if (id > self.data.len - 1) {
                return;
            }

            try self.machinery.dead.resize(self.machinery.allocator, self.machinery.dead.bit_length + 1, true);
            self.machinery.dead.set(id);
        }

        pub fn hasComponents(_: *const Self, comptime C: anytype) bool {
            inline for (C) |Component| {
                if (!@hasDecl(Component, "Name")) {
                    @compileError(@typeName(Component) ++ " component type missing 'pub const Name = .name;' declaration");
                }

                if (!@hasField(ComponentsField, @tagName(Component.Name))) {
                    return false;
                }
            }

            return true;
        }

        pub fn Slice(comptime C: anytype) type {
            return struct {
                const E = Entities(ComponentTypes, EntityName);

                index: usize = 0,
                entities: *E,

                pub fn next(self: *@This()) ?Entity(C) {
                    if (self.index == self.entities.data.len) {
                        return null;
                    }

                    while (self.index < self.entities.data.len) {
                        defer self.index += 1;

                        if (self.index + 1 <= self.entities.machinery.dead.bit_length) {
                            if (self.entities.machinery.dead.isSet(self.index)) {
                                continue;
                            }
                        }

                        var e: Entity(C) = .{
                            .id = self.index,
                            .comps = .{},
                        };

                        inline for (C) |Component| {
                            @field(e.comps, @tagName(Component.Name)) = self.entities.data.items(Component.Name)[self.index];
                        }

                        return e;
                    }

                    return null;
                }

                pub fn update(self: *@This(), entity: Entity(C)) void {
                    inline for (C) |Component| {
                        self.entities.set(entity.id, Component.Name, @field(entity.comps, @tagName(Component.Name)));
                    }
                }

                pub fn remove(self: *@This(), id: EntityID) std.mem.Allocator.Error!void {
                    try self.entities.remove(id);
                }
            };
        }

        // fn getFilterFields(comptime filters: anytype) []const ComponentsField {
        //     comptime var fields: []const ComponentsField = &[0]ComponentsField{};
        //     inline for (filters) |f| {
        //         if (@typeInfo(@TypeOf(f)) != .EnumLiteral) {
        //             @compileError("unknown filter type: " ++ @typeName(f));
        //         }
        //
        //         fields = fields ++ [_]ComponentsField{@as(ComponentsField, f)};
        //     }
        //
        //     return fields;
        // }

        pub fn slice(self: *Self, comptime C: anytype) Slice(C) {
            return .{ .entities = self };
        }
    };
}
