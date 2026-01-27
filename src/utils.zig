const std = @import("std");

pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn isGitRepo() bool {
    return fileExists(".git");
}

pub fn hasArg(args: []const []const u8, target: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, target)) return true;
    }
    return false;
}

pub fn getArgValue(args: []const []const u8, prefix: []const u8) ?[]const u8 {
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, prefix)) {
            if (std.mem.indexOf(u8, arg, "=")) |split_idx| {
                return arg[split_idx + 1 ..];
            }
        }
    }
    return null;
}
