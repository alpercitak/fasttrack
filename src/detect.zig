const std = @import("std");
const utils = @import("utils.zig");

pub const Orchestrator = enum { nx, turbo, none };
pub const Manager = enum { pnpm, bun, npm, yarn };
pub const CIRunner = enum { github, gitlab, bitbucket, generic };

pub fn detectOrchestrator() Orchestrator {
    if (utils.fileExists("nx.json")) return .nx;
    if (utils.fileExists("turbo.json")) return .turbo;
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
    // Empty values (e.g. an unset CI variable expanded to "") count as not given
    if (utils.getArgValue(args, "--base=")) |val| {
        if (val.len > 0) return try allocator.dupe(u8, val);
    }

    if (std.process.getEnvVarOwned(allocator, "FASTTRACK_BASE")) |env_val| {
        if (env_val.len > 0) return env_val;
        allocator.free(env_val);
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

test "resolveBaseRef" {
    const a = std.testing.allocator;
    const given = try resolveBaseRef(a, &.{ "fasttrack", "--base=origin/dev" });
    defer a.free(given);
    try std.testing.expectEqualStrings("origin/dev", given);

    // Falls through to FASTTRACK_BASE or the default, depending on the environment
    const empty = try resolveBaseRef(a, &.{ "fasttrack", "--base=" });
    defer a.free(empty);
    try std.testing.expect(empty.len > 0);
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
