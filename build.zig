const std = @import("std");

const Example = struct {
    name: []const u8,
    path: []const u8,
    desc: []const u8,
};

fn getModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return b.addModule("compecs", .{
        .root_source_file = b.path("src/compecs.zig"),
        .target = target,
        .optimize = optimize,
    });
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const compecs = getModule(b, target, optimize);
    const examples = [_]Example{
        .{
            .name = "rockets",
            .path = "examples/rockets.zig",
            .desc = "Simple ECS space example",
        },
    };

    const examples_step = b.step("examples", "Builds all the examples");
    for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = b.path(example.path),
            .optimize = optimize,
            .target = target,
        });

        exe.root_module.addImport("compecs", compecs);

        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step(example.name, example.desc);

        run_step.dependOn(&run_cmd.step);
        examples_step.dependOn(&exe.step);
    }
}
