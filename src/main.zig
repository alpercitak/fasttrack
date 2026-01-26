const std = @import("std");

const Orchestrator = enum { nx, turbo, bun, none };
const Manager = enum { pnpm, bun, npm, yarn };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Show help if no args or --help
    if (args.len < 2 or hasArg(args, "--help") or hasArg(args, "-h")) {
        printHelp();
        return;
    }

    const orch = detectOrchestrator();
    const mgr = detectManager();

    std.debug.print("\x1b[34m🔍 Detected: {s} + {s}\x1b[0m\n\n", .{ @tagName(mgr), @tagName(orch) });

    const is_affected = hasArg(args, "--affected");

    // Validate affected flag
    if (is_affected and orch == .none) {
        std.debug.print("\x1b[33m⚠️  Warning: --affected flag requires nx or turbo\x1b[0m\n", .{});
    }

    var ran_something = false;
    var had_error = false;

    // Define tasks in order of execution
    const tasks = [_]struct { flag: []const u8, alt_flag: ?[]const u8, name: []const u8 }{
        .{ .flag = "--format", .alt_flag = "--prettier", .name = "format" },
        .{ .flag = "--lint", .alt_flag = null, .name = "lint" },
        .{ .flag = "--typecheck", .alt_flag = null, .name = "typecheck" },
        .{ .flag = "--test", .alt_flag = null, .name = "test" },
        .{ .flag = "--build", .alt_flag = null, .name = "build" },
    };

    for (tasks) |task| {
        const match = hasArg(args, task.flag) or (task.alt_flag != null and hasArg(args, task.alt_flag.?));
        if (match) {
            runTask(allocator, mgr, orch, task.name, is_affected) catch |err| {
                had_error = true;
                std.debug.print("\x1b[31m✗ Error running task '{s}': {}\x1b[0m\n\n", .{ task.name, err });
                // Continue to next task instead of failing immediately
            };
            ran_something = true;
        }
    }

    if (!ran_something) {
        std.debug.print("\x1b[33m⚠️  No tasks specified. Use --help for usage.\x1b[0m\n", .{});
    } else if (had_error) {
        std.process.exit(1);
    }
}

fn printHelp() void {
    std.debug.print(
        \\fasttrack - task runner
        \\
        \\Usage: fasttrack [options]
        \\
        \\Options:
        \\  --lint         Run linting
        \\  --test         Run tests
        \\  --format       Run formatter (Prettier)
        \\  --prettier     Alias for --format
        \\  --build        Run build
        \\  --typecheck    Run type checking
        \\  --affected     Only run on affected projects (requires nx/turbo)
        \\  --help, -h     Show this help
        \\
        \\Examples:
        \\  fasttrack --lint --test
        \\  fasttrack --lint --affected
        \\  fasttrack --format --lint --test --build
        \\
    , .{});
}

fn detectOrchestrator() Orchestrator {
    // Priority: nx > turbo > bun > none
    if (fileExists("nx.json")) return .nx;
    if (fileExists("turbo.json")) return .turbo;
    if (fileExists("bunfig.toml")) return .bun; // Bun workspaces
    return .none;
}

fn detectManager() Manager {
    // Priority: pnpm > yarn > bun > npm
    if (fileExists("pnpm-lock.yaml")) return .pnpm;
    if (fileExists("yarn.lock")) return .yarn;
    if (fileExists("bun.lock") or fileExists("bun.lockb")) return .bun;
    if (fileExists("package-lock.json")) return .npm;
    return .npm; // Default fallback
}

fn runTask(
    allocator: std.mem.Allocator,
    mgr: Manager,
    orch: Orchestrator,
    target: []const u8,
    affected: bool,
) !void {
    var argv = std.ArrayListUnmanaged([]const u8){};
    defer argv.deinit(allocator);

    // Base command
    try argv.append(allocator, @tagName(mgr));

    // Orchestrator-specific logic
    switch (orch) {
        .nx => {
            try argv.append(allocator, "nx");
            try argv.append(allocator, if (affected) "affected" else "run-many");
            try argv.append(allocator, "-t");
            try argv.append(allocator, target);
            if (!affected) {
                try argv.append(allocator, "--all");
            }
        },
        .turbo => {
            try argv.append(allocator, "turbo");
            try argv.append(allocator, "run");
            try argv.append(allocator, target);
            if (affected) {
                try argv.append(allocator, "--filter=[origin/main...HEAD]");
            }
        },
        .bun => {
            try argv.append(allocator, "run");
            try argv.append(allocator, target);
            // Note: bun doesn't support filtering like nx/turbo
            // --affected flag is ignored for bun
        },
        .none => {
            try argv.append(allocator, "run");
            try argv.append(allocator, target);
        },
    }

    // Print command
    std.debug.print("\x1b[36m» Running: ", .{});
    for (argv.items, 0..) |arg, i| {
        if (i > 0) std.debug.print(" ", .{});
        std.debug.print("{s}", .{arg});
    }
    std.debug.print("\x1b[0m\n", .{});

    // Run command
    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();

    // Check exit code
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("\x1b[31m✗ Task '{s}' failed with code {d}\x1b[0m\n", .{ target, code });
                return error.TaskFailed;
            }
            std.debug.print("\x1b[32m✓ Task '{s}' completed\x1b[0m\n\n", .{target});
        },
        else => {
            std.debug.print("\x1b[31m✗ Task '{s}' terminated abnormally\x1b[0m\n", .{target});
            return error.TaskFailed;
        },
    }
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn hasArg(args: []const []const u8, target: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, target)) return true;
    }
    return false;
}
