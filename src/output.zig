const std = @import("std");

pub fn printHelp() void {
    std.debug.print(
        \\fasttrack - task runner
        \\
        \\Usage: fasttrack [options]
        \\
        \\Tasks:
        \\  --lint         Run linting
        \\  --test         Run tests
        \\  --format       Run formatter (Prettier)
        \\  --build        Run build
        \\  --typecheck    Run type checking
        \\
        \\Options:
        \\  --affected     Only run on affected projects
        \\  --base=<ref>   Base git ref for --affected (default: origin/main)
        \\  --verbose      Show detailed output
        \\  --help, -h     Show this help
        \\
        \\Environment Variables:
        \\  FASTTRACK_BASE    Override default base ref
        \\
        \\Examples:
        \\  fasttrack --lint --test
        \\  fasttrack --lint --affected
        \\
    , .{});
}
