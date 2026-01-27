const std = @import("std");
const utils = @import("utils.zig");
const detect = @import("detect.zig");
const output = @import("output.zig");
const runner = @import("runner.zig");
const config = @import("config.zig");

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

    const cfg = config.Config{
        .verbose = utils.hasArg(args, "--verbose"),
        .parallel = utils.hasArg(args, "--parallel"),
    };

    const orch = detect.detectOrchestrator();
    const mgr = detect.detectManager();

    std.debug.print("\x1b[34m🔍 Detected: {s} + {s}\x1b[0m\n\n", .{ @tagName(mgr), @tagName(orch) });

    const is_affected = utils.hasArg(args, "--affected");

    const base_ref = try detect.resolveBaseRef(allocator, args);
    defer allocator.free(base_ref); // Handles all cases: arg, env, or default
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

    if (cfg.parallel) {
        var threads = std.ArrayList(std.Thread).empty;
        defer threads.deinit(allocator);

        for (tasks) |task| {
            if (utils.hasArg(args, task.flag) or
                (task.alt_flag != null and utils.hasArg(args, task.alt_flag.?)))
            {
                const t = try std.Thread.spawn(.{}, runner.runTask, .{
                    allocator, mgr, orch, task.name, is_affected, base_ref, cfg,
                });
                try threads.append(allocator, t);
                ran_something = true;
            }
        }

        for (threads.items) |t| t.join();
    } else {
        for (tasks) |task| {
            const match = utils.hasArg(args, task.flag) or (task.alt_flag != null and utils.hasArg(args, task.alt_flag.?));
            if (match) {
                runner.runTask(allocator, mgr, orch, task.name, is_affected, base_ref, cfg) catch {
                    had_error = true;
                };
                ran_something = true;
            }
        }
    }

    if (!ran_something) {
        std.debug.print("\x1b[33m⚠️  No tasks specified. Use --help for usage.\x1b[0m\n", .{});
    } else if (had_error) {
        std.process.exit(1);
    }
}
