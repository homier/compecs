const std = @import("std");

const compecs = @import("compecs");

const Components = compecs.Components;
const Component = compecs.Component;
const Entity = compecs.Entity;
const Entities = compecs.Entities;
const EntityID = compecs.EntityID;
const Space = compecs.Space;
const EntitySlicer = compecs.EntitySlicer;
const System = compecs.System;

const Velocity = struct {
    pub const Name = .velocity;

    x: f32 = 0.0,
    y: f32 = 0.0,
};

const Position = struct {
    pub const Name = .position;

    x: f32 = 0.0,
    y: f32 = 0.0,
};

pub const Rockets = Entities(Components(.{
    Velocity,
    Position,
}), .rocket);

pub const VelocitySystem = struct {
    const Self = @This();
    const Slicer = EntitySlicer(Filter);

    pub const Name = .velocity_system;
    pub const Filter = .{Velocity};

    machinery: struct {
        allocator: std.mem.Allocator,
    } = undefined,

    pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
        self.*.machinery = .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.*.machinery = undefined;
    }

    pub fn run(_: *const Self, _: *Cosmos, slicer: *const Slicer) !void {
        std.log.debug("Running system: {}", .{Name});

        while (slicer.next()) |entity| {
            std.log.debug("Received entity: {}", .{entity});

            var updated = entity;
            updated.comps.velocity.x += 1.0;
            updated.comps.velocity.y += 2.0;

            slicer.update(updated);
        }
    }
};

pub const PositionSystem = struct {
    const Self = @This();
    const Slicer = EntitySlicer(Filter);

    pub const Name = .position_system;
    pub const Filter = .{Position};

    machinery: struct {
        allocator: std.mem.Allocator,
    } = undefined,

    pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
        self.*.machinery = .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.*.machinery = undefined;
    }

    pub fn run(_: *const Self, _: *Cosmos, slicer: *const Slicer) !void {
        std.log.debug("Running system: {}", .{Name});

        while (slicer.next()) |entity| {
            std.log.debug("Received entity: {}", .{entity});

            var updated = entity;
            updated.comps.position.x += 1.0;
            updated.comps.position.y += 2.0;

            slicer.update(updated);
        }
    }
};

pub const InitSystem = struct {
    const Self = @This();

    pub const Name = .init;
    pub const NoFilter = void;

    machinery: struct {
        allocator: std.mem.Allocator,
    } = undefined,

    initialized: bool = false,

    pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
        self.*.machinery = .{ .allocator = allocator };
        self.*.initialized = false;
    }

    pub fn deinit(self: *Self) void {
        self.*.machinery = undefined;
    }

    pub fn run(self: *Self, space: *Cosmos) !void {
        if (self.initialized) {
            return;
        }

        defer self.initialized = true;

        _ = try space.entities.rocket.new();
    }
};

pub const Cosmos = Space(.{Rockets}, .{
    InitSystem,
    VelocitySystem,
    PositionSystem,
});

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var space: Cosmos = undefined;
    try space.init(allocator);
    defer space.denit();

    while (true) {
        try space.run();
        std.time.sleep(std.time.ns_per_s);
    }
}
