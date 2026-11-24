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
        \\  --format       Run formatter (alias: --prettier)
        \\  --build        Run build
        \\  --typecheck    Run type checking
        \\
        \\Options:
        \\  --affected     Only run on affected projects (requires nx/turbo)
        \\  --base=<ref>   Base git ref for --affected (default: origin/main)
        \\  --parallel     Run tasks in parallel
        \\  --quiet        Hide task output (only show status lines)
        \\  --verbose      Show CI/branch detection details
        \\  --help, -h     Show this help
        \\
        \\Environment Variables:
        \\  FASTTRACK_BASE    Override default base ref
        \\
        \\Examples:
        \\  fasttrack --lint --test
        \\  fasttrack --lint --affected
        \\  fasttrack --build --test --parallel --affected
        \\
    , .{});
}
