const std = @import("std");
const utils = @import("utils.zig");

pub const Orchestrator = enum { nx, turbo, bun, none };
pub const Manager = enum { pnpm, bun, npm, yarn };
pub const CIRunner = enum { github, gitlab, bitbucket, generic };

pub fn detectOrchestrator() Orchestrator {
    if (utils.fileExists("nx.json")) return .nx;
    if (utils.fileExists("turbo.json")) return .turbo;
    if (utils.fileExists("bunfig.toml")) return .bun;
    return .none;
}

pub fn detectManager() Manager {
    if (utils.fileExists("pnpm-lock.yaml")) return .pnpm;
    if (utils.fileExists("yarn.lock")) return .yarn;
    if (utils.fileExists("bun.lock") or utils.fileExists("bun.lockb")) return .bun;
    return .npm;
}

pub fn detectCIRunner() CIRunner {
    const envVars = [_]struct { name: []const u8, runner: CIRunner }{
        .{ .name = "GITHUB_ACTIONS", .runner = .github },
        .{ .name = "GITLAB_CI", .runner = .gitlab },
        .{ .name = "BITBUCKET_BUILD_NUMBER", .runner = .bitbucket },
    };

    for (envVars) |env| {
        if (std.process.hasEnvVar(std.heap.page_allocator, env.name) catch false) {
            return env.runner;
        }
    }
    return .generic;
}

pub fn getCurrentBranch(allocator: std.mem.Allocator, runner: CIRunner) ?[]const u8 {
    const env_var = switch (runner) {
        .github => "GITHUB_REF_NAME",
        .gitlab => "CI_COMMIT_REF_NAME",
        .bitbucket => "BITBUCKET_BRANCH",
        .generic => "GIT_BRANCH",
    };
    return std.process.getEnvVarOwned(allocator, env_var) catch null;
}

// Determine Base Reference (Priority: --base flag > FASTTRACK_BASE env > origin/main)
pub fn resolveBaseRef(allocator: std.mem.Allocator, args: []const []const u8) ![]const u8 {
    if (utils.getArgValue(args, "--base=")) |val| {
        return try allocator.dupe(u8, val);
    }

    if (std.process.getEnvVarOwned(allocator, "FASTTRACK_BASE")) |env_val| {
        return env_val;
    } else |_| {}

    return try allocator.dupe(u8, "origin/main");
}

/// True when the current branch is the branch `base_ref` points to (e.g. `main` vs `origin/main`).
/// Diffing a branch against itself finds nothing, so callers fall back to the previous commit.
pub fn isOnBaseBranch(base_ref: []const u8, branch: []const u8) bool {
    if (branch.len == 0) return false;
    if (std.mem.eql(u8, base_ref, branch)) return true;
    const remote = "origin/";
    return std.mem.startsWith(u8, base_ref, remote) and std.mem.eql(u8, base_ref[remote.len..], branch);
}

test "isOnBaseBranch" {
    try std.testing.expect(isOnBaseBranch("origin/main", "main"));
    try std.testing.expect(isOnBaseBranch("main", "main"));
    try std.testing.expect(isOnBaseBranch("origin/release/1.0", "release/1.0"));
    try std.testing.expect(!isOnBaseBranch("origin/main", "ain"));
    try std.testing.expect(!isOnBaseBranch("origin/main", "feature/main"));
    try std.testing.expect(!isOnBaseBranch("origin/master", "main"));
    try std.testing.expect(!isOnBaseBranch("origin/main", ""));
}
