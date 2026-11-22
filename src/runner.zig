const std = @import("std");
const detect = @import("detect.zig");
const config = @import("config.zig");

pub fn runTask(
    allocator: std.mem.Allocator,
    mgr: detect.Manager,
    orch: detect.Orchestrator,
    target: []const u8,
    affected: bool,
    base_ref: []const u8,
    cfg: config.Config,
) !void {
    var argv = std.ArrayListUnmanaged([]const u8){};
    defer argv.deinit(allocator);

    // Detect CI runner and get current branch
    const runner = detect.detectCIRunner();
    const current_branch = detect.getCurrentBranch(allocator, runner) orelse "";
    defer if (current_branch.len > 0) allocator.free(current_branch);

    // Smart detection: if base is origin/main and current is main, use HEAD~1
    const is_on_base = (std.mem.endsWith(u8, base_ref, current_branch) and current_branch.len > 0) or
        (std.mem.eql(u8, current_branch, "main") and std.mem.eql(u8, base_ref, "origin/master"));

    switch (orch) {
        .nx => {
            try argv.append(allocator, execCommand(mgr));
            try argv.append(allocator, "nx");
            try argv.append(allocator, if (affected) "affected" else "run-many");
            try argv.append(allocator, "-t");
            try argv.append(allocator, target);
            if (affected) {
                const base = if (is_on_base) "HEAD~1" else base_ref;
                const base_arg = try std.fmt.allocPrint(allocator, "--base={s}", .{base});
                try argv.append(allocator, base_arg);
            } else {
                try argv.append(allocator, "--all");
            }
        },
        .turbo => {
            try argv.append(allocator, execCommand(mgr));
            try argv.append(allocator, "turbo");
            try argv.append(allocator, "run");
            try argv.append(allocator, target);
            if (affected) {
                const diff = if (is_on_base) "HEAD~1...HEAD" else try std.fmt.allocPrint(allocator, "{s}...HEAD", .{base_ref});
                const filter = try std.fmt.allocPrint(allocator, "--filter=[{s}]", .{diff});
                try argv.append(allocator, filter);
            }
        },
        else => {
            try argv.append(allocator, @tagName(mgr));
            try argv.append(allocator, "run");
            try argv.append(allocator, target);
        },
    }

    // Print and Execute
    std.debug.print("\x1b[36m» Running: ", .{});
    for (argv.items, 0..) |arg, i| {
        std.debug.print("{s}{s}", .{ if (i > 0) " " else "", arg });
    }
    std.debug.print("\x1b[0m\n", .{});

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = if (cfg.quiet) .Ignore else .Inherit;
    child.stderr_behavior = if (cfg.quiet) .Ignore else .Inherit;

    const term = child.spawnAndWait() catch |err| {
        std.debug.print("\x1b[31m✗ Task '{s}' could not start '{s}': {s}\x1b[0m\n\n", .{ target, argv.items[0], @errorName(err) });
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
