const std = @import("std");

pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn hasArg(args: []const []const u8, target: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, target)) return true;
    }
    return false;
}

pub fn getArgValue(args: []const []const u8, prefix: []const u8) ?[]const u8 {
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, prefix)) return arg[prefix.len..];
    }
    return null;
}

test "hasArg" {
    const args = [_][]const u8{ "fasttrack", "--lint", "--test" };
    try std.testing.expect(hasArg(&args, "--lint"));
    try std.testing.expect(!hasArg(&args, "--build"));
}

test "getArgValue" {
    const args = [_][]const u8{ "fasttrack", "--base=origin/dev", "--lint" };
    try std.testing.expectEqualStrings("origin/dev", getArgValue(&args, "--base=").?);
    try std.testing.expectEqual(null, getArgValue(&args, "--other="));
}
