const std = @import("std");
const detect = @import("detect.zig");
const config = @import("config.zig");

/// Runs the given tasks and returns true if all of them succeeded.
/// `affected_base` is the git ref to diff against, or null to run on all projects.
///
/// With `cfg.parallel`, nx and turbo get every target in one call so they schedule,
/// cache and print the work themselves. Without an orchestrator, one process is
/// started per task and they run at the same time.
pub fn runTasks(
    gpa: std.mem.Allocator,
    mgr: detect.Manager,
    orch: detect.Orchestrator,
    targets: []const []const u8,
    affected_base: ?[]const u8,
    cfg: config.Config,
) !bool {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const groups: []const []const []const u8 = if (cfg.parallel and (orch == .nx or orch == .turbo))
        &.{targets}
    else blk: {
        const singles = try arena.alloc([]const []const u8, targets.len);
        for (singles, targets) |*s, *t| s.* = t[0..1];
        break :blk singles;
    };

    const children = try arena.alloc(std.process.Child, groups.len);
    const started = try arena.alloc(bool, groups.len);
    const labels = try arena.alloc([]const u8, groups.len);
    var ok = true;

    for (groups, children, started, labels) |group, *child, *was_started, *label| {
        label.* = try std.mem.join(arena, ", ", group);
        const argv = try buildArgv(arena, mgr, orch, group, affected_base);

        std.debug.print("\x1b[36m» Running: ", .{});
        for (argv, 0..) |arg, i| std.debug.print("{s}{s}", .{ if (i > 0) " " else "", arg });
        std.debug.print("\x1b[0m\n", .{});

        child.* = std.process.Child.init(argv, arena);
        child.stdout_behavior = if (cfg.quiet) .Ignore else .Inherit;
        child.stderr_behavior = if (cfg.quiet) .Ignore else .Inherit;

        was_started.* = true;
        child.spawn() catch |err| {
            std.debug.print("\x1b[31m✗ Task '{s}' could not start '{s}': {s}\x1b[0m\n\n", .{ label.*, argv[0], @errorName(err) });
            was_started.* = false;
            ok = false;
            continue;
        };
        if (!cfg.parallel) ok = waitAndReport(child, label.*) and ok;
    }

    if (cfg.parallel) {
        for (children, started, labels) |*child, was_started, label| {
            if (was_started) ok = waitAndReport(child, label) and ok;
        }
    }

    return ok;
}

fn waitAndReport(child: *std.process.Child, label: []const u8) bool {
    const term = child.wait() catch |err| {
        std.debug.print("\x1b[31m✗ Task '{s}' could not be awaited: {s}\x1b[0m\n\n", .{ label, @errorName(err) });
        return false;
    };
    switch (term) {
        .Exited => |code| if (code == 0) {
            std.debug.print("\x1b[32m✓ Task '{s}' completed\x1b[0m\n\n", .{label});
            return true;
        } else {
            std.debug.print("\x1b[31m✗ Task '{s}' failed (exit code {d})\x1b[0m\n\n", .{ label, code });
        },
        else => std.debug.print("\x1b[31m✗ Task '{s}' terminated abnormally\x1b[0m\n\n", .{label}),
    }
    return false;
}

/// Builds the command line for one or more targets. More than one target is only
/// meaningful for nx and turbo; package manager scripts take a single target.
/// All memory comes from `arena`.
pub fn buildArgv(
    arena: std.mem.Allocator,
    mgr: detect.Manager,
    orch: detect.Orchestrator,
    targets: []const []const u8,
    affected_base: ?[]const u8,
) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;

    switch (orch) {
        .nx => {
            try argv.appendSlice(arena, &.{ execCommand(mgr), "nx" });
            if (affected_base) |base| {
                try argv.appendSlice(arena, &.{ "affected", "-t" });
                try argv.appendSlice(arena, targets);
                try argv.append(arena, try std.fmt.allocPrint(arena, "--base={s}", .{base}));
            } else {
                try argv.appendSlice(arena, &.{ "run-many", "-t" });
                try argv.appendSlice(arena, targets);
                try argv.append(arena, "--all");
            }
        },
        .turbo => {
            try argv.appendSlice(arena, &.{ execCommand(mgr), "turbo", "run" });
            try argv.appendSlice(arena, targets);
            if (affected_base) |base| {
                try argv.append(arena, try std.fmt.allocPrint(arena, "--filter=[{s}...HEAD]", .{base}));
            }
        },
        else => {
            std.debug.assert(targets.len == 1);
            try argv.appendSlice(arena, &.{ @tagName(mgr), "run", targets[0] });
        },
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

fn expectArgv(expected: []const []const u8, mgr: detect.Manager, orch: detect.Orchestrator, targets: []const []const u8, base: ?[]const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const actual = try buildArgv(arena_state.allocator(), mgr, orch, targets, base);
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| try std.testing.expectEqualStrings(e, a);
}

test "buildArgv: nx" {
    try expectArgv(&.{ "pnpm", "nx", "run-many", "-t", "lint", "--all" }, .pnpm, .nx, &.{"lint"}, null);
    try expectArgv(&.{ "npx", "nx", "affected", "-t", "lint", "--base=origin/main" }, .npm, .nx, &.{"lint"}, "origin/main");
}

test "buildArgv: nx with several targets" {
    try expectArgv(&.{ "pnpm", "nx", "run-many", "-t", "lint", "test", "build", "--all" }, .pnpm, .nx, &.{ "lint", "test", "build" }, null);
    try expectArgv(&.{ "npx", "nx", "affected", "-t", "lint", "test", "--base=HEAD~1" }, .npm, .nx, &.{ "lint", "test" }, "HEAD~1");
}

test "buildArgv: turbo" {
    try expectArgv(&.{ "yarn", "turbo", "run", "lint" }, .yarn, .turbo, &.{"lint"}, null);
    try expectArgv(&.{ "bunx", "turbo", "run", "lint", "--filter=[HEAD~1...HEAD]" }, .bun, .turbo, &.{"lint"}, "HEAD~1");
}

test "buildArgv: turbo with several targets" {
    try expectArgv(&.{ "yarn", "turbo", "run", "lint", "test", "build" }, .yarn, .turbo, &.{ "lint", "test", "build" }, null);
    try expectArgv(&.{ "pnpm", "turbo", "run", "lint", "test", "--filter=[origin/main...HEAD]" }, .pnpm, .turbo, &.{ "lint", "test" }, "origin/main");
}

test "buildArgv: no orchestrator ignores affected" {
    try expectArgv(&.{ "npm", "run", "lint" }, .npm, .none, &.{"lint"}, null);
    try expectArgv(&.{ "bun", "run", "lint" }, .bun, .none, &.{"lint"}, "origin/main");
}
