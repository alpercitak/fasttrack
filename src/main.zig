const std = @import("std");
const utils = @import("utils.zig");

const Orchestrator = enum { nx, turbo, bun, none };
const Manager = enum { pnpm, bun, npm, yarn };
const CIRunner = enum { github, gitlab, bitbucket, generic };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Show help if no args or --help
    if (args.len < 2 or utils.hasArg(args, "--help") or utils.hasArg(args, "-h")) {
        printHelp();
        return;
    }

    const orch = detectOrchestrator();
    const mgr = detectManager();

    std.debug.print("\x1b[34m🔍 Detected: {s} + {s}\x1b[0m\n\n", .{ @tagName(mgr), @tagName(orch) });

    const is_affected = utils.hasArg(args, "--affected");

    // Determine Base Reference (Priority: --base flag > FASTTRACK_BASE env > origin/main)
    const base_from_arg = utils.getArgValue(args, "--base=");
    const base_from_env = std.process.getEnvVarOwned(allocator, "FASTTRACK_BASE") catch null;
    defer if (base_from_env) |env| allocator.free(env);

    const base_ref = base_from_arg orelse (base_from_env orelse "origin/main");
    std.debug.print("\x1b[34m🎯 Base Ref: {s}\x1b[0m\n\n", .{base_ref});

    if (is_affected and orch == .none) {
        std.debug.print("\x1b[33m⚠️  Warning: --affected flag requires nx or turbo\x1b[0m\n", .{});
    }

    var ran_something = false;
    var had_error = false;

    const tasks = [_]struct { flag: []const u8, alt_flag: ?[]const u8, name: []const u8 }{
        .{ .flag = "--format", .alt_flag = "--prettier", .name = "format" },
        .{ .flag = "--lint", .alt_flag = null, .name = "lint" },
        .{ .flag = "--typecheck", .alt_flag = null, .name = "typecheck" },
        .{ .flag = "--test", .alt_flag = null, .name = "test" },
        .{ .flag = "--build", .alt_flag = null, .name = "build" },
    };

    for (tasks) |task| {
        const match = utils.hasArg(args, task.flag) or (task.alt_flag != null and utils.hasArg(args, task.alt_flag.?));
        if (match) {
            runTask(allocator, mgr, orch, task.name, is_affected, base_ref) catch |err| {
                had_error = true;
                std.debug.print("\x1b[31m✗ Error running task '{s}': {}\x1b[0m\n\n", .{ task.name, err });
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
        \\  --build        Run build
        \\  --typecheck    Run type checking
        \\  --affected     Only run on affected projects
        \\  --base=<ref>   Base git ref for --affected (default: origin/main)
        \\  --help, -h     Show this help
        \\
        \\Supported CI Runners:
        \\  • GitHub Actions (GITHUB_REF_NAME)
        \\  • GitLab CI (CI_COMMIT_REF_NAME)
        \\  • Bitbucket Pipelines (BITBUCKET_BRANCH)
        \\  • Generic (GIT_BRANCH)
        \\
        \\Examples:
        \\  fasttrack --lint --test
        \\  fasttrack --lint --affected
        \\  fasttrack --format --lint --test --build
        \\
    , .{});
}

fn detectOrchestrator() Orchestrator {
    if (utils.fileExists("nx.json")) return .nx;
    if (utils.fileExists("turbo.json")) return .turbo;
    if (utils.fileExists("bunfig.toml")) return .bun;
    return .none;
}

fn detectManager() Manager {
    if (utils.fileExists("pnpm-lock.yaml")) return .pnpm;
    if (utils.fileExists("yarn.lock")) return .yarn;
    if (utils.fileExists("bun.lock") or utils.fileExists("bun.lockb")) return .bun;
    return .npm;
}

fn detectCIRunner() CIRunner {
    // Check for GitHub Actions
    _ = std.process.getEnvVarOwned(std.heap.page_allocator, "GITHUB_ACTIONS") catch null;
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "GITHUB_ACTIONS") catch null != null) {
        return .github;
    }
    // Check for GitLab CI
    _ = std.process.getEnvVarOwned(std.heap.page_allocator, "GITLAB_CI") catch null;
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "GITLAB_CI") catch null != null) {
        return .gitlab;
    }
    // Check for Bitbucket Pipelines
    _ = std.process.getEnvVarOwned(std.heap.page_allocator, "BITBUCKET_BUILD_NUMBER") catch null;
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "BITBUCKET_BUILD_NUMBER") catch null != null) {
        return .bitbucket;
    }
    return .generic;
}

fn getCurrentBranch(allocator: std.mem.Allocator, runner: CIRunner) ?[]const u8 {
    const env_var = switch (runner) {
        .github => "GITHUB_REF_NAME",
        .gitlab => "CI_COMMIT_REF_NAME",
        .bitbucket => "BITBUCKET_BRANCH",
        .generic => "GIT_BRANCH",
    };
    return std.process.getEnvVarOwned(allocator, env_var) catch null;
}

fn runTask(
    allocator: std.mem.Allocator,
    mgr: Manager,
    orch: Orchestrator,
    target: []const u8,
    affected: bool,
    base_ref: []const u8,
) !void {
    var argv = std.ArrayListUnmanaged([]const u8){};
    defer argv.deinit(allocator);

    try argv.append(allocator, @tagName(mgr));

    // Detect CI runner and get current branch
    const runner = detectCIRunner();
    const current_branch = getCurrentBranch(allocator, runner) orelse "";
    defer if (current_branch.len > 0) allocator.free(current_branch);

    // Smart detection: if base is origin/main and current is main, use HEAD~1
    const is_on_base = (std.mem.endsWith(u8, base_ref, current_branch) and current_branch.len > 0) or
        (std.mem.eql(u8, current_branch, "main") and std.mem.eql(u8, base_ref, "origin/master"));

    switch (orch) {
        .nx => {
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
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();
    if (term != .Exited or term.Exited != 0) return error.TaskFailed;
    std.debug.print("\x1b[32m✓ Task '{s}' completed\x1b[0m\n\n", .{target});
}
