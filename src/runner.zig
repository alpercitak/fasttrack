const std = @import("std");
const detect = @import("detect.zig");
const config = @import("config.zig");

/// Runs one task. `affected_base` is the git ref to diff against, or null to run on all projects.
pub fn runTask(
    gpa: std.mem.Allocator,
    mgr: detect.Manager,
    orch: detect.Orchestrator,
    target: []const u8,
    affected_base: ?[]const u8,
    cfg: config.Config,
) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const argv = try buildArgv(arena, mgr, orch, target, affected_base);

    std.debug.print("\x1b[36m» Running: ", .{});
    for (argv, 0..) |arg, i| {
        std.debug.print("{s}{s}", .{ if (i > 0) " " else "", arg });
    }
    std.debug.print("\x1b[0m\n", .{});

    var child = std.process.Child.init(argv, arena);
    child.stdout_behavior = if (cfg.quiet) .Ignore else .Inherit;
    child.stderr_behavior = if (cfg.quiet) .Ignore else .Inherit;

    const term = child.spawnAndWait() catch |err| {
        std.debug.print("\x1b[31m✗ Task '{s}' could not start '{s}': {s}\x1b[0m\n\n", .{ target, argv[0], @errorName(err) });
        return error.TaskFailed;
    };
    switch (term) {
        .Exited => |code| if (code == 0) {
            std.debug.print("\x1b[32m✓ Task '{s}' completed\x1b[0m\n\n", .{target});
            return;
        } else {
            std.debug.print("\x1b[31m✗ Task '{s}' failed (exit code {d})\x1b[0m\n\n", .{ target, code });
        },
        else => std.debug.print("\x1b[31m✗ Task '{s}' terminated abnormally\x1b[0m\n\n", .{target}),
    }
    return error.TaskFailed;
}

/// Builds the command line for a task. All memory comes from `arena`.
pub fn buildArgv(
    arena: std.mem.Allocator,
    mgr: detect.Manager,
    orch: detect.Orchestrator,
    target: []const u8,
    affected_base: ?[]const u8,
) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;

    switch (orch) {
        .nx => {
            try argv.appendSlice(arena, &.{ execCommand(mgr), "nx" });
            if (affected_base) |base| {
                try argv.appendSlice(arena, &.{ "affected", "-t", target });
                try argv.append(arena, try std.fmt.allocPrint(arena, "--base={s}", .{base}));
            } else {
                try argv.appendSlice(arena, &.{ "run-many", "-t", target, "--all" });
            }
        },
        .turbo => {
            try argv.appendSlice(arena, &.{ execCommand(mgr), "turbo", "run", target });
            if (affected_base) |base| {
                try argv.append(arena, try std.fmt.allocPrint(arena, "--filter=[{s}...HEAD]", .{base}));
            }
        },
        else => try argv.appendSlice(arena, &.{ @tagName(mgr), "run", target }),
    }

    return argv.items;
}

/// Command that runs a binary from local node_modules for the given package manager.
/// `npm nx ...` is not valid, npm needs `npx`; pnpm and yarn resolve bins directly.
fn execCommand(mgr: detect.Manager) []const u8 {
    return switch (mgr) {
        .npm => "npx",
        .bun => "bunx",
        .pnpm => "pnpm",
        .yarn => "yarn",
    };
}

fn expectArgv(expected: []const []const u8, mgr: detect.Manager, orch: detect.Orchestrator, base: ?[]const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const actual = try buildArgv(arena_state.allocator(), mgr, orch, "lint", base);
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| try std.testing.expectEqualStrings(e, a);
}

test "buildArgv: nx" {
    try expectArgv(&.{ "pnpm", "nx", "run-many", "-t", "lint", "--all" }, .pnpm, .nx, null);
    try expectArgv(&.{ "npx", "nx", "affected", "-t", "lint", "--base=origin/main" }, .npm, .nx, "origin/main");
}

test "buildArgv: turbo" {
    try expectArgv(&.{ "yarn", "turbo", "run", "lint" }, .yarn, .turbo, null);
    try expectArgv(&.{ "bunx", "turbo", "run", "lint", "--filter=[HEAD~1...HEAD]" }, .bun, .turbo, "HEAD~1");
}

test "buildArgv: no orchestrator ignores affected" {
    try expectArgv(&.{ "npm", "run", "lint" }, .npm, .none, null);
    try expectArgv(&.{ "bun", "run", "lint" }, .bun, .bun, "origin/main");
}
