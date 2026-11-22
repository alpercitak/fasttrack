const std = @import("std");
const utils = @import("utils.zig");
const detect = @import("detect.zig");
const output = @import("output.zig");
const runner = @import("runner.zig");
const config = @import("config.zig");

const Task = struct { flag: []const u8, alt_flag: ?[]const u8 = null, name: []const u8 };

const tasks = [_]Task{
    .{ .flag = "--format", .alt_flag = "--prettier", .name = "format" },
    .{ .flag = "--lint", .name = "lint" },
    .{ .flag = "--typecheck", .name = "typecheck" },
    .{ .flag = "--test", .name = "test" },
    .{ .flag = "--build", .name = "build" },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Show help if no args or --help
    if (args.len < 2 or utils.hasArg(args, "--help") or utils.hasArg(args, "-h")) {
        output.printHelp();
        return;
    }

    if (findUnknownArg(args[1..])) |arg| {
        std.debug.print("\x1b[31m✗ Unknown option: {s}\x1b[0m\nUse --help for usage.\n", .{arg});
        std.process.exit(2);
    }

    for (tasks) |task| {
        if (isSelected(args, task)) break;
    } else {
        std.debug.print("\x1b[31m✗ No tasks specified. Use --help for usage.\x1b[0m\n", .{});
        std.process.exit(2);
    }

    const cfg = config.Config{
        .verbose = utils.hasArg(args, "--verbose"),
        .quiet = utils.hasArg(args, "--quiet"),
        .parallel = utils.hasArg(args, "--parallel"),
    };

    const orch = detect.detectOrchestrator();
    const mgr = detect.detectManager();

    std.debug.print("\x1b[34m🔍 Detected: {s} + {s}\x1b[0m\n\n", .{ @tagName(mgr), @tagName(orch) });

    const is_affected = utils.hasArg(args, "--affected");
    if (is_affected and orch != .nx and orch != .turbo) {
        std.debug.print("\x1b[33m⚠️  Warning: --affected requires nx or turbo, running on everything\x1b[0m\n\n", .{});
    }

    const base_ref = try detect.resolveBaseRef(allocator, args);
    defer allocator.free(base_ref);

    const ci = detect.detectCIRunner();
    const branch = detect.getCurrentBranch(allocator, ci);
    defer if (branch) |b| allocator.free(b);

    // On the base branch itself a diff against base is empty, so compare with the previous commit
    const affected_base: ?[]const u8 = if (is_affected and (orch == .nx or orch == .turbo))
        (if (detect.isOnBaseBranch(base_ref, branch orelse "")) "HEAD~1" else base_ref)
    else
        null;

    if (cfg.verbose) {
        std.debug.print("\x1b[34m🧭 CI: {s}, branch: {s}, base ref: {s}\x1b[0m\n\n", .{ @tagName(ci), branch orelse "(unknown)", base_ref });
    }
    if (affected_base) |base| {
        std.debug.print("\x1b[34m🎯 Affected since: {s}\x1b[0m\n\n", .{base});
    }

    var had_error = false;

    if (cfg.parallel) {
        var failed = std.atomic.Value(bool).init(false);
        var threads = std.ArrayList(std.Thread).empty;
        defer threads.deinit(allocator);

        for (tasks) |task| {
            if (isSelected(args, task)) {
                const t = try std.Thread.spawn(.{}, runTaskInThread, .{
                    &failed, allocator, mgr, orch, task.name, affected_base, cfg,
                });
                try threads.append(allocator, t);
            }
        }

        for (threads.items) |t| t.join();
        had_error = failed.load(.monotonic);
    } else {
        for (tasks) |task| {
            if (isSelected(args, task)) {
                runner.runTask(allocator, mgr, orch, task.name, affected_base, cfg) catch {
                    had_error = true;
                };
            }
        }
    }

    if (had_error) std.process.exit(1);
}

const options = [_][]const u8{ "--affected", "--parallel", "--verbose", "--quiet", "--help", "-h" };

fn findUnknownArg(args: []const []const u8) ?[]const u8 {
    outer: for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--base=")) continue;
        for (options) |opt| if (std.mem.eql(u8, arg, opt)) continue :outer;
        for (tasks) |task| {
            if (std.mem.eql(u8, arg, task.flag)) continue :outer;
            if (task.alt_flag) |alt| if (std.mem.eql(u8, arg, alt)) continue :outer;
        }
        return arg;
    }
    return null;
}

test "findUnknownArg" {
    try std.testing.expectEqual(null, findUnknownArg(&.{ "--lint", "--prettier", "--affected", "--base=origin/dev" }));
    try std.testing.expectEqualStrings("--tset", findUnknownArg(&.{ "--lint", "--tset" }).?);
    try std.testing.expectEqualStrings("--base", findUnknownArg(&.{"--base"}).?);
}

fn isSelected(args: []const []const u8, task: Task) bool {
    if (utils.hasArg(args, task.flag)) return true;
    if (task.alt_flag) |alt| return utils.hasArg(args, alt);
    return false;
}

fn runTaskInThread(
    failed: *std.atomic.Value(bool),
    allocator: std.mem.Allocator,
    mgr: detect.Manager,
    orch: detect.Orchestrator,
    target: []const u8,
    affected_base: ?[]const u8,
    cfg: config.Config,
) void {
    runner.runTask(allocator, mgr, orch, target, affected_base, cfg) catch failed.store(true, .monotonic);
}

test {
    std.testing.refAllDecls(@This());
    _ = utils;
    _ = detect;
    _ = runner;
}
